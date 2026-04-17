import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  const Failure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

class ModelFailure extends Failure {
  const ModelFailure(super.m);
}

class InferenceFailure extends Failure {
  const InferenceFailure(super.m);
}

class CameraFailure extends Failure {
  const CameraFailure(super.m);
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.m);
}

class UnknownFailure extends Failure {
  const UnknownFailure(super.m);
}
