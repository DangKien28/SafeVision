import 'package:permission_handler/permission_handler.dart';
import '../error/exceptions.dart';

class AppPermissionHandler {
  AppPermissionHandler._();

  /// Yêu cầu quyền camera, ném PermissionException nếu bị từ chối
  static Future<void> requestCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      throw const PermissionException(
        'Quyền camera bị từ chối. Vui lòng cấp quyền trong Cài đặt.',
      );
    }
  }

  /// Yêu cầu quyền microphone (dùng nếu cần audio)
  static Future<void> requestMicrophone() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw const PermissionException(
        'Quyền microphone bị từ chối.',
      );
    }
  }

  /// Kiểm tra không yêu cầu lại
  static Future<bool> isCameraGranted() async =>
      await Permission.camera.isGranted;

  /// Mở cài đặt ứng dụng nếu quyền bị từ chối vĩnh viễn
  static Future<void> openSettings() => openAppSettings();
}