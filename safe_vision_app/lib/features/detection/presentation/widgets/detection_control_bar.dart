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
  static const double _kMinAccessibleTouchTarget = 80;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stopButtonBaseStyle =
        theme.elevatedButtonTheme.style ?? ElevatedButton.styleFrom();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 320;
        final outerHorizontalPadding = isCompact ? 4.0 : 16.0;
        final innerHorizontalPadding = isCompact ? 4.0 : 12.0;
        final iconSpacing = isCompact ? 4.0 : 8.0;
        final stopSpacing = isCompact ? 4.0 : 12.0;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              outerHorizontalPadding,
              0,
              outerHorizontalPadding,
              12,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.28),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: innerHorizontalPadding,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Cài đặt',
                      style: IconButton.styleFrom(
                        minimumSize:
                            const Size.square(_kMinAccessibleTouchTarget),
                        foregroundColor: colorScheme.onSurface,
                      ),
                      icon: const Icon(Icons.settings, size: 30),
                      onPressed: onSettings,
                    ),
                    SizedBox(width: iconSpacing),
                    IconButton(
                      tooltip: 'Đổi camera',
                      style: IconButton.styleFrom(
                        minimumSize:
                            const Size.square(_kMinAccessibleTouchTarget),
                        foregroundColor: colorScheme.onSurface,
                      ),
                      icon: const Icon(Icons.cameraswitch_outlined, size: 30),
                      onPressed: onSwitchCamera,
                    ),
                    SizedBox(width: stopSpacing),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: stopButtonBaseStyle.copyWith(
                          minimumSize: const WidgetStatePropertyAll(
                            Size.square(_kMinAccessibleTouchTarget),
                          ),
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          textStyle: WidgetStatePropertyAll(
                            theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ) ??
                                const TextStyle(
                                  fontSize: 18,
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
      },
    );
  }
}
