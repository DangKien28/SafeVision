import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get highContrastTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      
      // Cấu hình Nút bấm lớn (Task SAF-24)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          textStyle: const TextStyle(
            fontSize: 24, // Chữ rất to
            fontWeight: FontWeight.bold,
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(double.infinity, 80), // Nút luôn rộng và cao tối thiểu 80dp
        ),
      ),

      // Cấu hình Text
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        bodyLarge: TextStyle(fontSize: 20, color: AppColors.textPrimary),
      ),
    );
  }
}