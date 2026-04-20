import 'package:flutter/material.dart';

import 'config/theme/app_theme.dart';
import 'injection_container.dart';
import 'features/detection/presentation/pages/detection_page.dart';
import 'features/settings/presentation/pages/settings_page.dart';
import 'features/splash/splash_page.dart';

/// Root application widget.
///
/// Wires together the [MaterialApp], the high-contrast [AppTheme.darkTheme],
/// and the named-route table.
class SafeVisionApp extends StatelessWidget {
  const SafeVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeVision',
      debugShowCheckedModeBanner: false,

      // High-contrast dark theme required by accessibility specification.
      theme: AppTheme.darkTheme,

      initialRoute: SplashPage.routeName,
      routes: {
        SplashPage.routeName: (_) => const SplashPage(),
        DetectionPage.routeName: (_) => DetectionPage(
              settingsRepository: sl(),
            ),
        SettingsPage.routeName: (_) => const SettingsPage(),
      },
    );
  }
}
