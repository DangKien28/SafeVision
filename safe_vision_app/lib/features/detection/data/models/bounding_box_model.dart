import '../../domain/entities/detection_object.dart';

/// Data-layer DTO for a bounding box received from the TFLite isolate.
class BoundingBoxModel {
  const BoundingBoxModel({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  /// Parses a [Map] produced by the inference isolate.
  factory BoundingBoxModel.fromMap(Map<String, dynamic> map) =>
      BoundingBoxModel(
        left:   (map['left']   as num).toDouble(),
        top:    (map['top']    as num).toDouble(),
        width:  (map['width']  as num).toDouble(),
        height: (map['height'] as num).toDouble(),
      );

  /// Parses the [top, left, bottom, right] format used by some TFLite models.
  factory BoundingBoxModel.fromTFLiteList(List<dynamic> list) {
    final top    = (list[0] as num).toDouble();
    final left   = (list[1] as num).toDouble();
    final bottom = (list[2] as num).toDouble();
    final right  = (list[3] as num).toDouble();
    return BoundingBoxModel(
      left:   left,
      top:    top,
      width:  right - left,
      height: bottom - top,
    );
  }

  /// Converts to the domain entity.
  BoundingBox toEntity() =>
      BoundingBox(left: left, top: top, width: width, height: height);
}