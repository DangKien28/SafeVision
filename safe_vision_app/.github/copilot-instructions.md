# SafeVision AI Agent Instructions

## Project Overview
SafeVision is a Flutter mobile app designed to help visually impaired users identify objects in their environment using real-time camera detection with YOLOv8 model via TensorFlow Lite.

**Target Platforms:** Android, iOS, Windows, macOS, Linux, Web

## Architecture Pattern: Clean Architecture + BLoC

The codebase follows Clean Architecture divided into three layers:
- **Presentation** (`presentation/`): UI, widgets, BLoC event handlers
- **Domain** (`domain/`): Business logic, entities, abstract repositories
- **Data** (`data/`): Data sources, concrete repository implementations

**Feature Structure:**
```
lib/features/{feature_name}/
├── presentation/  (pages, widgets, bloc)
├── domain/        (entities, repositories, usecases)
└── data/          (datasources, repositories)
```

## Core Dependencies & Patterns

### State Management: Flutter BLoC
- Use `flutter_bloc` (v9.1.1) for state management
- Event-driven architecture: UI dispatches events → BLoC processes → state updates
- Example: [lib/features/tts/presentation/bloc/tts_event.dart](lib/features/tts/presentation/bloc/tts_event.dart)

### Key External Services
1. **AI Model:** YOLOv8 TensorFlow Lite (`tflite_flutter: ^0.10.4`)
   - Model path: `assets/models/yolov8n_safevision.tflite`
   - Labels: `assets/models/labels.txt`
   - Initialization: [lib/core/utils/ai_helper.dart](lib/core/utils/ai_helper.dart) line 11-17

2. **Camera:** Real-time capture for object detection
   - Managed by `CameraController` in [lib/features/detection/presentation/pages/camera_view_page.dart](lib/features/detection/presentation/pages/camera_view_page.dart)
   - Resolution: Medium preset to balance speed/quality

3. **Text-to-Speech (TTS):** Voice feedback for accessibility
   - Service: [lib/features/tts/data/datasources/tts_service.dart](lib/features/tts/data/datasources/tts_service.dart)
   - Helper: [lib/core/utils/voice_helper.dart](lib/core/utils/voice_helper.dart)

4. **Permissions:** Camera access required at startup
   - Utility: [lib/core/utils/permission_handler.dart](lib/core/utils/permission_handler.dart)

## Critical Implementation Details

### Detection Flow
1. User triggers capture → `_handleDetectionRequest()` in CameraViewPage
2. Image bytes captured and passed to `AiHelper.predict(imageBytes)`
3. Model outputs detections as `List<Recognition>` (id, label, score, Rect location)
4. Bounding boxes rendered via `BoundingBoxPainter` custom painter
5. TTS announces detected objects via `VoiceHelper`

### Recognition Entity
```dart
class Recognition {
  final int id;
  final String label;
  final double score;
  final Rect location; // Bounding box for UI rendering
}
```

### UI Accessibility Requirements
- **High Contrast Theme:** [lib/config/theme/app_theme.dart](lib/config/theme/app_theme.dart)
- **Large Buttons:** Minimum 80dp height, 24pt font size (Task SAF-24)
- **Voice Feedback:** All key actions announced via TTS
- **Haptic Feedback:** Heavy impact on detection, light on ready state

### Processing Lock Pattern
To prevent UI spam during model inference:
```dart
bool _isProcessing = false; // Lock during model prediction
if (_isProcessing) return; // Early exit if already processing
setState(() => _isProcessing = true);
// ... inference happens here ...
setState(() => _isProcessing = false);
```
See [lib/features/detection/presentation/pages/camera_view_page.dart](lib/features/detection/presentation/pages/camera_view_page.dart) line 59-60.

## Build & Development

### Flutter Commands
```bash
flutter pub get           # Install dependencies
flutter analyze          # Check code quality (includes flutter_lints)
flutter build apk        # Build Android APK
flutter build ios        # Build iOS app
flutter test            # Run widget tests
```

### Code Quality Standards
- Lint rules: [analysis_options.yaml](analysis_options.yaml) (extends flutter_lints)
- Dart version: >=3.0.0 <4.0.0
- Suppress lints with: `// ignore: lint_name` or `// ignore_for_file: lint_name`

### Asset Configuration
- Models, icons, images, sounds registered in [pubspec.yaml](pubspec.yaml)
- Runtime asset loading: `rootBundle.loadString()` for labels, `Interpreter.fromAsset()` for models

## Common Workflows

**Adding New Object Detection Feature:**
1. Create feature folder: `lib/features/{feature}/` with domain/data/presentation
2. Define `Recognition`-based entities
3. Add BLoC events in `presentation/bloc/{feature}_event.dart`
4. Implement repository in `domain/repositories/`
5. Update AI model if needed in assets/models/

**Fixing Permission Issues:**
- Check [lib/core/utils/permission_handler.dart](lib/core/utils/permission_handler.dart) for camera permission logic
- Ensure `handleCameraPermission()` completes before camera initialization

**Accessibility Improvements:**
- Modify theme in [lib/config/theme/app_theme.dart](lib/config/theme/app_theme.dart)
- Add TTS calls via `VoiceHelper` for new actions
- Test with high contrast + large font settings

## Known Conventions

- **Comments in Vietnamese:** Code comments explain Vietnamese-specific context (education project from Vietnam)
- **Task References:** Code comments cite SAF-XX task IDs (e.g., SAF-26: remove redundant screen transitions)
- **Class Requirements:** Some classes have required markers in comments, e.g., `// PHẢI CÓ CHỮ "class Recognition" Ở ĐÂY`
