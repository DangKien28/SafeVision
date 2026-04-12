import 'package:flutter/material.dart';
import '../../domain/entities/detection_object.dart';

class ConfidenceScoreDisplay extends StatelessWidget {
  final List<DetectionObject> detections;
  final int maxItems;

  const ConfidenceScoreDisplay({
    super.key,
    required this.detections,
    this.maxItems = 5,
  });

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) return const SizedBox.shrink();

    final sorted = [...detections]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final items = sorted.take(maxItems).toList();

    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Phát hiện ${detections.length} vật thể',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          ...items.map((d) => _DetectionRow(detection: d)),
        ],
      ),
    );
  }
}

class _DetectionRow extends StatelessWidget {
  final DetectionObject detection;
  const _DetectionRow({required this.detection});

  @override
  Widget build(BuildContext context) {
    final pct = detection.confidence.clamp(0.0, 1.0);
    final color = pct > 0.75
        ? Colors.greenAccent
        : pct > 0.5
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              detection.label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 36,
            child: Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
