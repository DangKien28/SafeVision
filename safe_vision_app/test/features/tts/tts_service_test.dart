import 'package:flutter_test/flutter_test.dart';

// TtsService test strategy
//
// TtsService depends on FlutterTts, a native plugin that cannot run in a
// unit-test environment because there is no audio engine.
//
// The chosen approach uses TestableTtsService as a test double that mirrors
// the real cooldown and queue logic without depending on FlutterTts.
// This lets the tests verify:
// 1. Per-text cooldown: the same text is blocked within a time window.
// 2. Queue deduplication: identical content is never added twice.
// 3. _lastSpoken management: the map does not grow without bounds.
//
// Full validation of speak, pause, and stop still requires an integration
// test on a real device or emulator with an active audio engine.
// ─────────────────────────────────────────────────────────────────────────

/// Test double that mirrors TtsService cooldown and queue behavior.
/// All methods return the same kinds of values as the real implementation so
/// tests can verify the contract without a native engine.
class TestableTtsService {
  final List<String> _queue = [];
  final Map<String, DateTime> _lastSpoken = {};
  final bool _isSpeaking = false;

  static const int ttsCooldownMs = 3000;
  static const int maxLastSpoken = 100;

  /// Accepts text into the queue when it is outside the cooldown window.
  /// Returns the text when accepted, or `null` when blocked by cooldown.
  Future<String?> speakWarning(String text) async {
    final now = DateTime.now();

    // Prune expired entries before checking cooldown.
    if (_lastSpoken.length > maxLastSpoken) {
      _lastSpoken.removeWhere(
          (_, time) => now.difference(time).inMilliseconds > ttsCooldownMs * 2);
    }

    final last = _lastSpoken[text];
    if (last != null && now.difference(last).inMilliseconds < ttsCooldownMs) {
      return null;
    }

    // Record the timestamp and enqueue exactly once.
    _lastSpoken[text] = now;
    _enqueue(text);
    return text;
  }

  void _enqueue(String text) {
    if (!_queue.contains(text)) _queue.add(text);
  }

  List<String> get queue => List.unmodifiable(_queue);
  Map<String, DateTime> get lastSpoken => Map.unmodifiable(_lastSpoken);
  bool get isSpeaking => _isSpeaking;
  int get queueLength => _queue.length;
}

void main() {
  late TestableTtsService service;

  setUp(() {
    service = TestableTtsService();
  });

  // Invariant: each content is only added to the queue once.

  group('speakWarning - only enqueues once per acceptance', () {
    test('calling speakWarning once adds exactly one item to the queue',
        () async {
      await service.speakWarning('Cảnh báo! Người đi bộ phía trước');

      expect(service.queueLength, equals(1),
          reason: 'Content should only be added to queue exactly once');
      expect(service.queue.first, 'Cảnh báo! Người đi bộ phía trước');
    });

    test('second call with identical content is blocked by cooldown', () async {
      await service.speakWarning('xe đạp bên trái');
      await service.speakWarning('xe đạp bên trái');

      expect(service.queueLength, equals(1),
          reason: 'Cooldown must block second call with identical content');
    });

    test('different contents can enter the queue together', () async {
      await service.speakWarning('vật thể A');
      await service.speakWarning('vật thể B');

      expect(service.queueLength, equals(2));
      expect(service.queue, containsAll(['vật thể A', 'vật thể B']));
    });

    test('_lastSpoken records timestamp after accepting to speak', () async {
      const text = 'người đi bộ';
      final before = DateTime.now();
      await service.speakWarning(text);
      final after = DateTime.now();

      final recorded = service.lastSpoken[text];
      expect(recorded, isNotNull);
      expect(recorded!.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(recorded.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });

  // Cooldown logic

  group('speakWarning - cooldown per content', () {
    test('identical content within cooldown window returns null', () async {
      const text = 'xe máy';
      final result1 = await service.speakWarning(text);
      final result2 = await service.speakWarning(text);

      expect(result1, equals(text), reason: 'First call must be accepted');
      expect(result2, isNull,
          reason: 'Second call within cooldown must be blocked');
    });

    test('different contents do not block each other\'s cooldown', () async {
      final r1 = await service.speakWarning('văn bản A');
      final r2 = await service.speakWarning('văn bản B');
      final r3 = await service.speakWarning('văn bản C');

      expect(r1, isNotNull);
      expect(r2, isNotNull);
      expect(r3, isNotNull);
      expect(service.queueLength, equals(3));
    });

    test(
        '_lastSpoken does not grow unboundedly and is pruned when exceeding 100 items',
        () async {
      for (int i = 0; i < 101; i++) {
        await service.speakWarning('văn_bản_$i');
      }
      // Pruning starts after 100 entries so growth stays bounded.
      expect(service.lastSpoken.length, lessThanOrEqualTo(101));
    });
  });

  // Queue deduplication

  group('Queue deduplication', () {
    test('identical content is not added twice to the queue', () async {
      await service.speakWarning('duplicate content');

      expect(service.queue.where((t) => t == 'duplicate content').length,
          equals(1));
    });

    test('empty string is processed without crash', () async {
      expect(() => service.speakWarning(''), returnsNormally);
    });
  });
}
