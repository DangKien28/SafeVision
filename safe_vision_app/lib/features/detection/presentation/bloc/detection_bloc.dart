import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/usecases/load_model_usecase.dart';
import '../../domain/usecases/detection_object_from_frame.dart';
import '../../../tts/presentation/bloc/tts_bloc.dart';
import '../../../tts/presentation/bloc/tts_event.dart';
import 'detection_event.dart';
import 'detection_state.dart';

class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final LoadModelUsecase         _loadModel;
  final DetectionObjectFromFrame _detectFromFrame;
  final TtsBloc                  _ttsBloc;

  bool _isProcessing = false;
  DateTime _lastSpoken = DateTime(0);
  Map<String, double> _previousObjects = {};

  DetectionBloc({
    required LoadModelUsecase         loadModel,
    required DetectionObjectFromFrame detectFromFrame,
    required TtsBloc                  ttsBloc,
  })  : _loadModel      = loadModel,
        _detectFromFrame = detectFromFrame,
        _ttsBloc         = ttsBloc,
        super(const DetectionInitial()) {
    on<DetectionStarted>(_onStarted);
    on<DetectionStopped>(_onStopped);
    on<DetectionFrameReceived>(_onFrameReceived);
  }

  // ── Load model ─────────────────────────────────────────────────────────────

  Future<void> _onStarted(
    DetectionStarted event,
    Emitter<DetectionState> emit,
  ) async {
    debugPrint('[DetectionBloc] DetectionStarted → loading model...');
    emit(const DetectionLoading());
    try {
      await _loadModel.load();
      debugPrint('[DetectionBloc] model loaded → DetectionModelReady');
      emit(const DetectionModelReady());
    } catch (e) {
      debugPrint('[DetectionBloc] model load FAILED: $e');
      emit(DetectionFailure(e.toString()));
    }
  }

  void _onStopped(DetectionStopped event, Emitter<DetectionState> emit) {
    _ttsBloc.add(const TtsStop());
    _previousObjects.clear();
    _isProcessing = false;
    emit(const DetectionInitial());
  }

  // ── Per-frame detection ────────────────────────────────────────────────────

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    if (_isProcessing) return; // Frame trước chưa xong
    _isProcessing = true;

    try {
      debugPrint('[DetectionBloc] running inference...');
      final detections = await _detectFromFrame(event.image);
      debugPrint('[DetectionBloc] got ${detections.length} detections');

      if (detections.isEmpty) return;

      emit(DetectionSuccess(detections: detections));

      // ── TTS logic ────────────────────────────────────────────
      final currentObjects = {
        for (final d in detections) d.label: d.boundingBox.area,
      };

      final candidates = <dynamic>[];
      for (final d in detections) {
        final oldArea = _previousObjects[d.label];
        if (oldArea == null || d.boundingBox.area > oldArea * 1.3) {
          candidates.add(d);
        }
      }
      _previousObjects = currentObjects;

      if (candidates.isEmpty) return;

      final now = DateTime.now();
      if (now.difference(_lastSpoken).inMilliseconds < 1500) return;
      _lastSpoken = now;

      final dangerous = candidates
          .where((d) => d.isDangerous)
          .toList()
        ..sort((a, b) => b.boundingBox.area.compareTo(a.boundingBox.area));

      if (dangerous.isNotEmpty) {
        debugPrint('[DetectionBloc] TTS danger: ${dangerous.first.voiceWarning}');
        _ttsBloc.add(TtsSpeak(
          dangerous.first.voiceWarning,
          immediate:     true,
          withVibration: true,
        ));
      } else {
        final top = candidates.reduce(
          (a, b) => a.confidence > b.confidence ? a : b,
        );
        debugPrint('[DetectionBloc] TTS: ${top.voiceWarning}');
        _ttsBloc.add(TtsSpeak(top.voiceWarning));
      }
    } catch (e) {
      debugPrint('[DetectionBloc] _onFrameReceived error: $e');
    } finally {
      _isProcessing = false;
    }
  }
}