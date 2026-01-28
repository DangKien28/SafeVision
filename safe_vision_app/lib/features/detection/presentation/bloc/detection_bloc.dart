import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:safe_vision_app/features/detection/domain/usecases/detection_object_from_frame.dart';
import 'detection_event.dart';
import 'detection_state.dart';

class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  final DetectFromFrameUsecase detectUsecase;

  DetectionBloc(this.detectUsecase) : super(DetectionInitial()) {
    on<DetectFromFrameEvent>((event, emit) async {
      emit(DetectionLoading());
      try {
        final boxes = await detectUsecase(event.imageBytes);
        emit(DetectionLoaded(boxes));
      } catch (e) {
        emit(DetectionError(e.toString()));
      }
    });
  }
}
