// lib/config/routes/app_routes.dart

import 'package:flutter/material.dart';
import '../../features/detection/presentation/pages/camera_view_page.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String camera = '/';
  static const String settings = '/settings';

  // Error message shown on unknown routes.
  static const String _unknownRouteMessage = 'Page not found';

  static Route<dynamic> onGenerateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case camera:
        return MaterialPageRoute(builder: (_) => const CameraViewPage());
      case settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text(_unknownRouteMessage)),
          ),
        );
    }
  }
}
