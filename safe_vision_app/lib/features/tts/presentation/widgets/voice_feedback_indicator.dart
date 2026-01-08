import 'package:flutter/material.dart';
import '../../../../config/theme/app_colors.dart';

class VoiceFeedbackIndicator extends StatelessWidget {
  final bool isSpeaking;

  const VoiceFeedbackIndicator({super.key, required this.isSpeaking});

  @override
  Widget build(BuildContext context) {
    // SAF-24 & SAF-26: Hiển thị một vòng tròn hoặc thanh trạng thái lớn, màu sắc mạnh
    return Semantics(
      label: isSpeaking ? "Đang phát âm thanh hỗ trợ" : "Sẵn sàng nhận lệnh",
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSpeaking ? AppColors.primary : Colors.grey[900],
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4), // Viền trắng tương phản
        ),
        child: Icon(
          isSpeaking ? Icons.volume_up : Icons.mic_none,
          size: 80, // SAF-24: Icon cực lớn
          color: isSpeaking ? Colors.black : Colors.white,
        ),
      ),
    );
  }
}