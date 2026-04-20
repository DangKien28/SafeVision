import 'package:flutter/material.dart';

class DetectionControlBar extends StatelessWidget {
  const DetectionControlBar({
    super.key,
    required this.onStop,
    required this.onSettings,
    required this.onSwitchCamera,
  });

  final VoidCallback onStop;
  final VoidCallback onSettings;
  final VoidCallback onSwitchCamera;
  static const double _kMinAccessibleTouchTarget = 56;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stopButtonBaseStyle =
        theme.elevatedButtonTheme.style ?? ElevatedButton.styleFrom();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Cài đặt',
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(_kMinAccessibleTouchTarget),
                    foregroundColor: colorScheme.onSurface,
                  ),
                  icon: const Icon(Icons.settings, size: 30),
                  onPressed: onSettings,
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Đổi camera',
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(_kMinAccessibleTouchTarget),
                    foregroundColor: colorScheme.onSurface,
                  ),
                  icon: const Icon(Icons.cameraswitch_outlined, size: 30),
                  onPressed: onSwitchCamera,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: stopButtonBaseStyle.copyWith(
                      minimumSize: const WidgetStatePropertyAll(
                        Size.square(_kMinAccessibleTouchTarget),
                      ),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      textStyle: WidgetStatePropertyAll(
                        theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.stop_circle_outlined, size: 24),
                    label: const Text('Dừng', maxLines: 1),
                    onPressed: onStop,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
