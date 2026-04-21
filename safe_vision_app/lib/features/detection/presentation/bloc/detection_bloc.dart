import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/tracked_detection.dart';
import '../../domain/services/alert_policy_engine.dart';
import '../../domain/services/object_tracker.dart';
import '../../domain/services/realtime_pipeline_monitor.dart';
import '../../domain/services/vision_quality_evaluator.dart';
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
  bool _modelReleased = true;
  int _frameEpoch = 0;

  final ObjectTracker _tracker = ObjectTracker();
  final AlertPolicyEngine _alertPolicy = AlertPolicyEngine();
  final RealtimePipelineMonitor _pipelineMonitor = RealtimePipelineMonitor();

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
      _frameEpoch++;
      emit(const DetectionLoading());
      _tracker.clear();
      _alertPolicy.reset();
      _pipelineMonitor.reset();

      try {
        await _releaseModelIfNeeded();
        await _loadModel.call(const NoParams());
        _modelReleased = false;
        emit(const DetectionModelReady());
      } catch (e) {
        _modelReleased = true;
        debugPrint('[DetectionBloc] loadModel failed: $e');
        emit(DetectionFailure(e.toString()));
      }
    });
  }

  Future<void> _onStopped(
    DetectionStopped event,
    Emitter<DetectionState> emit,
  ) async {
    await _serializeLifecycle(() async {
      _frameEpoch++;
      _tracker.clear();
      _alertPolicy.reset();
      _pipelineMonitor.reset();
      await _releaseModelIfNeeded(force: true);
      emit(const DetectionInitial());
    });
  }

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    final canProcessFrame = _stateAllowsFrames;
    if (!canProcessFrame) {
      event.onDone();
      return;
    }

    final frameEpoch = _frameEpoch;

    try {
      final frameStartedAt = DateTime.now();
      final visibilityScore = VisionQualityEvaluator.score(event.frame);
      final lowVisibility =
          visibilityScore < AppConstants.lowVisibilityThreshold;
      _pipelineMonitor.onVisibilityUpdated(
        lowVisibility: lowVisibility,
        visibilityScore: visibilityScore,
      );

      final detections = await _detectFromFrame(
        event.frame,
        rotationDegrees: event.rotationDegrees,
      );
      final inferenceMs =
          DateTime.now().difference(frameStartedAt).inMicroseconds / 1000.0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _pipelineMonitor.onFrameProcessed(
        nowMs: nowMs,
        inferenceMs: inferenceMs,
      );

      final canEmitResult = _stateAllowsFrames;
      if (!canEmitResult || frameEpoch != _frameEpoch) return;

      final tracked = _tracker.update(detections);

      emit(DetectionSuccess(
        detections: detections,
        trackedDetections: tracked,
        timestamp: nowMs,
        pipelineMetrics: _pipelineMonitor.snapshot(nowMs),
      ));

      _handleWarnings(
        trackedDetections: tracked,
        lowVisibility: lowVisibility,
        nowMs: nowMs,
      );
    } catch (e) {
      debugPrint('[DetectionBloc] inference error (frame skipped): $e');
    } finally {
      event.onDone();
    }
  }

  // ── Warning policy ──────────────────────────────────────────────────────────

  void _handleWarnings({
    required List<TrackedDetection> trackedDetections,
    required bool lowVisibility,
    required int nowMs,
  }) {
    final decision = _alertPolicy.evaluate(
      trackedDetections: trackedDetections,
      lowVisibility: lowVisibility,
      nowMs: nowMs,
    );
    if (decision == null) return;

    _onWarning(
      text: decision.text,
      immediate: decision.immediate,
      withVibration: decision.withVibration,
    );
    _pipelineMonitor.onAlertSent(nowMs);
  }

  void recordDroppedFrame(PipelineDropReason reason) {
    _pipelineMonitor.onFrameDropped(reason);
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    _frameEpoch++;
    await _releaseModelIfNeeded();
    return super.close();
  }
}
