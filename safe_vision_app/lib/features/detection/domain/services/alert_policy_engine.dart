import '../../../../core/constants/app_constants.dart';
import '../entities/tracked_detection.dart';

class AlertDecision {
  const AlertDecision({
    required this.text,
    required this.immediate,
    required this.withVibration,
  });

  final String text;
  final bool immediate;
  final bool withVibration;
}

class AlertPolicyEngine {
  final Map<int, _TrackAlertInfo> _trackInfos = {};
  int _lastDangerousAlertAtMs = -1;
  int _lastLowVisibilityAlertAtMs = -1;

  AlertDecision? evaluate({
    required List<TrackedDetection> trackedDetections,
    required bool lowVisibility,
    required int nowMs,
  }) {
    if (lowVisibility &&
        _isCooldownOver(_lastLowVisibilityAlertAtMs, nowMs,
            AppConstants.lowVisibilityWarningCooldownMs)) {
      _lastLowVisibilityAlertAtMs = nowMs;
      return const AlertDecision(
        text: 'Cảnh báo: tầm nhìn kém, vui lòng di chuyển chậm và cẩn thận.',
        immediate: false,
        withVibration: false,
      );
    }

    final visibleTracks =
        trackedDetections.where((track) => track.isVisible).toList();
    if (visibleTracks.isEmpty) return null;

    final visibleIds = visibleTracks.map((t) => t.trackId).toSet();
    _trackInfos.removeWhere((id, _) => !visibleIds.contains(id));

    for (final tracked in visibleTracks) {
      _trackInfos.putIfAbsent(tracked.trackId, _TrackAlertInfo.new).seenCount++;
    }

    final candidates = visibleTracks
        .where(
          (tracked) =>
              (_trackInfos[tracked.trackId]?.seenCount ?? 0) >=
              AppConstants.alertStabilityFrames,
        )
        .toList()
      ..sort((a, b) {
        final dangerOrder = (b.detection.isDangerous ? 1 : 0) -
            (a.detection.isDangerous ? 1 : 0);
        if (dangerOrder != 0) return dangerOrder;

        final areaOrder = b.detection.boundingBox.area
            .compareTo(a.detection.boundingBox.area);
        if (areaOrder != 0) return areaOrder;

        return b.detection.confidence.compareTo(a.detection.confidence);
      });

    if (candidates.isEmpty) return null;

    final top = candidates.first;
    final info = _trackInfos[top.trackId]!;
    final isDangerous = top.detection.isDangerous;

    if (isDangerous) {
      if (!_isCooldownOver(_lastDangerousAlertAtMs, nowMs,
          AppConstants.alertDangerousCooldownMs)) {
        return null;
      }
      _lastDangerousAlertAtMs = nowMs;
      info.warnedSafeTrack = true;
      return AlertDecision(
        text: top.detection.voiceWarning,
        immediate: true,
        withVibration: true,
      );
    }

    if (info.warnedSafeTrack) return null;
    info.warnedSafeTrack = true;
    return AlertDecision(
      text: top.detection.voiceWarning,
      immediate: false,
      withVibration: false,
    );
  }

  void reset() {
    _trackInfos.clear();
    _lastDangerousAlertAtMs = -1;
    _lastLowVisibilityAlertAtMs = -1;
  }

  bool _isCooldownOver(int previousMs, int nowMs, int cooldownMs) {
    if (previousMs < 0) return true;
    return nowMs - previousMs >= cooldownMs;
  }
}

class _TrackAlertInfo {
  int seenCount = 0;
  bool warnedSafeTrack = false;
}
