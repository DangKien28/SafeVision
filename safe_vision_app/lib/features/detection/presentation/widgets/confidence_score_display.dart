import 'package:flutter/material.dart';

import '../../domain/entities/detection_object.dart';

/// Displays a confidence score panel for detected objects.
///
/// Shows at most [maxItems] objects, each with:
///   - Vietnamese display label
///   - Confidence percentage
///   - [LinearProgressIndicator] bar
///
/// Renders a zero-size [SizedBox] when [detections] is empty so the camera
/// feed is not obscured.
class ConfidenceScoreDisplay extends StatelessWidget {
  const ConfidenceScoreDisplay({
    super.key,
    required this.detections,
    this.maxItems = 5,
  });

  final List<DetectionObject> detections;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) return const SizedBox.shrink();

    final items = detections.take(maxItems).toList();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: count badge
          Text(
            'Phát hiện: ${detections.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          ...items.map((d) => _DetectionRow(detection: d)),
        ],
      ),
    );
  }
}

class _DetectionRow extends StatelessWidget {
  const _DetectionRow({required this.detection});

  final DetectionObject detection;

  @override
  Widget build(BuildContext context) {
    final label      = detection.label;
    final confidence = detection.confidence;
    final pct        = (confidence * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: detection.isDangerous
                        ? Colors.orangeAccent
                        : Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: confidence.clamp(0.0, 1.0),
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation<Color>(
              detection.isDangerous ? Colors.orange : Colors.greenAccent,
            ),
            minHeight: 4,
          ),
        ],
      ),
    );
  }
}