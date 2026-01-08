import 'package:flutter/material.dart';

class ConfidenceScoreDisplay extends StatelessWidget {
  final double confidence;

  const ConfidenceScoreDisplay({
    super.key,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Độ tin cậy: ${(confidence * 100).toInt()}%',
        style: const TextStyle(
          fontSize: 24,
          color: Colors.white,
        ),
      ),
    );
  }
}
