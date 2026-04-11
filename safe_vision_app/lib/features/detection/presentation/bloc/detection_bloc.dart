import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/detection_object.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/usecases/load_model_usecase.dart';
import '../../domain/usecases/close_model_usecase.dart';
import '../../domain/usecases/detection_object_from_frame.dart';
import '../../../../core/utils/perf_monitor.dart';
import 'detection_event.dart';
import 'detection_state.dart';

typedef DetectionWarningCallback = void Function({
  required String text,
  required bool immediate,
  required bool withVibration,
});

/// Coordinates the detection lifecycle: loading the model, processing camera
/// frames, emitting TTS warnings, and tracking approaching motion.
///
/// Frame locking is handled entirely by [CameraService] through
/// [DetectionFrameReceived.onDone]. This BLoC does not guard concurrent frames
/// on its own, so [onDone] must always be called from a `finally` block.
///
/// Warnings are emitted when:
/// - An object appears continuously for at least 3 frames.
/// - The bounding-box area grows by more than 30% compared to the previous
///   frame, which signals an approaching object.
class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final LoadModelUsecase _loadModel;
  final CloseModelUsecase _closeModel;
  final DetectionObjectFromFrame _detectFromFrame;
  final DetectionWarningCallback _onWarning;

  Map<String, List<double>> _previousObjects = {};
  Map<String, int> _consecutiveFrames = {};

  /// Reusable sort buffer — avoids a heap allocation on every frame.
  final List<DetectionObject> _sortBuffer = [];

  Future<void>? _closeFuture;

  DetectionBloc({
    required LoadModelUsecase loadModel,
    required CloseModelUsecase closeModel,
    required DetectionObjectFromFrame detectFromFrame,
    required DetectionWarningCallback onWarning,
  })  : _loadModel = loadModel,
        _closeModel = closeModel,
        _detectFromFrame = detectFromFrame,
        _onWarning = onWarning,
        super(const DetectionInitial()) {
    on<DetectionStarted>(_onStarted);
    on<DetectionStopped>(_onStopped);
    on<DetectionFrameReceived>(_onFrameReceived, transformer: droppable());
  }

  Future<void> _onStarted(
    DetectionStarted event,
    Emitter<DetectionState> emit,
  ) async {
    if (_closeFuture != null) {
      try {
        await _closeFuture;
      } catch (e) {
        debugPrint('[DetectionBloc] _closeFuture threw on restart: $e');
      } finally {
        _closeFuture = null;
      }
    }
    _previousObjects = {};
    _consecutiveFrames = {};
    _sortBuffer.clear();
    if (kDebugMode) debugPrint('[DetectionBloc] loading model...');
    emit(const DetectionLoading());
    try {
      await _loadModel.call(const NoParams());
      if (kDebugMode) debugPrint('[DetectionBloc] model loaded');
      emit(const DetectionModelReady());
    } catch (e) {
      debugPrint('[DetectionBloc] model load FAILED: $e');
      emit(DetectionFailure(e.toString()));
    }
  }

  Future<void> _onStopped(
    DetectionStopped event,
    Emitter<DetectionState> emit,
  ) async {
    _previousObjects.clear();
    _consecutiveFrames.clear();
    _sortBuffer.clear();
    emit(const DetectionInitial());
    _closeFuture = _closeModel.call(const NoParams());
    try {
      await _closeFuture;
    } catch (e) {
      debugPrint('[DetectionBloc] closeModel error: $e');
    } finally {
      _closeFuture = null;
    }
  }

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    // FIX (Bug #5 — accepted Debate 1):
    //
    // Guard: release the camera lock immediately when the model is not ready.
    //
    // WITHOUT this guard, frames dispatched during model loading or teardown
    // call _detectFromFrame while _isolateSendPort may be null or the
    // interpreter is being released. The datasource handles this safely
    // (returns [] when !_modelLoaded), but the frame still consumes the
    // 2.5s inference timeout budget before returning, and the camera lock
    // is held for that entire duration — stalling all subsequent frames.
    //
    // The three non-inference states:
    //   DetectionInitial  — model is stopped, closeModel may be in-flight
    //   DetectionLoading  — model is initializing, isolate not yet ready
    //   DetectionFailure  — model failed, isolate is in unknown state
    //
    // In all three cases the correct behavior is: release the lock
    // immediately and let the UI handle the state (spinner, error widget).
    // The existing DetectionLoading UI already shows "Đang tải mô hình AI..."
    // so frame drops during loading are expected and do not require
    // additional user feedback beyond what is already rendered.
    //
    // DetectionModelReady and DetectionSuccess are the only states where
    // inference is safe to attempt.
    if (state is DetectionInitial ||
        state is DetectionLoading ||
        state is DetectionFailure) {
      if (kDebugMode) {
        debugPrint(
          '[DetectionBloc] frame skipped — model not ready '
          '(state: ${state.runtimeType})',
        );
      }
      event.onDone(); // Always release CameraService frame lock
      return;
    }

    final sw = kDebugMode ? (Stopwatch()..start()) : null;

    try {
      final detections = await _detectFromFrame(
        event.image,
        rotationDegrees: event.rotationDegrees,
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[DetectionBloc] inference timeout — skipping frame');
          }
          return [];
        },
      );

      if (kDebugMode) {
        sw?.stop();
        PerfMonitor.inferenceCompleted(sw?.elapsedMilliseconds ?? 0);
        PerfMonitor.frameReceived();
        if (detections.isNotEmpty) {
          debugPrint('[DetectionBloc] detections=${detections.length}');
        }
      }

      emit(DetectionSuccess(
        detections: detections,
        timestamp: DateTime.now().microsecondsSinceEpoch,
      ));

      if (detections.isEmpty) return;

      _triggerWarningIfNeeded(detections);
    } catch (e) {
      debugPrint('[DetectionBloc] _onFrameReceived error: $e');
    } finally {
      // onDone() releases CameraService._isProcessingFrame so the next
      // frame can be dispatched. Must be called unconditionally — including
      // on the early-return path above, on timeout, and on exception.
      event.onDone();
    }
  }

  void _triggerWarningIfNeeded(List<DetectionObject> detections) {
    final currentObjects = _groupAreasByLabel(detections);

    _sortBuffer
      ..clear()
      ..addAll(detections)
      ..sort((a, b) {
        final labelCompare = a.label.compareTo(b.label);
        if (labelCompare != 0) return labelCompare;
        return b.boundingBox.area.compareTo(a.boundingBox.area);
      });

    final candidates = <DetectionObject>[];
    final currentIndices = <String, int>{};
    final newConsecutive = <String, int>{};

    for (final d in _sortBuffer) {
      final currentIndex = currentIndices.update(
        d.label,
        (value) => value + 1,
        ifAbsent: () => 0,
      );

      final presenceKey = '${d.label}_$currentIndex';
      final prevCount = _consecutiveFrames[presenceKey] ?? 0;
      final currentCount = prevCount + 1;
      newConsecutive[presenceKey] = currentCount;

      final previousAreas = _previousObjects[d.label];
      final oldArea =
          previousAreas != null && currentIndex < previousAreas.length
              ? previousAreas[currentIndex]
              : null;

      final isApproaching =
          oldArea != null && d.boundingBox.area > oldArea * 1.3;
      final isStable = currentCount == 3;
      final isFirstSeen = currentCount == 1;

      if (isApproaching || isStable || isFirstSeen) candidates.add(d);
    }

    _previousObjects = currentObjects;
    _consecutiveFrames = newConsecutive;

    if (candidates.isEmpty) return;

    final dangerous = candidates.where((d) => d.isDangerous).toList()
      ..sort((a, b) => b.boundingBox.area.compareTo(a.boundingBox.area));

    if (dangerous.isNotEmpty) {
      _onWarning(
        text: dangerous.first.voiceWarning,
        immediate: true,
        withVibration: true,
      );
    } else {
      final top = candidates.reduce(
        (a, b) => a.confidence > b.confidence ? a : b,
      );
      _onWarning(
        text: top.voiceWarning,
        immediate: false,
        withVibration: false,
      );
    }
  }

  Map<String, List<double>> _groupAreasByLabel(
    List<DetectionObject> detections,
  ) {
    final grouped = <String, List<double>>{};
    for (final detection in detections) {
      grouped
          .putIfAbsent(detection.label, () => <double>[])
          .add(detection.boundingBox.area);
    }
    for (final areas in grouped.values) {
      areas.sort((a, b) => b.compareTo(a));
    }
    return grouped;
  }

  @override
  Future<void> close() async {
    _sortBuffer.clear();
    if (_closeFuture != null) {
      try {
        await _closeFuture;
      } catch (_) {}
    }
    return super.close();
  }
}
