import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';
import '../bloc/settings_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
        centerTitle: true,
      ),
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionHeader(title: 'Giọng nói'),

              // Bật/tắt giọng nói
              SwitchListTile(
                title: const Text('Thông báo âm thanh'),
                subtitle: const Text('Đọc cảnh báo khi phát hiện vật thể'),
                value: state.voiceEnabled,
                onChanged: (v) => context
                    .read<SettingsBloc>()
                    .add(SettingsVoiceToggled(v)),
              ),

              // Tốc độ đọc
              ListTile(
                title: const Text('Tốc độ đọc'),
                subtitle: Slider(
                  value: state.speechRate,
                  min: 0.25,
                  max: 1.0,
                  divisions: 15,
                  label: state.speechRate.toStringAsFixed(2),
                  onChanged: state.voiceEnabled
                      ? (v) => context
                          .read<SettingsBloc>()
                          .add(SettingsSpeechRateChanged(v))
                      : null,
                ),
                trailing: Text(
                  state.speechRate.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),

              // Ngôn ngữ TTS
              ListTile(
                title: const Text('Ngôn ngữ'),
                trailing: DropdownButton<String>(
                  value: state.ttsLanguage,
                  items: const [
                    DropdownMenuItem(value: 'vi-VN', child: Text('Tiếng Việt')),
                    DropdownMenuItem(value: 'en-US', child: Text('English')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      context
                          .read<SettingsBloc>()
                          .add(SettingsTtsLanguageChanged(v));
                    }
                  },
                ),
              ),

              const Divider(height: 32),
              _SectionHeader(title: 'Phát hiện vật thể'),

              // Ngưỡng confidence
              ListTile(
                title: const Text('Ngưỡng độ tin cậy'),
                subtitle: Slider(
                  value: state.confidenceThreshold,
                  min: 0.1,
                  max: 0.95,
                  divisions: 17,
                  label:
                      '${(state.confidenceThreshold * 100).toStringAsFixed(0)}%',
                  onChanged: (v) => context
                      .read<SettingsBloc>()
                      .add(SettingsConfidenceChanged(v)),
                ),
                trailing: Text(
                  '${(state.confidenceThreshold * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),

              // Hiện panel confidence
              SwitchListTile(
                title: const Text('Hiện bảng kết quả'),
                subtitle:
                    const Text('Danh sách vật thể ở góc trên màn hình'),
                value: state.showConfidencePanel,
                onChanged: (v) => context
                    .read<SettingsBloc>()
                    .add(SettingsConfidencePanelToggled(v)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}