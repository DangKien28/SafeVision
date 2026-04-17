import 'package:permission_handler/permission_handler.dart' as ph
    show
        Permission,
        openAppSettings,
        PermissionActions,
        PermissionStatusGetters;

import '../error/exceptions.dart';

/// Centralises all runtime permission requests for SafeVision.
///
/// ## Usage
///
/// ```dart
/// await AppPermissionHandler.requestCamera();   // throws on denial
/// await _cameraService.initialize();
/// ```
///
/// ## Contract
///
/// [requestCamera] throws [PermissionException] when the user has
/// permanently denied the camera permission.  Callers MUST catch this
/// and surface a settings deep-link to the user so they can re-enable it.
abstract class AppPermissionHandler {
  AppPermissionHandler._();

  /// Requests the camera permission.
  ///
  /// * If already granted, returns immediately.
  /// * If the system shows a rationale dialog, waits for user response.
  /// * If permanently denied, opens App Settings and throws
  ///   [PermissionException] so the caller can update the UI.
  static Future<void> requestCamera() async {
    var status = await ph.Permission.camera.status;

    if (status.isGranted) return;

    if (status.isPermanentlyDenied) {
      await ph.openAppSettings();
      throw const PermissionException(
        'Quyền camera bị từ chối. Vui lòng cấp quyền trong Cài đặt.',
      );
    }

    // Request from the OS.
    status = await ph.Permission.camera.request();

    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        await ph.openAppSettings();
      }
      throw const PermissionException(
        'Quyền camera bị từ chối. Vui lòng cấp quyền trong Cài đặt.',
      );
    }
  }

  /// Requests the microphone permission (reserved for future use).
  static Future<void> requestMicrophone() async {
    final status = await ph.Permission.microphone.request();
    if (!status.isGranted) {
      throw const PermissionException('Quyền micro bị từ chối.');
    }
  }

  /// Opens the application settings page so the user can grant permissions
  /// that were permanently denied.
  static Future<void> openSettings() => ph.openAppSettings();
}
