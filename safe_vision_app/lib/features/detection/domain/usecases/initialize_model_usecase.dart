import '../repositories/detection_repository.dart';

class InitializeModelUseCase {
  final DetectionRepository repository;

  InitializeModelUseCase(this.repository);

  Future<void> execute() async {
    await repository.initializeModel();
  }
}