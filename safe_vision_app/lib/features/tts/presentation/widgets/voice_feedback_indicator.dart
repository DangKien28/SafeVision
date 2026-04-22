import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/tts_bloc.dart';
import '../bloc/tts_state.dart';

class VoiceFeedbackIndicator extends StatelessWidget {
  const VoiceFeedbackIndicator({super.key});

  /// FIX RC-7: Distinguish warning speech from informational speech.
  /// "Cảnh báo!" prefix = warning → orange indicator (correct UX semantics).
  /// Other text (e.g. "Hệ thống sẵn sàng") = informational → green indicator.
  /// Previously, all states used green which is semantically "safe/success",
  /// contradicting the "Cảnh báo!" text alongside it.
  static bool _isWarningText(String text) =>
      text.startsWith('Cảnh báo') || text.startsWith('canh bao');

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TtsBloc, TtsState>(
      builder: (context, state) {
        if (state is! TtsSpeaking) return const SizedBox.shrink();

        final isWarning = _isWarningText(state.text);
        // Orange for warnings, green for informational announcements.
        final indicatorColor =
            isWarning ? Colors.orangeAccent : Colors.greenAccent;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: indicatorColor.withValues(alpha: 0.75),
              width: isWarning ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulsingDot(color: indicatorColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  state.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: _anim.value),
        ),
      ),
    );
  }
}
