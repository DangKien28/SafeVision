/// Hằng số dùng chung cho toàn bộ logic cử chỉ của SafeVision.
class GestureConstants {
  static const double swipeVelocityThreshold = 650.0;
  static const Duration cameraFrameThrottle = Duration(milliseconds: 330);
  static const Duration ttsFeedbackCooldown = Duration(milliseconds: 900);

  static const String swipeLeft = 'Vuốt sang trái';
  static const String swipeRight = 'Vuốt sang phải';
  static const String swipeUp = 'Vuốt lên';
  static const String swipeDown = 'Vuốt xuống';
  static const String tap = 'Chạm một lần';
  static const String doubleTap = 'Chạm đúp';
  static const String longPress = 'Nhấn giữ';
}