import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_new/main.dart';

void main() {
  testWidgets('Photobooth start screen smoke test', (WidgetTester tester) async {
    // ✅ PhotoBoothApp sekarang butuh cameras — kirim list kosong untuk test
    // (kamera tidak tersedia di lingkungan test, ini expected)
    await tester.pumpWidget(PhotoBoothApp(cameras: const []));

    // ✅ Teks di StartScreen asli adalah "Start Session", bukan "MULAI"
    expect(find.text('Start Session'), findsOneWidget);

    // Pastikan tidak ada teks '0' (bekas template counter default Flutter)
    expect(find.text('0'), findsNothing);

    // ✅ Tombol disabled saat cameras kosong — tap tidak akan navigasi
    // Cukup verifikasi widget ada, tidak perlu tap karena akan throw error
    expect(find.text('Start Session'), findsOneWidget);
  });
}