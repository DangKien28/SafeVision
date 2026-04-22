class ModelNotFoundException implements Exception {
  final String message;
  const ModelNotFoundException(this.message);
  @override
  String toString() => 'ModelNotFoundException: $message';
}

class InferenceException implements Exception {
  final String message;
  const InferenceException(this.message);
  @override
  String toString() => 'InferenceException: $message';
}

class CameraException implements Exception {
  final String message;
  const CameraException(this.message);
  @override
  String toString() => 'CameraException: $message';
}

class PermissionException implements Exception {
  final String message;
  const PermissionException(this.message);
  @override
  String toString() => 'PermissionException: $message';
}

class ImageConversionException implements Exception {
  final String message;
  const ImageConversionException(this.message);
  @override
  String toString() => 'ImageConversionException: $message';
}
