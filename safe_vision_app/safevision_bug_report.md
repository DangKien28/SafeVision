
🔴 CRITICAL BUG #1 — _closeFuture race condition in DetectionBloc
Root Cause
dart// detection_bloc.dart
Future<void> _onStopped(...) async {
  _closeFuture = _closeModel.call(const NoParams());
  await _closeFuture;  // ← stored AND awaited
}

Future<void> _onStarted(...) async {
  if (_closeFuture != null) {
    await _closeFuture;
    _closeFuture = null;  // ← cleared here
  }
  // ...
}
Problem: _closeFuture is set to the completed future after _onStopped awaits it. A concurrent _onStarted may see _closeFuture != null but it is already resolved — harmless but wasteful. Worse: if _closeModel throws, _closeFuture holds a rejected future. A subsequent _onStarted will await a rejected future and crash silently.
Approaches
ArchitectPragmaticFixUse Completer with try/finallyWrap await _closeFuture in try/catchTrade-offClean but adds complexitySimple, acceptable for this use case
Pragmatic wins — one try/catch is sufficient:
dart// detection_bloc.dart

Future<void> _onStarted(
  DetectionStarted event,
  Emitter<DetectionState> emit,
) async {
  if (_closeFuture != null) {
    try {
      await _closeFuture;
    } catch (_) {
      // Close failed — log but don't block startup
      debugPrint('[DetectionBloc] awaiting _closeFuture threw, continuing');
    } finally {
      _closeFuture = null;
    }
  }
  _previousObjects = {};
  _consecutiveFrames = {};
  _sortBuffer.clear();
  emit(const DetectionLoading());
  try {
    await _loadModel.call(const NoParams());
    emit(const DetectionModelReady());
  } catch (e) {
    debugPrint('[DetectionBloc] model load FAILED: $e');
    emit(DetectionFailure(e.toString()));
  }
}

🔴 CRITICAL BUG #2 — onDone() never called on inference timeout in BLoC
Root Cause
dart// detection_bloc.dart — _onFrameReceived
try {
  final detections = await _detectFromFrame(...).timeout(
    const Duration(seconds: 3),
    onTimeout: () => [],  // ← returns [] but onDone is in finally — OK
  );
  // ...
} catch (e) {
  debugPrint('[DetectionBloc] _onFrameReceived error: $e');
  // ← NO rethrow, but finally still runs — OK
} finally {
  event.onDone();  // ← this IS called — correct
}
Actually this is fine — finally always runs. But there's a subtler issue: droppable() transformer drops the event entirely before _onFrameReceived is even called when a frame is in-flight. The dropped event's onDone is never called, leaving CameraService._isProcessingFrame = true permanently if the first frame's inference stalls forever.
The real scenario:

Frame A dispatched → _isProcessingFrame = true → BLoC starts processing
Frame B dispatched (CameraService already dropped it due to busy lock) — safe
But: if droppable() drops the event after it enters the BLoC event queue (before _onFrameReceived fires), onDone is never invoked

Looking at bloc_concurrency's droppable() — it uses exhaustMap, so the second event is dropped at the stream level before the handler is called. CameraService already guards with _isProcessingFrame before dispatching. So frames only reach the BLoC when the lock is free. This is actually safe by design — but only because of the double-guard. This should be documented explicitly.
dart// Add to CameraService.startImageStream — already correct but document:
// INVARIANT: A frame is dispatched to onFrame only when _isProcessingFrame==false.
// DetectionBloc's droppable() transformer is defense-in-depth, not primary guard.

🔴 CRITICAL BUG #3 — Memory leak in BoundingBoxPainter._textCache
Root Cause
dartstatic final Map<String, TextPainter> _textCache = {};
static const int _maxCacheEntries = 100;

TextPainter _getOrCreatePainter(String label) {
  if (_textCache.containsKey(label)) return _textCache[label]!;

  if (_textCache.length >= _maxCacheEntries) {
    final toEvict = _textCache.keys.take(_maxCacheEntries ~/ 2).toList();
    for (final key in toEvict) {
      _textCache[key]!.dispose();  // ← correct
      _textCache.remove(key);
    }
  }
  // ...
}
Problem 1: dispose() on the painter only removes labels owned by that instance's boxes. If label "car" was created by painter A, but painter B (which doesn't have "car" in its boxes) replaces it — the cache entry for "car" is never disposed by B.
Problem 2: The eviction takes the first 50 keys from a Map — but Map iteration order in Dart is insertion order. This means frequently used labels (inserted early) get evicted while rarely used ones (inserted recently) survive. This is inverted LRU.
dart// CURRENT — wrong eviction order
final toEvict = _textCache.keys.take(_maxCacheEntries ~/ 2).toList();
// Evicts oldest-inserted, which may be the most-used labels
Fix — Use proper LRU with promotion
dart// bounding_box_painter.dart

/// LRU TextPainter cache. Promotes on access to maintain true LRU order.
/// Uses LinkedHashMap insertion-order semantics: head = oldest, tail = newest.
static final Map<String, TextPainter> _textCache = LinkedHashMap();
static const int _maxCacheEntries = 50; // Reduced — 100 is excessive for label count

TextPainter _getOrCreatePainter(String label) {
  // Cache hit → promote to tail (most recently used)
  if (_textCache.containsKey(label)) {
    final tp = _textCache.remove(label)!;
    _textCache[label] = tp; // reinsert at tail
    return tp;
  }

  // Evict least recently used (head) when at capacity
  if (_textCache.length >= _maxCacheEntries) {
    final lruKey = _textCache.keys.first; // head = LRU
    _textCache.remove(lruKey)!.dispose();
  }

  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 200);

  _textCache[label] = painter;
  return painter;
}
Also fix dispose() — it should not try to remove from the static cache based on instance boxes:
dartvoid dispose() {
  // Instance dispose: only clear entries this painter uniquely owns.
  // Since the cache is shared, only remove if the value is still the
  // same object (prevents double-free across painter instances).
  for (final box in boxes) {
    // Don't remove from shared cache on instance dispose —
    // the cache manages its own lifecycle via LRU eviction.
    // This method is intentionally a no-op for the static cache.
  }
}

🟡 PERFORMANCE BUG #4 — _triggerWarningIfNeeded allocates on every frame
Root Cause
dartvoid _triggerWarningIfNeeded(List<DetectionObject> detections) {
  final currentObjects = _groupAreasByLabel(detections); // ← Map allocation

  _sortBuffer..clear()..addAll(detections)..sort(...);

  final candidates = <DetectionObject>[]; // ← List allocation per frame
  final currentIndices = <String, int>{};  // ← Map allocation per frame
  final newConsecutive = <String, int>{};  // ← Map allocation per frame
  // ...
}
At 6 FPS this allocates ~4 objects/frame = ~24 heap allocations/second. Minor but cumulative GC pressure.
Fix — Reuse maps with clear()
dart// Add to DetectionBloc fields:
final Map<String, int> _currentIndicesBuffer = {};
final Map<String, int> _newConsecutiveBuffer = {};
final List<DetectionObject> _candidatesBuffer = [];

void _triggerWarningIfNeeded(List<DetectionObject> detections) {
  final currentObjects = _groupAreasByLabel(detections);

  _sortBuffer
    ..clear()
    ..addAll(detections)
    ..sort((a, b) {
      final c = a.label.compareTo(b.label);
      return c != 0 ? c : b.boundingBox.area.compareTo(a.boundingBox.area);
    });

  _candidatesBuffer.clear();
  _currentIndicesBuffer.clear();
  _newConsecutiveBuffer.clear();

  for (final d in _sortBuffer) {
    final idx = _currentIndicesBuffer.update(
      d.label, (v) => v + 1, ifAbsent: () => 0,
    );
    final presenceKey = '${d.label}_$idx';
    final prevCount = _consecutiveFrames[presenceKey] ?? 0;
    final currentCount = prevCount + 1;
    _newConsecutiveBuffer[presenceKey] = currentCount;

    final previousAreas = _previousObjects[d.label];
    final oldArea = previousAreas != null && idx < previousAreas.length
        ? previousAreas[idx] : null;

    final isApproaching = oldArea != null && d.boundingBox.area > oldArea * 1.3;
    final isStable = currentCount == 3;
    final isFirstSeen = currentCount == 1;

    if (isApproaching || isStable || isFirstSeen) _candidatesBuffer.add(d);
  }

  _previousObjects = currentObjects;
  _consecutiveFrames = Map.of(_newConsecutiveBuffer);

  if (_candidatesBuffer.isEmpty) return;

  // ... rest unchanged
}

// Also clear in close():
@override
Future<void> close() async {
  _sortBuffer.clear();
  _candidatesBuffer.clear();
  _currentIndicesBuffer.clear();
  _newConsecutiveBuffer.clear();
  return super.close();
}

🟡 PERFORMANCE BUG #5 — presenceKey string allocation per detection per frame
Root Cause
dartfinal presenceKey = '${d.label}_$idx'; // string interpolation = heap alloc
At 6 FPS with 10 detections = 60 string allocations/second.
Fix — Use a composite key struct or encode as int
dart// For labels up to ~1000 unique entries and index up to 99:
// Encode as (label.hashCode << 7) | idx — NOT collision-safe for all labels
// Better: use a record type (Dart 3+)
typedef _PresenceKey = (String, int);

final Map<_PresenceKey, int> _consecutiveFrames = {};
final Map<_PresenceKey, int> _newConsecutiveBuffer = {};

// Usage:
final presenceKey = (d.label, idx);
final prevCount = _consecutiveFrames[presenceKey] ?? 0;
Records in Dart 3 are value-equal by default, making them correct map keys without string allocation.

🟡 BUG #6 — CameraService._streamGeneration not incremented in switchCamera
Root Cause
dartFuture<void> switchCamera() async {
  if (_cameras.length < 2) return;
  _currentIndex = (_currentIndex + 1) % _cameras.length;
  await _setupController(_cameras[_currentIndex]);
  // _setupController DOES increment _streamGeneration ✓
}
Actually _setupController does increment it — this is fine. ✓

🟡 BUG #7 — DetectionLocalDatasourceImpl._killAndRespawnIsolate has a TOCTOU window
Root Cause
dartFuture<void> _killAndRespawnIsolate() async {
  final oldSendPort = _isolateSendPort;
  // ...
  _isolateSendPort = null;
  _isolateBusy = false; // ← reset here

  // ... async gap ...
  await _spawnIsolate(modelBytes); // ← during this gap, runInference
                                    // could be called with null sendPort
  // but returns [] due to null check — safe
}
The null check in runInference:
dartif (!_modelLoaded || _isolateSendPort == null) return [];
This is safe. ✓

🟡 BUG #8 — TtsService._pruneLastSpoken throttle is wrong direction
Root Cause
dartvoid _pruneLastSpoken(DateTime now) {
  if (_lastPruneAt != null &&
      now.difference(_lastPruneAt!).inMilliseconds < AppConstants.ttsCooldownMs) {
    return; // ← skip if last prune was within 3 seconds
  }
  _lastPruneAt = now;
  // ...
}
This is actually correct — prune runs at most once per cooldown window. ✓
But there's a different issue: _lastSpoken uses LinkedHashMap but the code uses it both as a regular Map and relies on insertion order for LRU:
dartfinal LinkedHashMap<String, DateTime> _lastSpoken =
    LinkedHashMap<String, DateTime>();

// LRU promotion:
_lastSpoken.remove(text);
_lastSpoken[text] = now; // reinsert at tail — correct ✓
This is correct. ✓

🟡 BUG #9 — _CameraViewPageState._boxNotifier disposed while listener active
Root Cause
dart@override
void dispose() {
  _phase = _LifecyclePhase.disposed;
  // ...
  _disposeBoxNotifier(); // ← disposes notifier
  unawaited(_cameraService.dispose()); // ← async, may call onFrame after notifier disposed
  super.dispose();
}

void _setBoxes(List<SmoothedBox> boxes) {
  if (_phase == _LifecyclePhase.disposed || _boxNotifierDisposed) return;
  _boxNotifier.value = boxes; // ← guarded correctly ✓
}
The guard _boxNotifierDisposed prevents writing to a disposed notifier. ✓
But unawaited(_cameraService.dispose()) runs async — during this window, an in-flight onFrame callback could complete and call event.onDone(), which is fine, but the BLoC listener could fire _setBoxes. The _phase == disposed check catches this. ✓

🔴 ACTUAL BUG #10 — shouldRepaint fallback is broken
Root Cause
dart@override
bool shouldRepaint(covariant BoundingBoxPainter old) {
  if (mirrorHorizontal != old.mirrorHorizontal) return true;
  if (_version != old._version) return true;
  // Fallback when versioning is not provided (`version == 0` on both sides).
  if (_version == 0 && old._version == 0) {
    if (boxes.length != old.boxes.length) return true;
    for (int i = 0; i < boxes.length; i++) {
      if (boxes[i] != old.boxes[i]) return true;
    }
  }
  return false;
}
Problem: BoundingBoxPainter is constructed in _DetectionOverlay without a version parameter:
dart// camera_view_page.dart
painter: BoundingBoxPainter(
  boxes: boxes,
  mirrorHorizontal: isFront,
), // ← no version passed → version defaults to 0
So both old and new painters have version == 0 → falls through to O(n) comparison every rebuild. The O(1) optimization is never used in production.
Fix — Wire BoxTracker.version to BoundingBoxPainter
dart// camera_view_page.dart — in _DetectionOverlay

// Add version to SmoothedBox or carry it separately
// Option: store version alongside boxes in a record

// Step 1: Change ValueNotifier type
late final ValueNotifier<({List<SmoothedBox> boxes, int version})> _boxNotifier =
    ValueNotifier((boxes: const [], version: 0));

// Step 2: Update _setBoxes
void _setBoxes(List<SmoothedBox> boxes) {
  if (_phase == _LifecyclePhase.disposed || _boxNotifierDisposed) return;
  _boxNotifier.value = (boxes: boxes, version: _tracker.version);
}

// Step 3: Update builder
ValueListenableBuilder<({List<SmoothedBox> boxes, int version})>(
  valueListenable: boxNotifier,
  builder: (_, data, __) => IgnorePointer(
    child: CustomPaint(
      painter: BoundingBoxPainter(
        boxes: data.boxes,
        mirrorHorizontal: isFront,
        version: data.version,  // ← now O(1) shouldRepaint works
      ),
    ),
  ),
),

🟡 BUG #11 — SettingsBloc._onLoaded ignores stored TTS language
dartFuture<void> _onLoaded(...) async {
  // ...
  final language = AppConstants.ttsLanguage; // ← ignores _repository.getTtsLanguage()
  // ...
}
await _repository.getTtsLanguage() is never awaited — the result is discarded. This is intentional (language is locked to vi-VN) but the getTtsLanguage() call in SettingsRepositoryImpl is dead code. Document or remove it.

🟡 BUG #12 — _isolateBusy reset timing in _killAndRespawnIsolate
dartFuture<void> _killAndRespawnIsolate() async {
  // ...
  _isolateBusy = false; // reset early ← OK since we're on main isolate
  // ...
  await _spawnIsolate(modelBytes); // long async op
  // during this await, _isolateBusy = false → runInference could enter
  // but _isolateSendPort is null → returns [] ✓
}


 COMPLETE IMPLEMENTATION
dart// lib/features/detection/presentation/widgets/bounding_box_painter.dart
// PATCH: Fix LRU cache eviction order

import 'dart:collection';

// Replace _textCache declaration:
static final LinkedHashMap<String, TextPainter> _textCache = LinkedHashMap();
static const int _maxCacheEntries = 50;

TextPainter _getOrCreatePainter(String label) {
  if (_textCache.containsKey(label)) {
    // Promote to MRU position
    final tp = _textCache.remove(label)!;
    _textCache[label] = tp;
    return tp;
  }
  if (_textCache.length >= _maxCacheEntries) {
    // Evict LRU (head of LinkedHashMap)
    _textCache.remove(_textCache.keys.first)!.dispose();
  }
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 200);
  _textCache[label] = painter;
  return painter;
}
dart// lib/features/detection/presentation/bloc/detection_bloc.dart
// PATCH 1: Safe _closeFuture awaiting
// PATCH 2: Reduce per-frame allocations
// PATCH 3: Use record keys instead of string interpolation

import 'dart:async';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/detection_object.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/usecases/load_model_usecase.dart';
import '../../domain/usecases/close_model_usecase.dart';
import '../../domain/usecases/detection_object_from_frame.dart';
import '../../../../core/utils/perf_monitor.dart';
import 'detection_event.dart';
import 'detection_state.dart';

typedef DetectionWarningCallback = void Function({
  required String text,
  required bool immediate,
  required bool withVibration,
});

// Dart 3 record — value-equal, no string allocation
typedef _PresenceKey = (String label, int index);

class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final LoadModelUsecase _loadModel;
  final CloseModelUsecase _closeModel;
  final DetectionObjectFromFrame _detectFromFrame;
  final DetectionWarningCallback _onWarning;

  Map<String, List<double>> _previousObjects = {};
  Map<_PresenceKey, int> _consecutiveFrames = {};

  // Reusable buffers — no per-frame heap allocation
  final List<DetectionObject> _sortBuffer = [];
  final List<DetectionObject> _candidatesBuffer = [];
  final Map<String, int> _currentIndicesBuffer = {};
  final Map<_PresenceKey, int> _newConsecutiveBuffer = {};

  Future<void>? _closeFuture;

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
    on<DetectionStarted>(_onStarted);
    on<DetectionStopped>(_onStopped);
    on<DetectionFrameReceived>(_onFrameReceived, transformer: droppable());
  }

  Future<void> _onStarted(
    DetectionStarted event,
    Emitter<DetectionState> emit,
  ) async {
    if (_closeFuture != null) {
      try {
        await _closeFuture;
      } catch (e) {
        debugPrint('[DetectionBloc] _closeFuture threw on restart: $e');
      } finally {
        _closeFuture = null;
      }
    }
    _clearTrackingState();
    if (kDebugMode) debugPrint('[DetectionBloc] loading model...');
    emit(const DetectionLoading());
    try {
      await _loadModel.call(const NoParams());
      if (kDebugMode) debugPrint('[DetectionBloc] model loaded');
      emit(const DetectionModelReady());
    } catch (e) {
      debugPrint('[DetectionBloc] model load FAILED: $e');
      emit(DetectionFailure(e.toString()));
    }
  }

  Future<void> _onStopped(
    DetectionStopped event,
    Emitter<DetectionState> emit,
  ) async {
    _clearTrackingState();
    emit(const DetectionInitial());
    _closeFuture = _closeModel.call(const NoParams());
    try {
      await _closeFuture;
    } catch (e) {
      debugPrint('[DetectionBloc] closeModel error: $e');
    } finally {
      _closeFuture = null;
    }
  }

  void _clearTrackingState() {
    _previousObjects = {};
    _consecutiveFrames = {};
    _sortBuffer.clear();
    _candidatesBuffer.clear();
    _currentIndicesBuffer.clear();
    _newConsecutiveBuffer.clear();
  }

  Future<void> _onFrameReceived(
    DetectionFrameReceived event,
    Emitter<DetectionState> emit,
  ) async {
    final sw = kDebugMode ? (Stopwatch()..start()) : null;
    try {
      final detections = await _detectFromFrame(
        event.image,
        rotationDegrees: event.rotationDegrees,
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          if (kDebugMode) debugPrint('[DetectionBloc] inference timeout');
          return <DetectionObject>[];
        },
      );

      if (kDebugMode) {
        sw?.stop();
        PerfMonitor.inferenceCompleted(sw?.elapsedMilliseconds ?? 0);
        PerfMonitor.frameReceived();
        if (detections.isNotEmpty) {
          debugPrint('[DetectionBloc] detections=${detections.length}');
        }
      }

      emit(DetectionSuccess(
        detections: detections,
        timestamp: DateTime.now().microsecondsSinceEpoch,
      ));

      if (detections.isNotEmpty) _triggerWarningIfNeeded(detections);
    } catch (e) {
      debugPrint('[DetectionBloc] _onFrameReceived error: $e');
    } finally {
      event.onDone();
    }
  }

  void _triggerWarningIfNeeded(List<DetectionObject> detections) {
    final currentObjects = _groupAreasByLabel(detections);

    _sortBuffer
      ..clear()
      ..addAll(detections)
      ..sort((a, b) {
        final c = a.label.compareTo(b.label);
        return c != 0 ? c : b.boundingBox.area.compareTo(a.boundingBox.area);
      });

    _candidatesBuffer.clear();
    _currentIndicesBuffer.clear();
    _newConsecutiveBuffer.clear();

    for (final d in _sortBuffer) {
      final idx = _currentIndicesBuffer.update(
        d.label, (v) => v + 1, ifAbsent: () => 0,
      );
      final key = (d.label, idx); // record — no string alloc
      final prevCount = _consecutiveFrames[key] ?? 0;
      final currentCount = prevCount + 1;
      _newConsecutiveBuffer[key] = currentCount;

      final previousAreas = _previousObjects[d.label];
      final oldArea = (previousAreas != null && idx < previousAreas.length)
          ? previousAreas[idx]
          : null;

      final isApproaching =
          oldArea != null && d.boundingBox.area > oldArea * 1.3;
      final isStable = currentCount == 3;
      final isFirstSeen = currentCount == 1;

      if (isApproaching || isStable || isFirstSeen) _candidatesBuffer.add(d);
    }

    _previousObjects = currentObjects;
    _consecutiveFrames = Map.of(_newConsecutiveBuffer);

    if (_candidatesBuffer.isEmpty) return;

    final dangerous = _candidatesBuffer.where((d) => d.isDangerous).toList()
      ..sort((a, b) => b.boundingBox.area.compareTo(a.boundingBox.area));

    if (dangerous.isNotEmpty) {
      _onWarning(
        text: dangerous.first.voiceWarning,
        immediate: true,
        withVibration: true,
      );
    } else {
      final top = _candidatesBuffer
          .reduce((a, b) => a.confidence > b.confidence ? a : b);
      _onWarning(
        text: top.voiceWarning,
        immediate: false,
        withVibration: false,
      );
    }
  }

  Map<String, List<double>> _groupAreasByLabel(List<DetectionObject> d) {
    final grouped = <String, List<double>>{};
    for (final det in d) {
      grouped.putIfAbsent(det.label, () => <double>[])
          .add(det.boundingBox.area);
    }
    for (final areas in grouped.values) {
      areas.sort((a, b) => b.compareTo(a));
    }
    return grouped;
  }

  @override
  Future<void> close() async {
    _sortBuffer.clear();
    _candidatesBuffer.clear();
    _currentIndicesBuffer.clear();
    _newConsecutiveBuffer.clear();
    return super.close();
  }
}
dart// lib/features/detection/presentation/pages/camera_view_page.dart
// PATCH: Wire BoxTracker.version to BoundingBoxPainter for O(1) shouldRepaint

// Change notifier type:
late final ValueNotifier<({List<SmoothedBox> boxes, int version})> _boxNotifier =
    ValueNotifier((boxes: const [], version: 0));

// Update _setBoxes:
void _setBoxes(List<SmoothedBox> boxes) {
  if (_phase == _LifecyclePhase.disposed || _boxNotifierDisposed) return;
  _boxNotifier.value = (boxes: boxes, version: _tracker.version);
}

// In _DetectionOverlay, update ValueListenableBuilder:
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

// Update _disposeBoxNotifier type compatibility — no change needed
// Update _boxNotifier declaration in dispose:
void _disposeBoxNotifier() {
  if (_boxNotifierDisposed) return;
  _boxNotifierDisposed = true;
  _boxNotifier.dispose();
}

🧪 PERFORMANCE VALIDATION
dart// Add to PerfMonitor — already has FPS tracking.
// Measure shouldRepaint call frequency:

// In BoundingBoxPainter.shouldRepaint (debug only):
@override
bool shouldRepaint(covariant BoundingBoxPainter old) {
  assert(() {
    debugPrint('[Painter] shouldRepaint called, version=$_version old=${old._version}');
    return true;
  }());
  // ...
}

// Measure GC pressure with:
// flutter run --profile
// Then: flutter pub global run devtools
// → Memory tab → watch heap growth rate at 6FPS
// Target: <1MB/s heap growth in steady state
Dropped frame detection (already in PerfMonitor):
bash# In debug mode, watch for:
[PerfMonitor] FPS≈5.8 | inference≈180ms | dropped=12
# If dropped > 5% of total frames → investigate isolate timing

🔁 PASS 2 — Hidden Issues
Issue A: _groupAreasByLabel creates a new Map every frame
Could reuse with clear() similarly to other buffers. Minor at 6 FPS.
Issue B: DetectionSuccess.timestamp uses microsecondsSinceEpoch
This prevents Equatable equality from ever matching two identical detection lists, which is correct for forcing re-renders. But it means BlocBuilder.buildWhen never short-circuits on DetectionSuccess. The current buildWhen excludes DetectionSuccess entirely for the builder — correct.
Issue C: _RawBox in isolate uses const constructor on a non-const class
dartclass _RawBox {
  // ...
  const _RawBox({...}); // ← const constructor but fields are all final primitives
}
This is fine. ✓
Issue D: yuvToLetterboxedFloat32 has no fast path for 0° rotation
The most common phone orientation (portrait) is 0°. The switch(rotationDegrees) hits the default case with identity transform — no optimization opportunity here since pixel access is already O(1).