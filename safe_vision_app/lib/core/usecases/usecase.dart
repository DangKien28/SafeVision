abstract class UseCase<Output, Params> {
  Future<Output> call(Params params);
}

/// Sentinel parameter for use cases that take no input.
class NoParams {
  const NoParams();
}
