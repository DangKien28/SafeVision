import 'package:flutter/material.dart';

/// Bảng màu tương phản cực cao cho SafeVision.
class AppColors {
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF111111);
  static const Color surfaceAlt = Color(0xFF1A1A1A);

  static const Color primary = Color(0xFFFFFF00);
  static const Color secondary = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFF00E5FF);
  static const Color danger = Color(0xFFFF5252);

  static const Color onBackground = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFFFFFFFF);
  static const Color onPrimary = Color(0xFF000000);
  static const Color onSecondary = Color(0xFF000000);

  static const Color divider = Color(0xFF3A3A3A);
  static const Color success = Color(0xFF76FF03);

  static const Color cameraBorder = Color(0xFFFFFF00);
  static const Color textMuted = Color(0xFFCCCCCC);

  // Tên cũ được giữ lại để không phá vỡ các file theme hiện có.
  static const Color textPrimary = onBackground;
  static const Color textSecondary = textMuted;
  static const Color error = danger;
}