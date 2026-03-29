import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);
  @override List<Object?> get props => [message];
}

class ModelFailure      extends Failure { const ModelFailure(super.message); }
class InferenceFailure  extends Failure { const InferenceFailure(super.message); }
class CameraFailure     extends Failure { const CameraFailure(super.message); }
class PermissionFailure extends Failure { const PermissionFailure(super.message); }
class UnknownFailure    extends Failure { const UnknownFailure(super.message); }