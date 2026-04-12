// lib/features/tts/data/datasources/tts_service.dart

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../../core/constants/app_constants.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();

  bool _isSpeaking = false;
  final List<String> _queue = [];

  /// LinkedHashMap preserves insertion order so the oldest entry is always
  /// `_lastSpoken.entries.first` — O(1) LRU eviction without sorting.
  final LinkedHashMap<String, DateTime> _lastSpoken =
      LinkedHashMap<String, DateTime>();

  /// Timestamp of the last prune pass. Pruning runs at most once per cooldown
  /// window to avoid an O(n) scan on every frame callback.
  DateTime? _lastPruneAt;

  String _language = AppConstants.ttsLanguage;
  double _speechRate = AppConstants.ttsSpeechRate;
  double _pitch = AppConstants.ttsPitch;
  double _volume = AppConstants.ttsVolume;

  Future<void> initialize({
    String? language,
    double? speechRate,
    double? pitch,
    double? volume,
  }) async {
    _language = AppConstants.ttsLanguage;
    if (speechRate != null) _speechRate = speechRate;
    if (pitch != null) _pitch = pitch;
    if (volume != null) _volume = volume;

    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _tts.setVolume(_volume);

    _tts.setStartHandler(() => _isSpeaking = true);
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      _processQueue();
    });
    _tts.setCancelHandler(() {
      _isSpeaking = false;
      _queue.clear();
    });
    _tts.setErrorHandler((_) {
      _isSpeaking = false;
      _processQueue();
    });
  }

  Future<bool> speakWarning(String text) async {
    final now = DateTime.now();
    _pruneLastSpoken(now);

    final last = _lastSpoken[text];
    if (last != null &&
        now.difference(last).inMilliseconds < AppConstants.ttsCooldownMs) {
      return false;
    }

    // LRU promotion: remove then reinsert so this entry moves to the end
    // (most recently used). The LinkedHashMap's head is always the oldest.
    _lastSpoken.remove(text);
    _lastSpoken[text] = now;

    _enqueue(text);
    return true;
  }

  Future<bool> speakImmediate(String text) async {
    final now = DateTime.now();
    _pruneLastSpoken(now);

    final last = _lastSpoken[text];
    if (last != null &&
        now.difference(last).inMilliseconds < AppConstants.ttsCooldownMs) {
      return false;
    }

    _lastSpoken.remove(text);
    _lastSpoken[text] = now;

    await _tts.stop();
    _queue.clear();
    _isSpeaking = false;
    await _speak(text);
    return true;
  }

  Future<void> stop() async {
    _queue.clear();
    _lastSpoken.clear();
    _lastPruneAt = null;
    await _tts.stop();
    _isSpeaking = false;
  }

  Future<void> pause() async => _tts.pause();
  bool get isSpeaking => _isSpeaking;

  Future<void> dispose() async {
    _queue.clear();
    _lastSpoken.clear();
    _lastPruneAt = null;
    await _tts.stop();
    _isSpeaking = false;
  }

  // ── Private ──────────────────────────────────────────────────────────────

  /// Removes entries older than 2× the cooldown window.
  ///
  /// Runs at most once per cooldown period to keep the TTS hot path O(1).
  /// Uses insertion-order traversal of [LinkedHashMap] so the oldest entries
  /// are evicted first without any sorting.
  void _pruneLastSpoken(DateTime now) {
    // Throttle: skip prune if we ran one within the last cooldown window.
    if (_lastPruneAt != null &&
        now.difference(_lastPruneAt!).inMilliseconds <
            AppConstants.ttsCooldownMs) {
      return;
    }
    _lastPruneAt = now;

    final cutoff = now.subtract(
      Duration(milliseconds: AppConstants.ttsCooldownMs * 2),
    );

    // LinkedHashMap head = oldest entry. Walk forward and remove until
    // we find a fresh entry (all remaining entries are guaranteed fresher).
    while (_lastSpoken.isNotEmpty) {
      final oldest = _lastSpoken.entries.first;
      if (oldest.value.isBefore(cutoff)) {
        _lastSpoken.remove(oldest.key);
      } else {
        break;
      }
    }
  }

  void _enqueue(String text) {
    if (!_queue.contains(text)) _queue.add(text);
    if (!_isSpeaking) _processQueue();
  }

  void _processQueue() {
    if (_queue.isEmpty || _isSpeaking) return;
    _speak(_queue.removeAt(0));
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    _isSpeaking = true;
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TtsService] speak error: $e');
      _isSpeaking = false;
      _processQueue();
    }
  }
}
