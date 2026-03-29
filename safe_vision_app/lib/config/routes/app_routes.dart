import 'package:flutter/material.dart';
import '../../features/detection/presentation/pages/camera_view_page.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String camera   = '/';
  static const String settings = '/settings';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case camera:
        return MaterialPageRoute(builder: (_) => const CameraViewPage());
      case AppRoutes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Trang không tồn tại')),
          ),
        );
    }
  }
}