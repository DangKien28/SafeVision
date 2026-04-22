import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/camera_service.dart';
import '../../../../core/utils/voice_helper.dart';
import '../../../../injection_container.dart';
import '../../../settings/domain/repositories/settings_repository.dart';
import '../../../tts/presentation/bloc/tts_bloc.dart';
import '../../../tts/presentation/bloc/tts_event.dart';
import '../../../tts/presentation/widgets/voice_feedback_indicator.dart';
import '../../domain/entities/detection_object.dart';
import '../bloc/detection_bloc.dart';
import '../bloc/detection_event.dart';
import '../bloc/detection_state.dart';
import '../widgets/confidence_score_display.dart';
import '../widgets/detection_control_bar.dart';
import '../widgets/object_indicator_painter.dart';

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
  static const double _kConfidencePanelWidthPx = 220;

  final CameraService _camera = sl<CameraService>();

  late final TtsBloc _ttsBloc;
  late final DetectionBloc _detectionBloc;
  late final SettingsRepository _settingsRepository;
  late final AnimationController _pulseController;

  List<SmoothedBox> _boxes = const <SmoothedBox>[];
  int _boxVersion = 0;
  bool _cameraReady = false;
  bool _isDisposed = false;
  bool _showConfidencePanel = true;
  String? _errorMessage;

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
      case AppLifecycleState.hidden:
        unawaited(
          _camera.stopImageStream().catchError((Object e) {
            debugPrint('[DetectionPage] stop stream on lifecycle error: $e');
          }),
        );
        _detectionBloc.add(const DetectionStopped());
        break;
      case AppLifecycleState.resumed:
        if (_cameraReady) {
          try {
            _camera.startImageStream(onFrame: _onFrame);
          } catch (e) {
            debugPrint('[DetectionPage] stream resume error: $e');
          }
        }
        _detectionBloc.add(const DetectionStarted());
        break;
      case AppLifecycleState.inactive:
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

    unawaited(_detectionBloc.close());
    unawaited(_ttsBloc.close());

    unawaited(
      _camera.dispose().catchError((Object e) {
        debugPrint('[DetectionPage] camera dispose error: $e');
      }),
    );

    _pulseController.dispose();
    ObjectIndicatorPainter.clearCache();
    super.dispose();
  }

  Future<void> _bootstrapDetection() async {
    try {
      await _loadDisplaySettings();
      if (_isDisposed || _detectionBloc.isClosed) return;
      _detectionBloc.add(const DetectionStarted());
    } catch (e) {
      debugPrint('[DetectionPage] bootstrap error: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Kh\u00f4ng th\u1ec3 kh\u1edfi \u0111\u1ed9ng nh\u1eadn di\u1ec7n. Vui l\u00f2ng th\u1eed l\u1ea1i.';
      });
    }
  }

  Future<void> _loadDisplaySettings() async {
    try {
      final show = await _settingsRepository.getShowConfidencePanel();
      if (!mounted) return;
      setState(() {
        _showConfidencePanel = show;
      });
    } catch (e) {
      debugPrint('[DetectionPage] load display settings error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kh\u00f4ng th\u1ec3 t\u1ea3i c\u00e0i \u0111\u1eb7t hi\u1ec3n th\u1ecb.',
          ),
        ),
      );
    }
  }

  Future<void> _startCamera() async {
    try {
      await _camera.initialize();
      _camera.startImageStream(onFrame: _onFrame);
      if (!mounted) return;
      setState(() => _cameraReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  void _onFrame(CameraFrame frame, VoidCallback onDone) {
    if (_isDisposed || _detectionBloc.isClosed) {
      onDone();
      return;
    }

    _detectionBloc.add(
      DetectionFrameReceived(frame, _camera.rotationDegrees, onDone),
    );
  }

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

  void _onDetectionState(BuildContext context, DetectionState state) {
    if (state is DetectionModelReady && !_cameraReady) {
      unawaited(_startCamera());
    }

    if (state is DetectionSuccess) {
      final boxes = state.detections
          .map(SmoothedBox.fromDetectionObject)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _boxes = boxes;
        _boxVersion++;
      });
    }

    if (state is DetectionFailure) {
      if (mounted) {
        setState(() => _errorMessage = state.message);
      }
      _ttsBloc.add(
        TtsSpeak(
          VoiceHelper.systemError(),
          immediate: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<DetectionBloc>.value(value: _detectionBloc),
        BlocProvider<TtsBloc>.value(value: _ttsBloc),
      ],
      child: Scaffold(
        backgroundColor: Colors.black,
        body: BlocListener<DetectionBloc, DetectionState>(
          listener: _onDetectionState,
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
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
        _buildCameraPreview(context),
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
        if (_showConfidencePanel)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 48, 12, 0),
              child: SizedBox(
                width: _kConfidencePanelWidthPx,
                child: BlocBuilder<DetectionBloc, DetectionState>(
                  builder: (_, state) => ConfidenceScoreDisplay(
                    detections: state is DetectionSuccess
                        ? state.detections
                        : const <DetectionObject>[],
                  ),
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: DetectionControlBar(
            onStop: () {
              _detectionBloc.add(const DetectionStopped());
              Navigator.of(context).pop();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCameraPreview(BuildContext context) {
    final controller = _camera.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    final previewSize = controller.value.previewSize;
    final screenSize = MediaQuery.sizeOf(context);
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final fallbackWidth = isPortrait ? screenSize.height : screenSize.width;
    final fallbackHeight = isPortrait ? screenSize.width : screenSize.height;
    final previewWidth = previewSize?.width ?? fallbackWidth;
    final previewHeight = previewSize?.height ?? fallbackHeight;

    return Positioned.fill(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: previewWidth,
          height: previewHeight,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.bloc});

  final DetectionBloc bloc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<DetectionBloc, DetectionState>(
      bloc: bloc,
      builder: (_, state) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/sv_logo.png',
                semanticLabel: 'SafeVision Logo',
                height: 64,
                width: 64,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Semantics(
                  label: 'SafeVision Icon',
                  child: Icon(
                    Icons.visibility,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              CircularProgressIndicator(color: theme.colorScheme.primary),
              const SizedBox(height: 18),
              Text(
                state is DetectionLoading
                    ? '\u0110ang t\u1ea3i m\u00f4 h\u00ecnh AI...'
                    : '\u0110ang kh\u1edfi \u0111\u1ed9ng camera...',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                label: const Text('Th\u1eed l\u1ea1i'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Quay l\u1ea1i'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
