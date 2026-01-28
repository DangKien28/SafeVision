import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:safe_vision_app/features/detection/data/datasources/detection_local_datasource.dart';
import 'package:safe_vision_app/features/detection/domain/entities/bounding_box_entity.dart';
import 'package:safe_vision_app/features/detection/domain/repositories/detection_repository.dart';
import '../models/bounding_box_model.dart';

class DetectionLocalDatasourceImpl implements DetectionLocalDatasource {
  @override
  Future<List<BoundingBoxModel>> detect(List<int> imageBytes) async {
    final res = await http.post(
      Uri.parse("http://127.0.0.1:5000/detect"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"image": base64Encode(imageBytes)}),
    );

    final List data = jsonDecode(res.body);
    return data.map((e) => BoundingBoxModel.fromJson(e)).toList();
  }
}

class DetectionRepositoryImpl implements DetectionRepository {
  final DetectionLocalDatasource datasource;
  DetectionRepositoryImpl(this.datasource);

  @override
  Future<List<BoundingBoxEntity>> detect(List<int> imageBytes) async {
    final models = await datasource.detect(imageBytes);
    return models.map((e) => e.toEntity()).toList();
  }
}
