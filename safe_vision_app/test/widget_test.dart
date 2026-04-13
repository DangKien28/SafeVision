import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'; // Bắt buộc import thư viện này để dùng SemanticsFlag
import 'package:flutter_test/flutter_test.dart';

// Đảm bảo đường dẫn này khớp với tên package trong file pubspec.yaml của bạn
import 'package:safe_vision_app/core/presentation/widgets/accessible_button.dart';
import 'package:safe_vision_app/core/presentation/widgets/accessible_swipe_layout.dart';

void main() {
  group('AccessibleButton Tests', () {
    testWidgets('Nút bấm phải chứa đúng Label, Hint và cờ isButton cho trình đọc màn hình', (WidgetTester tester) async {
      // Bật Semantics trong môi trường Test
      tester.ensureSemantics();

      bool isTapped = false;

      // Bơm Widget vào môi trường test
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleButton(
              semanticLabel: 'Nhận diện môi trường',
              semanticHint: 'Chạm hai lần để quét',
              onTap: () {
                isTapped = true;
              },
              child: const Text('QUÉT'),
            ),
          ),
        ),
      );

      // Tìm Semantics của nút bấm
      final buttonSemantics = tester.getSemantics(find.byType(AccessibleButton));
      
      // Kiểm tra Label và Hint
      expect(buttonSemantics.label, 'Nhận diện môi trường');
      expect(buttonSemantics.hint, 'Chạm hai lần để quét');
      
      // KIỂM TRA LỖI ISBUTTON ĐÃ ĐƯỢC SỬA TẠI ĐÂY
      expect(buttonSemantics.hasFlag(SemanticsFlag.isButton), isTrue); 

      // Kịch bản: Người dùng chạm vào nút
      await tester.tap(find.byType(AccessibleButton));
      await tester.pump(); 
      
      expect(isTapped, isTrue); 
    });
  });

  group('AccessibleSwipeLayout Tests', () {
    testWidgets('Phải nhận diện đúng cử chỉ vuốt mạnh sang phải', (WidgetTester tester) async {
      bool swipedRight = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleSwipeLayout(
              onSwipeRight: () {
                swipedRight = true;
              },
              child: const Center(child: Text('Màn hình chính')),
            ),
          ),
        ),
      );

      // Vuốt ngang sang phải 500 pixel
      await tester.fling(find.text('Màn hình chính'), const Offset(500, 0), 1000.0);
      await tester.pumpAndSettle();

      expect(swipedRight, isTrue);
    });
  });
}