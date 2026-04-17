// Abstract UseCase contract used across all features.

abstract class UseCase<Type, Params> {
  Future<Type> call(Params params);
}

/// Sentinel parameter for use cases that take no input.
class NoParams {
  const NoParams();
}
