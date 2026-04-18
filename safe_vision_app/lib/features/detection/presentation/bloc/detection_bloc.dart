import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/detection_object.dart';
import '../../domain/services/object_tracker.dart';
import '../../domain/usecases/close_model_usecase.dart';
import '../../domain/usecases/detection_object_from_frame.dart';
import '../../domain/usecases/load_model_usecase.dart';
import 'detection_event.dart';
import 'detection_state.dart';

// ── Warning callback ──────────────────────────────────────────────────────────

typedef DetectionWarningCallback = void Function({
  required String text,
  required bool immediate,
  required bool withVibration,
});

// ── Track stability bookkeeping ───────────────────────────────────────────────

/// Minimum consecutive frames a track must be seen before announcing.
const int _kStabilityFrames = 2;

/// Per-track warning throttle state.
class _TrackInfo {
  int seenCount = 0;
  bool warned = false;
}

// ── DetectionBloc ─────────────────────────────────────────────────────────────

class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
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
    on<DetectionStarted>(_onStarted, transformer: sequential());
    on<DetectionStopped>(_onStopped, transformer: sequential());
    on<DetectionFrameReceived>(_onFrameReceived, transformer: droppable());
  }

  final LoadModelUsecase _loadModel;
  final CloseModelUsecase _closeModel;
  final DetectionObjectFromFrame _detectFromFrame;
  final DetectionWarningCallback _onWarning;
  Future<void> _lifecycleTail = Future<void>.value();
  bool _acceptFrames = false;
  bool _modelReleased = true;
  int _frameEpoch = 0;

  final ObjectTracker _tracker = ObjectTracker();

  // FIX (Bug 7): keyed by label STRING, not label.hashCode.
  // Hashing can collide — e.g. "person".hashCode == "car".hashCode in theory —
  // causing two distinct objects to share the same _TrackInfo entry, which
  // would suppress warnings for one of them entirely.
  final Map<String, _TrackInfo> _trackInfos = {};

  bool get _stateAllowsFrames =>
      state is DetectionModelReady || state is DetectionSuccess;

  Future<void> _serializeLifecycle(Future<void> Function() operation) {
    final previous = _lifecycleTail.catchError((_) {});
    final next = previous.then((_) => operation());
    _lifecycleTail = next;
    return next;
  }

  Future<void> _releaseModelIfNeeded({bool force = false}) async {
    if (!force && _modelReleased) return;

    try {
      await _closeModel.call(const NoParams());
    } catch (e) {
      debugPrint('[DetectionBloc] closeModel error (ignored): $e');
    } finally {
      _modelReleased = true;
    }
  }

  // ── Event handlers ──────────────────────────────────────────────────────────

  Future<void> _onStarted(
    DetectionStarted event,
    Emitter<DetectionState> emit,
  ) async {
    await _serializeLifecycle(() async {
      _acceptFrames = false;
      _frameEpoch++;
      emit(const DetectionLoading());
      _tracker.clear();
      _trackInfos.clear();

      try {
        await _releaseModelIfNeeded();
        await _loadModel.call(const NoParams());
        _modelReleased = false;
        _acceptFrames = true;
        emit(const DetectionModelReady());
      } catch (e, st) {
        _acceptFrames = false;
        _modelReleased = true;
        debugPrint('[DetectionBloc] loadModel failed: $e\n$st');
        emit(DetectionFailure(e.toString()));
      }
    });
  }

  Future<void> _onStopped(
    DetectionStopped event,
    Emitter<DetectionState> emit,
  ) async {
    await _serializeLifecycle(() async {
      _acceptFrames = false;
      _frameEpoch++;
      _tracker.clear();
      _trackInfos.clear();
      await _releaseModelIfNeeded(force: true);
      emit(const DetectionInitial());
    });
  }

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    final canProcessFrame =
        _acceptFrames || (_modelReleased && _stateAllowsFrames);
    if (!canProcessFrame) {
      event.onDone();
      return;
    }

    final frameEpoch = _frameEpoch;

    try {
      final detections = await _detectFromFrame(
        event.frame,
        rotationDegrees: event.rotationDegrees,
      );

      final canEmitResult =
          _acceptFrames || (_modelReleased && _stateAllowsFrames);
      if (!canEmitResult || frameEpoch != _frameEpoch) return;

      final tracked = _tracker.update(detections);

      emit(DetectionSuccess(
        detections: detections,
        trackedDetections: tracked,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      _handleWarnings(detections);
    } catch (e) {
      debugPrint('[DetectionBloc] inference error (frame skipped): $e');
    } finally {
      event.onDone();
    }
  }

  // ── Warning throttle ────────────────────────────────────────────────────────

  void _handleWarnings(List<DetectionObject> detections) {
    if (detections.isEmpty) return;

    // FIX (Bug 7): use label string as key instead of label.hashCode.
    // hashCode can collide across different label strings, merging track state
    // for unrelated objects and silently suppressing warnings for one of them.
    final currentLabels = detections.map((d) => d.label).toSet();
    _trackInfos.removeWhere((label, _) => !currentLabels.contains(label));

    for (final detection in detections) {
      // FIX (Bug 7): key is the label string, not its hashCode.
      final trackKey = detection.label;
      final info = _trackInfos.putIfAbsent(trackKey, _TrackInfo.new);

      info.seenCount++;

      // Wait for _kStabilityFrames before the first warning.
      if (info.seenCount < _kStabilityFrames) continue;

      // Safe objects warn once; dangerous objects re-warn on every frame.
      if (info.warned && !detection.isDangerous) continue;
      _onWarning(
        text: detection.voiceWarning,
        immediate: detection.isDangerous,
        withVibration: detection.isDangerous,
      );

      // Dangerous objects re-warn every time; safe ones warn once per track.
      if (!detection.isDangerous) info.warned = true;
    }
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    _acceptFrames = false;
    _frameEpoch++;
    await _releaseModelIfNeeded();
    return super.close();
  }
}
