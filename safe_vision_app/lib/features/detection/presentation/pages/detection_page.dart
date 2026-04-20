import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/camera_service.dart';
import '../../../../core/utils/voice_helper.dart';
import '../../../../injection_container.dart';
import '../../domain/entities/detection_object.dart';
import '../bloc/detection_bloc.dart';
import '../bloc/detection_event.dart';
import '../bloc/detection_state.dart';
import '../widgets/object_indicator_painter.dart';
import '../widgets/confidence_score_display.dart';
import '../../../tts/presentation/bloc/tts_bloc.dart';
import '../../../tts/presentation/bloc/tts_event.dart';
import '../../../tts/presentation/widgets/voice_feedback_indicator.dart';
import '../../../settings/domain/repositories/settings_repository.dart';

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
/// 4. [dispose] — stop camera stream, close both BLoCs.
///    [CameraService.dispose] returns a future; teardown starts immediately
///    and continues asynchronously (invoked via `unawaited` in this page's
///    dispose override).
class DetectionPage extends StatefulWidget {
  const DetectionPage({
    super.key,
    required this.settingsRepository,
  });

  static const routeName = '/detection';
  final SettingsRepository settingsRepository;

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────────

  final CameraService _camera = sl<CameraService>();

  // ── BLoCs (owned by this State — not by a BlocProvider factory) ──────────

  late final TtsBloc _ttsBloc;
  late final DetectionBloc _detectionBloc;
  late final SettingsRepository _settingsRepository;
  late final AnimationController _pulseController;

  // ── Rendering state ───────────────────────────────────────────────────────

  List<SmoothedBox> _boxes = [];
  int _boxVersion = 0;
  bool _cameraReady = false;
  String? _errorMessage;
  bool _isDisposed = false;
  bool _showConfidencePanel = true;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _ttsBloc = sl<TtsBloc>();
    _settingsRepository = widget.settingsRepository;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _detectionBloc = DetectionBloc(
      loadModel: sl(),
      closeModel: sl(),
      detectFromFrame: sl(),
      onWarning: _onWarning,
    );

    unawaited(_bootstrapDetection());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(
          _camera.stopImageStream().catchError((Object e) {
            debugPrint('[DetectionPage] stop stream on lifecycle error: $e');
          }),
        );
        _detectionBloc.add(const DetectionStopped());
        break;
      case AppLifecycleState.resumed:
        if (_cameraReady) {
          unawaited(
            _camera.startImageStream(onFrame: _onFrame).catchError((Object e) {
              debugPrint('[DetectionPage] stream resume error: $e');
            }),
          );
        }
        _detectionBloc.add(const DetectionStarted());
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    unawaited(
      _camera.stopImageStream().catchError((Object e) {
        debugPrint('[DetectionPage] stop stream error: $e');
      }),
    );

    _detectionBloc.close();
    _ttsBloc.close();

    unawaited(
      _camera.dispose().catchError((Object e) {
        debugPrint('[DetectionPage] camera dispose error: $e');
      }),
    );
    _pulseController.dispose();
    ObjectIndicatorPainter.clearCache();

    super.dispose();
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  Future<void> _startCamera() async {
    try {
      await _camera.initialize();
      await _camera.startImageStream(onFrame: _onFrame);
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  void _onFrame(CameraFrame frame, VoidCallback onDone) {
    if (_isDisposed || _detectionBloc.isClosed) {
      onDone();
      return;
    }

    _detectionBloc.add(
      DetectionFrameReceived(frame, _sensorRotation, onDone),
    );
  }

  /// Portrait-mode Android sensor rotation.
  ///
  /// In production this should read from the [CameraController.description]
  /// sensor orientation.  The conventional default for rear-facing portrait is
  /// 90°.
  int get _sensorRotation => _camera.rotationDegrees;

  Future<void> _bootstrapDetection() async {
    try {
      await _loadShowConfidencePanelSetting();
      if (_isDisposed || _detectionBloc.isClosed) return;
      _detectionBloc.add(const DetectionStarted());
    } catch (e) {
      debugPrint('[DetectionPage] bootstrap error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Không thể khởi động nhận diện. Vui lòng thử lại.';
        });
      }
    }
  }

  Future<void> _loadShowConfidencePanelSetting() async {
    try {
      final show = await _settingsRepository.getShowConfidencePanel();
      if (!mounted) return;
      setState(() => _showConfidencePanel = show);
    } catch (e) {
      debugPrint('[DetectionPage] load showConfidencePanel error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể tải cài đặt hiển thị.'),
          ),
        );
      }
    }
  }

  Future<void> _openSettings() async {
    try {
      await Navigator.of(context).pushNamed('/settings');
      await _loadShowConfidencePanelSetting();
    } catch (e) {
      debugPrint('[DetectionPage] open settings error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Không thể mở cài đặt. Vui lòng thử lại.')),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    if (!_cameraReady) return;
    try {
      await _camera.stopImageStream();
      await _camera.switchCamera();
      await _camera.startImageStream(onFrame: _onFrame);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[DetectionPage] switch camera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Không thể chuyển camera. Vui lòng thử lại.')),
        );
      }
    }
  }

  // ── Warning callback ──────────────────────────────────────────────────────

  void _onWarning({
    required String text,
    required bool immediate,
    required bool withVibration,
  }) {
    _ttsBloc.add(
      TtsSpeak(
        text,
        immediate: immediate,
        withVibration: withVibration,
      ),
    );
  }

  // ── BLoC state handler ────────────────────────────────────────────────────

  void _onDetectionState(BuildContext context, DetectionState state) {
    if (state is DetectionModelReady && !_cameraReady) {
      _startCamera();
    }

    if (state is DetectionSuccess) {
      final boxes = state.trackedDetections
          .map(SmoothedBox.fromTrackedDetection)
          .toList(growable: false);
      if (mounted) {
        setState(() {
          _boxes = boxes;
          _boxVersion++;
        });
      }
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
        _buildCameraPreview(),

        // ── Bounding box overlay ────────────────────────────────────────────
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, __) => CustomPaint(
            painter: ObjectIndicatorPainter(
              boxes: _boxes,
              mirrorHorizontal: _camera.isFrontCamera,
              version: _boxVersion,
              animationValue: _pulseController.value,
            ),
          ),
        ),

        const Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(top: 12),
              child: VoiceFeedbackIndicator(),
            ),
          ),
        ),

        // ── Confidence score panel ──────────────────────────────────────────
        if (_showConfidencePanel)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 48, 12, 0),
              child: SizedBox(
                width: 220,
                child: BlocBuilder<DetectionBloc, DetectionState>(
                  builder: (_, state) => ConfidenceScoreDisplay(
                    detections: state is DetectionSuccess
                        ? state.detections
                        : <DetectionObject>[],
                  ),
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
            onSettings: () => unawaited(_openSettings()),
            onSwitchCamera: () => unawaited(_switchCamera()),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPreview() {
    final controller = _camera.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    return Positioned.fill(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 1080,
          height: controller.value.previewSize?.width ?? 1920,
          child: CameraPreview(controller),
        ),
      ),
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
              style: const TextStyle(color: Colors.white, fontSize: 18),
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
              style: const TextStyle(color: Colors.white70, fontSize: 16),
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
    required this.onSwitchCamera,
  });

  final VoidCallback onStop;
  final VoidCallback onSettings;
  final VoidCallback onSwitchCamera;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: 88,
        color: Colors.black.withValues(alpha: 0.55),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Cài đặt',
              icon: const Icon(Icons.settings, size: 32, color: Colors.white),
              onPressed: onSettings,
            ),
            IconButton(
              tooltip: 'Đổi camera',
              icon: const Icon(Icons.cameraswitch_outlined,
                  size: 32, color: Colors.white),
              onPressed: onSwitchCamera,
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
