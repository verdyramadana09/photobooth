import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_new/main.dart';

void main() {
  testWidgets('Photobooth start screen smoke test', (WidgetTester tester) async {
    // ✅ PhotoBoothApp tidak perlu cameras lagi — kamera di-request saat CameraScreen dibuka
    await tester.pumpWidget(const PhotoBoothApp());

    // Verifikasi StartScreen muncul dengan teks yang benar
    expect(find.text('Start Session'), findsOneWidget);
    expect(find.text('Upload Template'), findsOneWidget);

    // Pastikan tidak ada teks '0' (bekas template counter default Flutter)
    expect(find.text('0'), findsNothing);
  });
}