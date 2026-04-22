import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safe_vision_app/core/error/exceptions.dart';

import '../../../../core/services/camera_service.dart';
import '../../../../core/utils/permission_handler.dart';
import '../../../../core/utils/voice_helper.dart';
import '../../../../injection_container.dart';
import '../../../settings/presentation/bloc/settings_bloc.dart';
import '../../../settings/presentation/bloc/settings_state.dart';
import '../../../tts/presentation/bloc/tts_bloc.dart';
import '../../../tts/presentation/bloc/tts_event.dart';
import '../../../tts/presentation/widgets/voice_feedback_indicator.dart';
import '../../../voice_command/domain/usecases/listen_target_object_usecase.dart';
import '../../domain/entities/detection_object.dart';
import '../bloc/detection_bloc.dart';
import '../bloc/detection_event.dart';
import '../bloc/detection_state.dart';
import '../widgets/bounding_box_painter.dart';
import '../widgets/confidence_score_display.dart';

class CameraViewPage extends StatefulWidget {
  const CameraViewPage({super.key});

  @override
  State<CameraViewPage> createState() => _CameraViewPageState();
}

class _CameraViewPageState extends State<CameraViewPage>
    with WidgetsBindingObserver {
  final CameraService _cameraService = sl<CameraService>();
  final ListenTargetObjectUsecase _listenTargetObject =
      sl<ListenTargetObjectUsecase>();
  final BoxTracker _tracker = BoxTracker();

  bool _cameraReady = false;
  bool _isTargetSearchMode = false;
  bool _isListeningForTarget = false;
  String? _targetObjectKey;
  String? _targetObjectName;
  DateTime? _lastTargetAnnouncement;
  int _targetListenSession = 0;
  int _cameraSession = 0;

  late final ValueNotifier<({List<SmoothedBox> boxes, int version})>
      _boxNotifier = ValueNotifier((boxes: const [], version: 0));
  bool _boxNotifierDisposed = false;

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
    _tracker.clear();
    _disposeBoxNotifier();
    unawaited(_cameraService.dispose());
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
            _startStreaming();
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
      _startStreaming();
    } on PermissionException catch (e) {
      if (!mounted || _phase == _LifecyclePhase.disposed) return;
      _showPermissionDialog(e.message);
    } catch (e) {
      debugPrint('[CameraViewPage] camera init error: $e');
    }
  }

  void _startStreaming() {
    if (_phase == _LifecyclePhase.disposed) return;

    final session = _cameraSession;
    _cameraService.startImageStream(
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
  }

  Future<void> _toggleSearch() async {
    if (_phase == _LifecyclePhase.disposed) return;
    final ttsBloc = context.read<TtsBloc>();

    if (_isTargetSearchMode) {
      _targetListenSession++;
      setState(() {
        _isTargetSearchMode = false;
        _isListeningForTarget = false;
        _targetObjectKey = null;
        _targetObjectName = null;
        _lastTargetAnnouncement = null;
      });
      ttsBloc.add(
        const TtsSpeak('Da dung tim do vat', immediate: true),
      );
      return;
    }

    if (_isListeningForTarget) return;

    setState(() {
      _isTargetSearchMode = true;
      _isListeningForTarget = true;
      _targetObjectKey = null;
      _targetObjectName = null;
      _lastTargetAnnouncement = null;
    });

    try {
      await AppPermissionHandler.requestMicrophone();
    } on PermissionException catch (e) {
      if (!mounted || _phase == _LifecyclePhase.disposed) return;
      setState(() {
        _isTargetSearchMode = false;
        _isListeningForTarget = false;
      });
      _showPermissionDialog(e.message);
      return;
    }

    final session = ++_targetListenSession;
    unawaited(_listenForTargetUntilRecognized(session, ttsBloc));
  }

  Future<void> _listenForTargetUntilRecognized(
    int session,
    TtsBloc ttsBloc,
  ) async {
    ttsBloc.add(
      const TtsSpeak('Doc ten do vat can tim', immediate: true),
    );

    while (mounted &&
        _phase != _LifecyclePhase.disposed &&
        _isTargetSearchMode &&
        _targetObjectKey == null &&
        session == _targetListenSession) {
      final heardText = await _listenTargetObject(
        const ListenTargetObjectParams(),
      );

      if (!mounted ||
          _phase == _LifecyclePhase.disposed ||
          !_isTargetSearchMode ||
          session != _targetListenSession) {
        return;
      }

      final key = VoiceHelper.canonicalLabelKey(heardText ?? '');
      if (key == null) {
        ttsBloc.add(
          const TtsSpeak(
            'Khong nghe ro. Vui long doc lai ten do vat can tim.',
            immediate: true,
          ),
        );
        continue;
      }

      setState(() {
        _isListeningForTarget = false;
        _targetObjectKey = key;
        _targetObjectName = VoiceHelper.normalizeLabel(heardText!);
      });

      ttsBloc.add(
        const TtsSpeak('Quay dien thoai xung quanh', immediate: true),
      );
      return;
    }

    if (!mounted || _phase == _LifecyclePhase.disposed) return;
    if (session != _targetListenSession) return;
    if (!_isTargetSearchMode || _targetObjectKey != null) return;

    setState(() {
      _isListeningForTarget = true;
    });
  }

  void _announceTargetIfFound(List<DetectionObject> detections) {
    if (!_isTargetSearchMode || _targetObjectKey == null || detections.isEmpty) {
      return;
    }

    final match = detections
        .where((d) => VoiceHelper.canonicalLabelKey(d.label) == _targetObjectKey)
        .toList()
      ..sort((a, b) => b.boundingBox.area.compareTo(a.boundingBox.area));

    if (match.isEmpty) return;

    final now = DateTime.now();
    final last = _lastTargetAnnouncement;
    if (last != null && now.difference(last).inMilliseconds < 2500) return;
    _lastTargetAnnouncement = now;

    final top = match.first;
    final name = _targetObjectName ?? VoiceHelper.normalizeLabel(top.label);
    context.read<TtsBloc>().add(
          TtsSpeak(
            'Da tim thay $name o vi tri ${top.boundingBox.horizontalPosition}',
            immediate: true,
          ),
        );
  }

  void _showPermissionDialog(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Yeu cau quyen Camera'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Huy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              AppPermissionHandler.openSettings();
            },
            child: const Text('Mo Cai dat'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MultiBlocListener(
        listeners: [
          BlocListener<DetectionBloc, DetectionState>(
            listenWhen: (_, curr) =>
                curr is DetectionSuccess || curr is DetectionInitial,
            listener: (_, state) {
              if (_phase == _LifecyclePhase.disposed || _boxNotifierDisposed) {
                return;
              }

              if (state is DetectionSuccess) {
                if (!_cameraReady) return;
                _setBoxes(_tracker.update(state.detections));
                _announceTargetIfFound(state.detections);
              } else if (state is DetectionInitial) {
                _tracker.clear();
                _setBoxes(const []);
              }
            },
          ),
        ],
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: _CameraLayer(
                service: _cameraService,
                cameraReady: _cameraReady,
                boxNotifier: _boxNotifier,
              ),
            ),
            BlocBuilder<DetectionBloc, DetectionState>(
              buildWhen: (prev, curr) =>
                  curr is DetectionSuccess ||
                  curr.runtimeType != prev.runtimeType,
              builder: (context, state) => _DetectionOverlay(
                state: state,
                onToggleSearch: _toggleSearch,
                isTargetSearchMode: _isTargetSearchMode,
                isListeningForTarget: _isListeningForTarget,
                onError: _buildError,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Loi: $msg',
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );

  void _setBoxes(List<SmoothedBox> boxes) {
    if (_phase == _LifecyclePhase.disposed || _boxNotifierDisposed) return;
    _boxNotifier.value = (boxes: boxes, version: _tracker.version);
  }

  void _disposeBoxNotifier() {
    if (_boxNotifierDisposed) return;
    _boxNotifierDisposed = true;
    _boxNotifier.dispose();
  }
}

enum _LifecyclePhase { active, paused, disposed }

class _DetectionOverlay extends StatelessWidget {
  const _DetectionOverlay({
    required this.state,
    required this.onToggleSearch,
    required this.isTargetSearchMode,
    required this.isListeningForTarget,
    required this.onError,
  });

  final DetectionState state;
  final Future<void> Function() onToggleSearch;
  final bool isTargetSearchMode;
  final bool isListeningForTarget;
  final Widget Function(String) onError;

  @override
  Widget build(BuildContext context) {
    final detections = state is DetectionSuccess
        ? (state as DetectionSuccess).detections
        : const <DetectionObject>[];

    return Stack(
      fit: StackFit.expand,
      children: [
        if (state is DetectionLoading)
          const ColoredBox(
            color: Colors.black45,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (p, c) => p.showConfidencePanel != c.showConfidencePanel,
          builder: (context, settings) {
            if (!settings.showConfidencePanel || detections.isEmpty) {
              return const SizedBox.shrink();
            }
            return Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 16,
              child: ConfidenceScoreDisplay(detections: detections),
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
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: onToggleSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isTargetSearchMode ? Colors.orangeAccent : Colors.white,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(
                  isListeningForTarget
                      ? 'Dang nghe...'
                      : (isTargetSearchMode ? 'Dung tim' : 'Tim do vat'),
                ),
              ),
            ),
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
  const _CameraLayer({
    required this.service,
    required this.cameraReady,
    required this.boxNotifier,
  });

  final CameraService service;
  final bool cameraReady;
  final ValueListenable<({List<SmoothedBox> boxes, int version})> boxNotifier;

  @override
  Widget build(BuildContext context) {
    final ctrl = service.controller;
    if (!cameraReady || ctrl == null || !ctrl.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final previewSize = ctrl.value.previewSize;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final previewWidth = previewSize?.width ?? 1.0;
    final previewHeight = previewSize?.height ?? 1.0;
    final canvasWidth = isPortrait ? previewHeight : previewWidth;
    final canvasHeight = isPortrait ? previewWidth : previewHeight;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.center,
          child: Transform(
            alignment: Alignment.center,
            transform: service.isFrontCamera
                ? Matrix4.diagonal3Values(-1.0, 1.0, 1.0)
                : Matrix4.identity(),
            child: SizedBox(
              width: canvasWidth,
              height: canvasHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(ctrl),
                  RepaintBoundary(
                    child: ValueListenableBuilder<(
                      {List<SmoothedBox> boxes, int version}
                    )>(
                      valueListenable: boxNotifier,
                      builder: (_, data, __) => IgnorePointer(
                        child: CustomPaint(
                          painter: BoundingBoxPainter(
                            boxes: data.boxes,
                            mirrorHorizontal: service.isFrontCamera,
                            version: data.version,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
