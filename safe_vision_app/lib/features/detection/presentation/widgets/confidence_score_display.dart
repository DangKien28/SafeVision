import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
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

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final items = detections.take(maxItems).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phát hiện: ${detections.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              ...items.map((d) => _DetectionRow(detection: d)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectionRow extends StatelessWidget {
  const _DetectionRow({required this.detection});

  final DetectionObject detection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = detection.label;
    final confidence = detection.confidence;
    final pct = (confidence * 100).round();
    final isDanger = detection.isDangerous;

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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDanger
                        ? AppColors.boundingBoxDanger
                        : AppColors.boundingBoxDefault,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: confidence.clamp(0.0, 1.0),
            backgroundColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(
              isDanger
                  ? AppColors.boundingBoxDanger
                  : AppColors.boundingBoxDefault,
            ),
            minHeight: 4,
          ),
        ],
      ),
    );
  }
}
