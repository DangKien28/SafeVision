import 'package:permission_handler/permission_handler.dart';
import '../error/exceptions.dart';

class AppPermissionHandler {
  AppPermissionHandler._();

  static Future<void> requestCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      throw const PermissionException(
        'Quyền camera bị từ chối. Vui lòng cấp quyền trong Cài đặt.',
      );
    }
  }

  static Future<void> requestMicrophone() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw const PermissionException(
        'Quyền micro bị từ chối.',
      );
    }
  }

  static Future<bool> isCameraGranted() async =>
      await Permission.camera.isGranted;

  static Future<void> openSettings() => openAppSettings();
}
