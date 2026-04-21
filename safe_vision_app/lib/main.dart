import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'config/routes/app_routes.dart';
import 'config/theme/app_theme.dart';
import 'features/detection/presentation/bloc/detection_bloc.dart';
import 'features/tts/presentation/bloc/tts_bloc.dart';
import 'features/settings/presentation/bloc/settings_bloc.dart';
import 'features/settings/presentation/bloc/settings_event.dart';
import 'injection_container.dart' as di;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await di.init();

  runApp(const SafeVisionApp());
}

class SafeVisionApp extends StatelessWidget {
  const SafeVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<TtsBloc>(
          create: (_) => di.sl<TtsBloc>(),
        ),
        BlocProvider<DetectionBloc>(
          create: (_) => di.sl<DetectionBloc>(),
        ),
        BlocProvider<SettingsBloc>(
          create: (_) => di.sl<SettingsBloc>()..add(const SettingsLoaded()),
        ),
      ],
      child: MaterialApp(
        title: 'Safe Vision',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        initialRoute: AppRoutes.camera,
        onGenerateRoute: AppRoutes.onGenerateRoute,
      ),
    );
  }
}
