import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// ─────────────────────────────────────────────────────────────
/// QrService — membuat QR code dari URL download
///
/// Dependency yang dibutuhkan (tambahkan ke pubspec.yaml):
///   qr_flutter: ^4.1.0
/// ─────────────────────────────────────────────────────────────
class QrService {
  // ✅ Generate URL download (bisa diganti dengan URL server asli)
  static String generateDownloadLink(String fileName) {
    return "https://photobooth.verdy.dev/download/$fileName";
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ Widget QR yang bisa langsung dipakai di dalam UI
  //
  // Contoh pakai:
  //   QrService.buildQrWidget("namafile.png", size: 180)
  // ─────────────────────────────────────────────────────────────
  static Widget buildQrWidget(
    String fileName, {
    double size = 200,
    Color foregroundColor = Colors.black,
    Color backgroundColor = Colors.white,
  }) {
    final url = generateDownloadLink(fileName);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: url,
            version: QrVersions.auto,
            size: size,
            eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: foregroundColor,
            ),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: foregroundColor,
            ),
            backgroundColor: backgroundColor,
          ),
          const SizedBox(height: 8),
          Text(
            "Scan untuk download",
            style: TextStyle(
              fontSize: 12,
              color: foregroundColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ✅ Export QR sebagai PNG bytes (untuk disimpan / dicetak)
  //
  // Contoh pakai:
  //   final bytes = await QrService.generateQrBytes("namafile.png");
  //   await File("qr.png").writeAsBytes(bytes);
  // ─────────────────────────────────────────────────────────────
  static Future<Uint8List> generateQrBytes(
    String fileName, {
    double size = 400,
    Color foregroundColor = Colors.black,
    Color backgroundColor = Colors.white,
  }) async {
    final url = generateDownloadLink(fileName);

    // QrPainter: render QR ke Canvas Flutter
    final painter = QrPainter(
      data: url,
      version: QrVersions.auto,
      eyeStyle: QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: foregroundColor,
      ),
      dataModuleStyle: QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: foregroundColor,
      ),
      // background digambar manual di canvas di bawah — tidak perlu emptyColor
    );

    // Render ke gambar PNG
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size),
      Paint()..color = backgroundColor,
    );

    painter.paint(canvas, Size(size, size));

    final image = await recorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}

// ─────────────────────────────────────────────────────────────
// CONTOH WIDGET: QR dialog pop-up
//
// Panggil dari mana saja:
//   QrDownloadDialog.show(context, fileName: "photo_123.png");
// ─────────────────────────────────────────────────────────────
class QrDownloadDialog extends StatelessWidget {
  final String fileName;
  const QrDownloadDialog({super.key, required this.fileName});

  static void show(BuildContext context, {required String fileName}) {
    showDialog(
      context: context,
      builder: (_) => QrDownloadDialog(fileName: fileName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Download Foto",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            QrService.buildQrWidget(fileName, size: 220),
            const SizedBox(height: 16),
            Text(
              QrService.generateDownloadLink(fileName),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Tutup"),
            ),
          ],
        ),
      ),
    );
  }
}