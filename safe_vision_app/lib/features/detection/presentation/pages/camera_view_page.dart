import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:camera/camera.dart';

import '../../../../core/services/camera_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<DetectionBloc>().add(const DetectionStarted());
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Không await trong dispose — tránh block main thread
    _cameraService.stopImageStream();
    _cameraService.dispose();
    // Dùng addPostFrameCallback để TTS stop sau khi widget đã unmount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // TtsBloc vẫn sống vì là singleton — gọi trực tiếp qua sl
      sl<TtsBloc>().add(const TtsStop());
    });
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _cameraService.stopImageStream();
        break;
      case AppLifecycleState.resumed:
        if (!_cameraService.isInitialized) {
          _startCamera();
        } else {
          _startStreaming();
        }
        break;
      default:
        break;
    }
  }

  Future<void> _startCamera() async {
    try {
      await _cameraService.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
      _startStreaming();
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  void _startStreaming() {
    if (_cameraService.controller?.value.isStreamingImages ?? false) return;
    _cameraService.startImageStream(
      onFrame: (image) {
        if (!mounted) return;
        context.read<DetectionBloc>().add(DetectionFrameReceived(image));
      },
    );
  }

  Future<void> _switchCamera() async {
    await _cameraService.stopImageStream();
    setState(() => _cameraReady = false);
    await _cameraService.switchCamera();
    if (!mounted) return;
    setState(() => _cameraReady = true);
    _startStreaming();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview — NGOÀI BlocBuilder, không bao giờ rebuild ──
          // RepaintBoundary ngăn GPU re-composite khi overlay thay đổi
          RepaintBoundary(
            child: _CameraLayer(
              cameraService: _cameraService,
              cameraReady: _cameraReady,
            ),
          ),

          // ── Overlay — chỉ phần này rebuild khi có detection mới ─────
          BlocBuilder<DetectionBloc, DetectionState>(
            // buildWhen: chỉ rebuild khi danh sách detection thực sự đổi
            buildWhen: (prev, curr) {
              if (prev.runtimeType != curr.runtimeType) return true;
              if (curr is DetectionSuccess && prev is DetectionSuccess) {
                return curr.detections != prev.detections;
              }
              return true;
            },
            builder: (context, state) {
              final detections = state is DetectionSuccess
                  ? state.detections
                  : <DetectionObject>[];

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Bounding boxes — chỉ vẽ, không rebuild camera
                  IgnorePointer(
                    child: CustomPaint(
                      painter: BoundingBoxPainter(
                        detections: detections,
                        mirrorHorizontal: _cameraService.isFrontCamera,
                      ),
                    ),
                  ),

                  // Loading overlay
                  if (state is DetectionLoading) _buildLoadingOverlay(),

                  // Confidence panel
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 8,
                    right: 80,
                    child: ConfidenceScoreDisplay(detections: detections),
                  ),

                  // Voice indicator
                  const Positioned(
                    bottom: 100,
                    left: 16,
                    right: 16,
                    child: Align(
                      alignment: Alignment.center,
                      child: VoiceFeedbackIndicator(),
                    ),
                  ),

                  // Error banner
                  if (state is DetectionFailure)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: _buildErrorBanner(state.message),
                    ),
                ],
              );
            },
          ),

          // ── Controls — luôn hiển thị, không cần rebuild theo state ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: _buildControls(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() => Container(
        color: Colors.black54,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 12),
              Text(
                'Đang tải mô hình AI...',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      );

  Widget _buildControls(BuildContext context) => Column(
        children: [
          _IconBtn(
            icon: Icons.flip_camera_ios,
            tooltip: 'Chuyển camera',
            onTap: _switchCamera,
          ),
          const SizedBox(height: 8),
          _IconBtn(
            icon: Icons.volume_up,
            tooltip: 'Tắt tiếng',
            onTap: () => context.read<TtsBloc>().add(const TtsStop()),
          ),
          const SizedBox(height: 8),
          _IconBtn(
            icon: Icons.settings,
            tooltip: 'Cài đặt',
            onTap: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      );

  Widget _buildErrorBanner(String message) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.85),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Lỗi: $message',
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
}

// ── Camera layer riêng — chỉ rebuild khi _cameraReady đổi ────────────────

class _CameraLayer extends StatelessWidget {
  final CameraService cameraService;
  final bool cameraReady;

  const _CameraLayer({
    required this.cameraService,
    required this.cameraReady,
  });

  @override
  Widget build(BuildContext context) {
    final controller = cameraService.controller;
    if (!cameraReady || controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // Mirror preview nếu camera trước
    if (cameraService.isFrontCamera) {
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0), // lật ngang
        child: CameraPreview(controller),
      );
    }

    return CameraPreview(controller);
  }
}

// ── IconBtn ───────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white30),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
