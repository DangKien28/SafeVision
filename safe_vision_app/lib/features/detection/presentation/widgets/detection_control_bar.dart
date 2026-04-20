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

  static const double _kBarHeight = 88;
  static const double _kStopButtonHeight = 56;
  static const double _kStopButtonWidth = 148;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        width: double.infinity,
        height: _kBarHeight,
        color: Colors.black.withValues(alpha: 0.55),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Cài đặt',
              icon: const Icon(Icons.settings, size: 32, color: Colors.white),
              onPressed: onSettings,
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Đổi camera',
              icon: const Icon(
                Icons.cameraswitch_outlined,
                size: 32,
                color: Colors.white,
              ),
              onPressed: onSwitchCamera,
            ),
            const Spacer(),
            SizedBox(
              width: _kStopButtonWidth,
              height: _kStopButtonHeight,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.stop_circle_outlined, size: 28),
                label: const Text('Dừng'),
                onPressed: onStop,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
