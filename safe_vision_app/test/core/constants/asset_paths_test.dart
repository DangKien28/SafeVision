import 'package:flutter_test/flutter_test.dart';
import 'package:safe_vision_app/core/constants/asset_paths.dart';

void main() {
  group('AssetPaths', () {
    test('modelDir is set', () {
      expect(AssetPaths.modelDir, 'assets/models/');
    });

    test('modelFile is set', () {
      expect(AssetPaths.modelFile, 'assets/models/yolov8n_safevision.tflite');
    });

    test('labels file is set', () {
      expect(AssetPaths.labels, 'assets/models/labels.txt');
    });

    test('iconApp path is set', () {
      expect(AssetPaths.iconApp, 'assets/icons/sv_icon.png');
    });

    test('logoSplash path is set', () {
      expect(AssetPaths.logoSplash, 'assets/images/sv_logo.png');
    });
  });
}
