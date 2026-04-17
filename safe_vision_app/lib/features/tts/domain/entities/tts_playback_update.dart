 
import 'package:equatable/equatable.dart';
 
enum TtsPlaybackStatus { started, stopped, error }
 
class TtsPlaybackUpdate extends Equatable {
  const TtsPlaybackUpdate({
    required this.status,
    this.text,
    this.error,
  });
 
  final TtsPlaybackStatus status;
  final String? text;
  final String? error;
 
  @override
  List<Object?> get props => [status, text, error];
}