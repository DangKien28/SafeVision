import 'package:flutter/material.dart';
import 'config/theme/app_theme.dart';
import 'features/detection/presentation/pages/camera_view_page.dart';

void main() {
  runApp(const SafeVisionApp());
}

class SafeVisionApp extends StatelessWidget {
  const SafeVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeVision',
      debugShowCheckedModeBanner: false,
      // Áp dụng cấu hình tương phản cao
      theme: AppTheme.highContrastTheme,
      // Mở thẳng màn hình camera (Task SAF-26: Loại bỏ thao tác thừa)
      home: const CameraViewPage(),
    );
  }
}