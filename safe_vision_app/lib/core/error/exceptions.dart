class ModelNotFoundException implements Exception {
  const ModelNotFoundException(this.message);
  final String message;
  @override
  String toString() => 'ModelNotFoundException: $message';
}

class InferenceException implements Exception {
  const InferenceException(this.message);
  final String message;
  @override
  String toString() => 'InferenceException: $message';
}

class CameraException implements Exception {
  const CameraException(this.message);
  final String message;
  @override
  String toString() => 'CameraException: $message';
}

class PermissionException implements Exception {
  const PermissionException(this.message);
  final String message;
  @override
  String toString() => 'PermissionException: $message';
}

class ImageConversionException implements Exception {
  const ImageConversionException(this.message);
  final String message;
  @override
  String toString() => 'ImageConversionException: $message';
}
