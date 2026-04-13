import 'package:flutter/material.dart';

/// Widget bọc ngoài các màn hình để nhận diện cử chỉ vuốt của người khiếm thị.
class AccessibleSwipeLayout extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;

  const AccessibleSwipeLayout({
    Key? key,
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.onSwipeUp,
    this.onSwipeDown,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // onPanEnd kích hoạt khi người dùng kết thúc thao tác vuốt trên màn hình
      onPanEnd: (details) {
        // Lấy vận tốc vuốt theo trục X (ngang) và Y (dọc)
        final double velocityX = details.velocity.pixelsPerSecond.dx;
        final double velocityY = details.velocity.pixelsPerSecond.dy;

        // Cài đặt ngưỡng vận tốc (để tránh người dùng chạm nhầm)
        const double threshold = 300.0;

        if (velocityX.abs() > velocityY.abs()) {
          // Vuốt theo chiều ngang mạnh hơn chiều dọc
          if (velocityX > threshold && onSwipeRight != null) {
            onSwipeRight!();
          } else if (velocityX < -threshold && onSwipeLeft != null) {
            onSwipeLeft!();
          }
        } else {
          // Vuốt theo chiều dọc mạnh hơn chiều ngang
          if (velocityY > threshold && onSwipeDown != null) {
            onSwipeDown!();
          } else if (velocityY < -threshold && onSwipeUp != null) {
            onSwipeUp!();
          }
        }
      },
      child: child,
    );
  }
}