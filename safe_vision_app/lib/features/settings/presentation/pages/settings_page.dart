import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../injection_container.dart';
import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';
import '../bloc/settings_state.dart';
import '../../../tts/presentation/bloc/tts_bloc.dart';

/// Settings page for SafeVision.
///
/// All sliders and toggles are oversized (80 dp touch targets) to comply with
/// the accessibility requirement.  Every change is immediately persisted via
/// [SettingsBloc] and announced via TTS.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const routeName = '/settings';

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SettingsBloc>(
          create: (_) =>
              SettingsBloc(sl(), sl(), sl(), sl())..add(const SettingsLoaded()),
        ),
        BlocProvider<TtsBloc>(create: (_) => sl<TtsBloc>()),
      ],
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionHeader('Giọng đọc'),
              _VoiceToggle(enabled: state.voiceEnabled),
              const SizedBox(height: 16),
              _SpeechRateSlider(rate: state.speechRate),
              const SizedBox(height: 16),
              _LanguageButton(language: state.ttsLanguage),
              const Divider(),
              _SectionHeader('Nhận diện'),
              _ConfidenceSlider(threshold: state.confidenceThreshold),
              const Divider(),
              _SectionHeader('Hiển thị'),
              _PanelToggle(show: state.showConfidencePanel),
            ],
          );
        },
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF00E5FF),
                )),
      );
}

// ── Voice toggle ──────────────────────────────────────────────────────────────

class _VoiceToggle extends StatelessWidget {
  const _VoiceToggle({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.volume_up, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Bật giọng đọc', style: TextStyle(fontSize: 18)),
              ),
              Switch(
                value: enabled,
                onChanged: (v) =>
                    context.read<SettingsBloc>().add(SettingsVoiceToggled(v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Speech rate slider ────────────────────────────────────────────────────────

class _SpeechRateSlider extends StatelessWidget {
  const _SpeechRateSlider({required this.rate});
  final double rate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.speed, size: 24),
              const SizedBox(width: 8),
              Text('Tốc độ đọc: ${(rate * 100).round()}%',
                  style: const TextStyle(fontSize: 16)),
            ]),
            Slider(
              value: rate.clamp(0.1, 1.0),
              min: 0.1,
              max: 1.0,
              divisions: 18,
              label: '${(rate * 100).round()}%',
              onChangeEnd: (v) => context
                  .read<SettingsBloc>()
                  .add(SettingsSpeechRateChanged(v)),
              onChanged: (_) {}, // visual feedback only while dragging
            ),
          ],
        ),
      ),
    );
  }
}

// ── Language button ───────────────────────────────────────────────────────────

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.language});
  final String language;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.language, size: 28),
        label: Text('Ngôn ngữ: ${language.isNotEmpty ? language : "vi-VN"}'),
        onPressed: () => context
            .read<SettingsBloc>()
            .add(const SettingsTtsLanguageChanged()),
      ),
    );
  }
}

// ── Confidence slider ─────────────────────────────────────────────────────────

class _ConfidenceSlider extends StatelessWidget {
  const _ConfidenceSlider({required this.threshold});
  final double threshold;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.tune, size: 24),
              const SizedBox(width: 8),
              Text('Ngưỡng nhận diện: ${(threshold * 100).round()}%',
                  style: const TextStyle(fontSize: 16)),
            ]),
            Slider(
              value: threshold.clamp(0.01, 0.99),
              min: 0.10,
              max: 0.90,
              divisions: 16,
              label: '${(threshold * 100).round()}%',
              onChangeEnd: (v) => context
                  .read<SettingsBloc>()
                  .add(SettingsConfidenceChanged(v)),
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
  }
}

// ── Confidence panel toggle ───────────────────────────────────────────────────

class _PanelToggle extends StatelessWidget {
  const _PanelToggle({required this.show});
  final bool show;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.bar_chart, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Hiển thị bảng điểm tin cậy',
                    style: TextStyle(fontSize: 18)),
              ),
              Switch(
                value: show,
                onChanged: (v) => context
                    .read<SettingsBloc>()
                    .add(SettingsConfidencePanelToggled(v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
