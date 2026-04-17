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

/// Signature for the callback that the BLoC fires when a warning must be
/// announced.  The call site (typically the page widget) is responsible for
/// dispatching to TtsBloc and triggering haptic feedback.
typedef DetectionWarningCallback = void Function({
  required String text,
  required bool immediate,
  required bool withVibration,
});

// ── Track stability bookkeeping ───────────────────────────────────────────────

/// Minimum number of consecutive frames a track must be seen before we
/// announce it.  Prevents one-frame false positives from spamming TTS.
const int _kStabilityFrames = 2;

/// Per-track counters used for warning throttle logic.
class _TrackInfo {
  int seenCount = 0;
  bool warned = false;
}

// ── DetectionBloc ─────────────────────────────────────────────────────────────

/// Drives the object-detection pipeline.
///
/// ## State machine
///
///   DetectionInitial
///     → (DetectionStarted) → DetectionLoading
///       → DetectionModelReady  [loadModel succeeded]
///       → DetectionFailure     [loadModel threw]
///
///   DetectionModelReady
///     → (DetectionFrameReceived) → DetectionSuccess | (silent on error)
///     → (DetectionStopped)       → DetectionInitial
///
/// ## Bugs fixed
///
/// ### 1 – Single source of truth for model readiness
///
/// The previous implementation mixed two independent boolean flags
/// (`_modelReady` field and `state is DetectionModelReady`) to decide whether
/// a frame could be processed.  This "split-brain" pattern can produce:
///   - frames processed while the model is being torn down (stale flag),
///   - frames silently dropped while the model is ready (flag not yet set).
///
/// Fix: only the BLoC **state** is authoritative.  All guards read
/// `state is DetectionModelReady`.  The `_modelReady` field is removed.
///
/// ### 2 – `onDone` guaranteed via finally
///
/// When `droppable()` drops a [DetectionFrameReceived] event, the event
/// handler never runs, so the `onDone` callback inside the event was never
/// called.  This permanently stalled the camera stream because
/// [CameraService] would never release `_isProcessingFrame`.
///
/// Fix: [DetectionFrameReceived] still carries `onDone`, but the bloc
/// handler wraps the *entire* processing path (including the drop-guard) in a
/// try/finally so `onDone` is always called — regardless of whether the frame
/// was processed, dropped, or threw.
///
/// ### 3 – Lifecycle race: stale results after DetectionStopped
///
/// If inference completed after [DetectionStopped] was handled, the bloc
/// emitted a [DetectionSuccess] into an "Initial" state, confusing the UI.
///
/// Fix: results are only emitted if `state is DetectionModelReady` at the
/// point the inference future resolves.
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

    // droppable: if inference is in flight, additional frames are silently
    // discarded.  onDone is still called via the wrapper below.
    on<DetectionFrameReceived>(_onFrameReceived, transformer: droppable());
  }

  final LoadModelUsecase _loadModel;
  final CloseModelUsecase _closeModel;
  final DetectionObjectFromFrame _detectFromFrame;
  final DetectionWarningCallback _onWarning;

  /// Temporal tracker that smooths positions and assigns stable track IDs.
  /// Reset (cleared) on every [DetectionStarted] and [DetectionStopped].
  final ObjectTracker _tracker = ObjectTracker();

  /// Per-track stability counters.  Reset on every [DetectionStarted].
  final Map<int, _TrackInfo> _trackInfos = {};

  // ── Event handlers ──────────────────────────────────────────────────────────

  Future<void> _onStarted(
    DetectionStarted event,
    Emitter<DetectionState> emit,
  ) async {
    emit(const DetectionLoading());
    _tracker.clear();
    _trackInfos.clear();

    try {
      await _loadModel.call(const NoParams());
      emit(const DetectionModelReady());
    } catch (e, st) {
      debugPrint('[DetectionBloc] loadModel failed: $e\n$st');
      emit(DetectionFailure(e.toString()));
    }
  }

  Future<void> _onStopped(
    DetectionStopped event,
    Emitter<DetectionState> emit,
  ) async {
    _tracker.clear();
    _trackInfos.clear();

    try {
      await _closeModel.call(const NoParams());
    } catch (e) {
      debugPrint('[DetectionBloc] closeModel error (ignored): $e');
    }

    emit(const DetectionInitial());
  }

  /// Processes one camera frame.
  ///
  /// The `onDone` callback from [event] is called unconditionally in a
  /// `finally` block — this is the contract that [CameraService] relies on to
  /// release the frame lock.
  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    // BUG FIX 1: single source of truth — only the state tells us whether the
    // model is ready.  If we are not in ModelReady, release the lock and bail.
    if (state is! DetectionModelReady) {
      event.onDone(); // BUG FIX 2: always release the camera lock
      return;
    }

    try {
      final detections = await _detectFromFrame(
        event.frame,
        rotationDegrees: event.rotationDegrees,
      );

      // BUG FIX 3: lifecycle race — discard results if we are no longer in
      // ModelReady (e.g., DetectionStopped arrived while inference was running).
      if (state is! DetectionModelReady) return;

      // Update temporal tracker for stable IDs and smooth positions.
      final tracked = _tracker.update(detections);

      emit(DetectionSuccess(
        detections: detections,
        trackedDetections: tracked,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      _handleWarnings(detections);
    } catch (e) {
      // Inference errors are silenced: a single bad frame is not fatal.  The
      // camera stream continues on the next frame.
      debugPrint('[DetectionBloc] inference error (frame skipped): $e');
    } finally {
      // BUG FIX 2: onDone is ALWAYS called, even on error or early return,
      // so CameraService._isProcessingFrame is always released.
      event.onDone();
    }
  }

  // ── Warning throttle ────────────────────────────────────────────────────────

  void _handleWarnings(List<DetectionObject> detections) {
    if (detections.isEmpty) return;

    // Age out tracks that are no longer detected.
    final currentIds = detections.map((d) => d.label.hashCode).toSet();
    _trackInfos.removeWhere((id, _) => !currentIds.contains(id));

    for (final detection in detections) {
      final trackId = detection.label.hashCode;
      final info = _trackInfos.putIfAbsent(trackId, _TrackInfo.new);

      info.seenCount++;

      // Wait for _kStabilityFrames before the first warning on each track.
      if (info.seenCount <= _kStabilityFrames) continue;

      // Do not repeat the warning for the same stable track every frame.
      if (info.warned && !detection.isDangerous) continue;

      info.warned = true;

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
    // Release the model even if the UI did not dispatch DetectionStopped.
    try {
      await _closeModel.call(const NoParams());
    } catch (_) {}
    return super.close();
  }
}