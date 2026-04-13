import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/detection/data/datasources/tflite_local_datasource.dart';
import 'features/detection/data/repositories/detection_repository_impl.dart';
import 'features/detection/domain/usecases/detect_object_usecase.dart';
import 'features/detection/domain/usecases/initialize_model_usecase.dart';
import 'features/tts/domain/usecases/speak_text_usecase.dart';
import 'features/detection/presentation/bloc/detection_bloc.dart';
import 'features/detection/presentation/pages/detection_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final tfliteDataSource = TFLiteLocalDataSource();
  final detectionRepository = DetectionRepositoryImpl(dataSource: tfliteDataSource);

  final initModelUseCase = InitializeModelUseCase(detectionRepository);
  final detectObjectUseCase = DetectObjectUseCase(detectionRepository);
  final speakTextUseCase = SpeakTextUseCase();

  // BỎ try-catch ĐỂ NẾU LỖI, APP SẼ DỪNG LẠI VÀ BÁO ĐỎ LÊN MÀN HÌNH
  await initModelUseCase.execute();

  runApp(SafeVisionApp(
    detectObjectUseCase: detectObjectUseCase,
    speakTextUseCase: speakTextUseCase,
  ));
}

class SafeVisionApp extends StatelessWidget {
  final DetectObjectUseCase detectObjectUseCase;
  final SpeakTextUseCase speakTextUseCase;

  const SafeVisionApp({
    Key? key,
    required this.detectObjectUseCase,
    required this.speakTextUseCase,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Cung cấp BLoC cho toàn bộ cây Widget
    return MultiBlocProvider(
      providers: [
        BlocProvider<DetectionBloc>(
          create: (context) => DetectionBloc(
            detectObjectUseCase: detectObjectUseCase,
            speakTextUseCase: speakTextUseCase,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'SafeVision',
        debugShowCheckedModeBanner: false, // Ẩn chữ DEBUG
        // Cấu hình Theme tương phản cao (Màu Đen - Vàng chủ đạo)
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: Colors.yellowAccent,
            secondary: Colors.greenAccent,
            surface: Colors.black,
          ),
          useMaterial3: true,
        ),
        home: const DetectionPage(),
      ),
    );
  }
}