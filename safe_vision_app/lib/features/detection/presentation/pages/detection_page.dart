import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vibration/vibration.dart';

import '../../../../core/services/camera_service.dart';
import '../../../../core/utils/voice_helper.dart';
import '../../../../injection_container.dart';
import '../../domain/entities/detection_object.dart';
import '../bloc/detection_bloc.dart';
import '../bloc/detection_event.dart';
import '../bloc/detection_state.dart';
import '../widgets/bounding_box_painter.dart';
import '../widgets/confidence_score_display.dart';
import '../../../tts/presentation/bloc/tts_bloc.dart';
import '../../../tts/presentation/bloc/tts_event.dart';

/// Root page for the object-detection camera feed.
///
/// ## Design
///
/// Both [DetectionBloc] and [TtsBloc] are created directly in [initState]
/// rather than through a [MultiBlocProvider] factory.  This is necessary
/// because [DetectionBloc] requires an [onWarning] callback that calls
/// [TtsBloc.add] — so both instances must exist at the same time before
/// the tree is built.
///
/// Using a [MultiBlocProvider] factory would create the BLoCs lazily during
/// [build], which means [TtsBloc] may not yet exist when [DetectionBloc]
/// fires its first warning.
///
/// ## Lifecycle
///
/// 1. [initState] — create both BLoCs, dispatch [DetectionStarted].
/// 2. [_onDetectionState] — when [DetectionModelReady], start camera.
/// 3. [didChangeAppLifecycleState] — pause/resume on app background.
/// 4. [dispose] — stop camera stream, dispatch [DetectionStopped], dispose
///    both BLoCs.  Camera hardware is released via
///    [CameraService.dispose] (sync call; async cleanup stored in
///    [CameraService.disposeFuture]).
class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});

  static const routeName = '/detection';

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage>
    with WidgetsBindingObserver {
  // ── Services ──────────────────────────────────────────────────────────────

  final CameraService _camera = sl<CameraService>();

  // ── BLoCs (owned by this State — not by a BlocProvider factory) ──────────

  late final TtsBloc _ttsBloc;
  late final DetectionBloc _detectionBloc;

  // ── Rendering state ───────────────────────────────────────────────────────

  final BoxTracker _tracker = BoxTracker();
  List<SmoothedBox> _boxes = [];
  bool _cameraReady = false;
  String? _errorMessage;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // BUG FIX: create TtsBloc first so _onWarning can reference it immediately.
    _ttsBloc = sl<TtsBloc>();

    _detectionBloc = DetectionBloc(
      loadModel:       sl(),
      closeModel:      sl(),
      detectFromFrame: sl(),
      // _onWarning is defined below with a direct reference to _ttsBloc.
      // No stub, no late wiring.
      onWarning: _onWarning,
    );

    _detectionBloc.add(const DetectionStarted());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _camera.stopImageStream();
        _detectionBloc.add(const DetectionStopped());
      case AppLifecycleState.resumed:
        if (_cameraReady) {
          _camera.startImageStream(_onFrame);
        }
        _detectionBloc.add(const DetectionStarted());
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Stop the pipeline before releasing hardware.
    _detectionBloc.add(const DetectionStopped());
    _detectionBloc.close();
    _ttsBloc.close();

    // CameraService.dispose() is synchronous (per the fix in camera_service.dart).
    // The async hardware teardown is stored in CameraService.disposeFuture so
    // the OS camera handle remains reachable until it ACKs the release.
    _camera.dispose();
    _tracker.clear();

    super.dispose();
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _startCamera() async {
    try {
      await _camera.initialize();
      await _camera.startImageStream(_onFrame);
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  void _onFrame(CameraFrame frame, VoidCallback onDone) {
    _detectionBloc.add(
      DetectionFrameReceived(frame, _sensorRotation, onDone),
    );
  }

  /// Portrait-mode Android sensor rotation.
  ///
  /// In production this should read from the [CameraController.description]
  /// sensor orientation.  The conventional default for rear-facing portrait is
  /// 90°.
  int get _sensorRotation => 90;

  // ── Warning callback ──────────────────────────────────────────────────────

  void _onWarning({
    required String text,
    required bool immediate,
    required bool withVibration,
  }) {
    _ttsBloc.add(TtsSpeak(text, immediate: immediate));
    if (withVibration) _triggerVibration();
  }

  Future<void> _triggerVibration() async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 200);
      }
    } catch (_) {}
  }

  // ── BLoC state handler ────────────────────────────────────────────────────

  void _onDetectionState(BuildContext context, DetectionState state) {
    if (state is DetectionModelReady && !_cameraReady) {
      _startCamera();
    }

    if (state is DetectionSuccess) {
      final boxes = _tracker.update(state.detections);
      if (mounted) setState(() => _boxes = boxes);
    }

    if (state is DetectionFailure) {
      if (mounted) setState(() => _errorMessage = state.message);
      _ttsBloc.add(TtsSpeak(VoiceHelper.systemError(), immediate: true));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      // Provide the already-created instances so child widgets can read them.
      providers: [
        BlocProvider<DetectionBloc>.value(value: _detectionBloc),
        BlocProvider<TtsBloc>.value(value: _ttsBloc),
      ],
      child: Scaffold(
        backgroundColor: Colors.black,
        body: BlocListener<DetectionBloc, DetectionState>(
          listener: _onDetectionState,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return _ErrorOverlay(
        message: _errorMessage!,
        onRetry: () {
          setState(() => _errorMessage = null);
          _detectionBloc.add(const DetectionStarted());
        },
      );
    }

    if (!_cameraReady) {
      return _LoadingOverlay(bloc: _detectionBloc);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Camera preview ──────────────────────────────────────────────────
        // CameraController is exposed via a getter on CameraService in the
        // real implementation.  Shown as a black placeholder here so the
        // widget tree compiles without the camera plugin in test environments.
        const ColoredBox(color: Colors.black),

        // ── Bounding box overlay ────────────────────────────────────────────
        CustomPaint(
          painter: BoundingBoxPainter(
            boxes: _boxes,
            version: _tracker.version,
          ),
        ),

        // ── Confidence score panel ──────────────────────────────────────────
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 48, 12, 0),
            child: BlocBuilder<DetectionBloc, DetectionState>(
              builder: (_, state) => ConfidenceScoreDisplay(
                detections: state is DetectionSuccess
                    ? state.detections
                    : <DetectionObject>[],
              ),
            ),
          ),
        ),

        // ── Bottom control bar ──────────────────────────────────────────────
        Align(
          alignment: Alignment.bottomCenter,
          child: _ControlBar(
            onStop: () {
              _detectionBloc.add(const DetectionStopped());
              Navigator.of(context).pop();
            },
            onSettings: () =>
                Navigator.of(context).pushNamed('/settings'),
          ),
        ),
      ],
    );
  }
}

// ── Loading overlay ───────────────────────────────────────────────────────────

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.bloc});
  final DetectionBloc bloc;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DetectionBloc, DetectionState>(
      bloc: bloc,
      builder: (_, state) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF00E5FF)),
            const SizedBox(height: 24),
            Text(
              state is DetectionLoading
                  ? 'Đang tải mô hình AI...'
                  : 'Đang khởi động camera...',
              style:
                  const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error overlay ─────────────────────────────────────────────────────────────

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 80,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Quay lại'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom control bar ────────────────────────────────────────────────────────

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.onStop,
    required this.onSettings,
  });

  final VoidCallback onStop;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: 88,
        color: Colors.black.withOpacity(0.55),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Cài đặt',
              icon: const Icon(Icons.settings, size: 32, color: Colors.white),
              onPressed: onSettings,
            ),
            SizedBox(
              height: 80,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.stop_circle_outlined, size: 28),
                label: const Text('Dừng'),
                onPressed: onStop,
              ),
            ),
          ],
        ),
      ),
    );
  }
}