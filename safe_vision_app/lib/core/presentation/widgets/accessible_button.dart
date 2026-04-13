import 'package:flutter/material.dart';

/// Một nút bấm lớn, độ tương phản cao, tối ưu cho VoiceOver/TalkBack.
class AccessibleButton extends StatelessWidget {
  final String semanticLabel; // Hệ thống sẽ đọc nội dung này khi trỏ vào
  final String semanticHint;  // Gợi ý hành động (VD: "Chạm hai lần để kích hoạt")
  final VoidCallback onTap;   // Hành động khi nhấn
  final Widget child;         // Nội dung hiển thị bên trong nút
  final Color backgroundColor;
  final Color borderColor;

  const AccessibleButton({
    Key? key,
    required this.semanticLabel,
    required this.semanticHint,
    required this.onTap,
    required this.child,
    this.backgroundColor = Colors.black, // Mặc định nền đen
    this.borderColor = Colors.yellowAccent, // Mặc định viền vàng tương phản
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true, // Báo cho thiết bị biết đây là nút có thể tương tác
      label: semanticLabel,
      hint: semanticHint,
      // Thêm thuộc tính excludeSemantics để trình đọc màn hình bỏ qua các 
      // Text/Icon rườm rà bên trong, chỉ đọc label và hint ở trên.
      excludeSemantics: true, 
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8.0), // Khoảng cách giữa các nút
          padding: const EdgeInsets.all(24.0), // Khu vực chạm cực lớn
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border.all(color: borderColor, width: 4.0), // Viền dày dễ nhìn
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}