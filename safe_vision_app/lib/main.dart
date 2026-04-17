
// Entry point.  Excluded from unit-test coverage (CI lcov filter).
//
// Sequence:
//   1. WidgetsFlutterBinding.ensureInitialized()
//   2. initDependencies() — registers all GetIt singletons/factories
//   3. runApp(SafeVisionApp())
//
// No heavyweight work is done here.  Model loading and camera initialisation
// happen inside the blocs, deferred to the first user interaction.
 
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safe_vision_app/app.dart';
 
import 'injection_container.dart' as di;
 
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
 
  // Lock to portrait; the camera feed and bounding boxes assume portrait.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
 
  // Register all dependencies lazily — no blocking I/O here.
  await di.initDependencies();
 
  // Make the status-bar transparent so the camera preview bleeds to the edge.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
 
  if (kDebugMode) {
    // Increase the isolate error threshold so inference errors surface as
    // debug prints rather than hard crashes during development.
    debugPrint('[SafeVision] Debug mode — isolate errors are non-fatal');
  }
 
  runApp(const SafeVisionApp());
}