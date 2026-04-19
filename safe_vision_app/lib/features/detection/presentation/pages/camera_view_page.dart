import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safe_vision_app/core/error/exceptions.dart';
import '../../../settings/presentation/bloc/settings_bloc.dart';
import '../../../settings/presentation/bloc/settings_state.dart';

import '../../../../core/services/camera_service.dart';
import '../../../../core/utils/permission_handler.dart';
import '../../../../injection_container.dart';
import '../bloc/detection_bloc.dart';
import '../bloc/detection_event.dart';
import '../bloc/detection_state.dart';
import '../widgets/bounding_box_painter.dart';
import '../widgets/confidence_score_display.dart';
import '../../domain/entities/detection_object.dart';
import '../../../tts/presentation/bloc/tts_bloc.dart';
import '../../../tts/presentation/bloc/tts_event.dart';
import '../../../tts/presentation/widgets/voice_feedback_indicator.dart';

class CameraViewPage extends StatefulWidget {
  const CameraViewPage({super.key});

  @override
  State<CameraViewPage> createState() => _CameraViewPageState();
}

class _CameraViewPageState extends State<CameraViewPage>
    with WidgetsBindingObserver {
  final CameraService _cameraService = sl<CameraService>();

  bool _cameraReady = false;
  int _cameraSession = 0;
  int _boxVersion = 0;

  late final ValueNotifier<({List<SmoothedBox> boxes, int version})>
      _boxNotifier = ValueNotifier((boxes: const [], version: 0));
  bool _boxNotifierDisposed = false;
  late final ValueNotifier<List<DetectionObject>> _detectionsNotifier =
      ValueNotifier(const <DetectionObject>[]);
  bool _detectionsNotifierDisposed = false;

  _LifecyclePhase _phase = _LifecyclePhase.active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<DetectionBloc>().add(const DetectionStarted());
    _startCamera();
  }

  @override
  void dispose() {
    _phase = _LifecyclePhase.disposed;
    WidgetsBinding.instance.removeObserver(this);
    context.read<DetectionBloc>().add(const DetectionStopped());
    context.read<TtsBloc>().add(const TtsStop());
    _disposeBoxNotifier();
    _disposeDetectionsNotifier();
    _cameraService.dispose(); // returns void; no future to await
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (_phase == _LifecyclePhase.active) {
          _phase = _LifecyclePhase.paused;
          unawaited(_cameraService.stopImageStream());
        }
        break;
      case AppLifecycleState.resumed:
        if (_phase == _LifecyclePhase.paused) {
          _phase = _LifecyclePhase.active;
          if (_cameraService.isInitialized) {
            unawaited(_startStreaming());
          } else {
            _startCamera();
          }
        }
        break;
    }
  }

  Future<void> _startCamera() async {
    if (_phase == _LifecyclePhase.disposed) return;
    try {
      await AppPermissionHandler.requestCamera();
      _cameraSession++;
      await _cameraService.initialize();
      if (!mounted || _phase == _LifecyclePhase.disposed) return;
      setState(() => _cameraReady = true);
      // BUG A FIX: await so errors are caught by the outer try/catch.
      await _startStreaming();
    } on PermissionException catch (e) {
      if (!mounted || _phase == _LifecyclePhase.disposed) return;
      _showPermissionDialog(e.message);
    } catch (e) {
      debugPrint('[Page] camera init error: $e');
    }
  }

  Future<void> _startStreaming() async {
    if (_phase == _LifecyclePhase.disposed) return;

    final int session = _cameraSession;
    try {
      await _cameraService.startImageStream(
        onFrame: (CameraFrame frame, void Function() onDone) {
          if (session != _cameraSession ||
              !mounted ||
              _phase == _LifecyclePhase.disposed) {
            onDone();
            return;
          }
          context.read<DetectionBloc>().add(
                DetectionFrameReceived(
                  frame,
                  _cameraService.rotationDegrees,
                  onDone,
                ),
              );
        },
      );
    } catch (e) {
      debugPrint('[Page] startImageStream error: $e');
      if (mounted && _phase != _LifecyclePhase.disposed) {
        setState(() => _cameraReady = false);
        // Retry via full init path to re-initialise the controller.
        await _startCamera();
      }
    }
  }

  Future<void> _switchCamera() async {
    await _cameraService.stopImageStream();
    if (!mounted || _phase == _LifecyclePhase.disposed) return;

    _cameraSession++;
    setState(() => _cameraReady = false);
    _setBoxes(const []);
    _setDetections(const []);

    try {
      await _cameraService.switchCamera();
      if (!mounted || _phase == _LifecyclePhase.disposed) return;
      setState(() => _cameraReady = true);

      await _startStreaming();
    } catch (e) {
      debugPrint('[Page] switchCamera error: $e');
      if (!mounted || _phase == _LifecyclePhase.disposed) return;
      setState(() => _cameraReady = false);
      await _startCamera();
    }
  }

  void _showPermissionDialog(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Yêu cầu quyền Camera'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              AppPermissionHandler.openSettings();
            },
            child: const Text('Mở Cài đặt'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: _CameraLayer(
              service: _cameraService,
              cameraReady: _cameraReady,
            ),
          ),
          MultiBlocListener(
            listeners: [
              BlocListener<DetectionBloc, DetectionState>(
                listenWhen: (_, curr) =>
                    curr is DetectionSuccess ||
                    curr is DetectionInitial ||
                    curr is DetectionFailure,
                listener: (_, state) {
                  if (_phase == _LifecyclePhase.disposed ||
                      _boxNotifierDisposed) {
                    return;
                  }
                  if (state is DetectionSuccess) {
                    _setDetections(state.detections);
                    if (!_cameraReady) return;
                    _setBoxes(
                      state.trackedDetections
                          .map(SmoothedBox.fromTrackedDetection)
                          .toList(growable: false),
                    );
                  } else if (state is DetectionInitial ||
                      state is DetectionFailure) {
                    _setBoxes(const []);
                    _setDetections(const []);
                  }
                },
              ),
            ],
            child: BlocBuilder<DetectionBloc, DetectionState>(
              buildWhen: (prev, curr) {
                if (curr is DetectionSuccess) return prev is! DetectionSuccess;
                if (curr.runtimeType != prev.runtimeType) return true;
                if (curr is DetectionFailure && prev is DetectionFailure) {
                  return curr.message != prev.message;
                }
                return false;
              },
              builder: (context, state) => _DetectionOverlay(
                boxNotifier: _boxNotifier,
                detectionsNotifier: _detectionsNotifier,
                state: state,
                isFront: _cameraService.isFrontCamera,
                onError: _buildError,
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: _buildControls(context),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('Lỗi: $msg',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center),
      );

  Widget _buildControls(BuildContext ctx) => Column(
        children: [
          _IconBtn(
              icon: Icons.flip_camera_ios,
              tooltip: 'Chuyển camera',
              onTap: _switchCamera),
          const SizedBox(height: 8),
          _IconBtn(
              icon: Icons.volume_up,
              tooltip: 'Tắt tiếng',
              onTap: () => ctx.read<TtsBloc>().add(const TtsStop())),
          const SizedBox(height: 8),
          _IconBtn(
              icon: Icons.settings,
              tooltip: 'Cài đặt',
              onTap: () => Navigator.pushNamed(ctx, '/settings')),
        ],
      );

  void _setBoxes(List<SmoothedBox> boxes) {
    if (_phase == _LifecyclePhase.disposed || _boxNotifierDisposed) return;
    _boxVersion++;
    _boxNotifier.value = (boxes: boxes, version: _boxVersion);
  }

  void _setDetections(List<DetectionObject> detections) {
    if (_phase == _LifecyclePhase.disposed || _detectionsNotifierDisposed) {
      return;
    }
    _detectionsNotifier.value = List.unmodifiable(detections);
  }

  void _disposeBoxNotifier() {
    if (_boxNotifierDisposed) return;
    _boxNotifierDisposed = true;
    _boxNotifier.dispose();
  }

  void _disposeDetectionsNotifier() {
    if (_detectionsNotifierDisposed) return;
    _detectionsNotifierDisposed = true;
    _detectionsNotifier.dispose();
  }
}

enum _LifecyclePhase { active, paused, disposed }

class _DetectionOverlay extends StatelessWidget {
  final ValueNotifier<({List<SmoothedBox> boxes, int version})> boxNotifier;
  final ValueNotifier<List<DetectionObject>> detectionsNotifier;
  final DetectionState state;
  final bool isFront;
  final Widget Function(String) onError;

  const _DetectionOverlay({
    required this.boxNotifier,
    required this.detectionsNotifier,
    required this.state,
    required this.isFront,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child:
              ValueListenableBuilder<({List<SmoothedBox> boxes, int version})>(
            valueListenable: boxNotifier,
            builder: (_, data, __) => IgnorePointer(
              child: CustomPaint(
                painter: BoundingBoxPainter(
                  boxes: data.boxes,
                  mirrorHorizontal: isFront,
                  version: data.version,
                ),
              ),
            ),
          ),
        ),
        if (state is DetectionLoading)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('Đang tải mô hình AI...',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (p, c) => p.showConfidencePanel != c.showConfidencePanel,
          builder: (context, settings) {
            if (!settings.showConfidencePanel) return const SizedBox.shrink();
            return ValueListenableBuilder<List<DetectionObject>>(
              valueListenable: detectionsNotifier,
              builder: (_, detections, __) => Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                right: 80,
                child: ConfidenceScoreDisplay(detections: detections),
              ),
            );
          },
        ),
        const Positioned(
          bottom: 100,
          left: 16,
          right: 16,
          child: Align(
            alignment: Alignment.center,
            child: VoiceFeedbackIndicator(),
          ),
        ),
        if (state is DetectionFailure)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: onError((state as DetectionFailure).message),
          ),
      ],
    );
  }
}

class _CameraLayer extends StatelessWidget {
  final CameraService service;
  final bool cameraReady;
  const _CameraLayer({required this.service, required this.cameraReady});

  @override
  Widget build(BuildContext context) {
    final ctrl = service.controller;
    if (!cameraReady || ctrl == null || !ctrl.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (service.isFrontCamera) {
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
        child: CameraPreview(ctrl),
      );
    }
    return CameraPreview(ctrl);
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      );
}
