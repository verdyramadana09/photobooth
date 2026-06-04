import 'dart:ui' as ui;
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../model/template_model.dart';

// ─────────────────────────────────────────────────────────────
// DATA CLASS — dikirim ke isolate (harus bisa di-serialize)
// ─────────────────────────────────────────────────────────────
class _FloodFillInput {
  final Uint8List pixels;
  final int width;
  final int height;
  final int threshold;
  _FloodFillInput(this.pixels, this.width, this.height, this.threshold);
}

// ─────────────────────────────────────────────────────────────
// FUNGSI FLOOD FILL MURNI (sync, tidak import Flutter)
// Dijalankan di isolate (native) atau main thread (web fallback)
// ─────────────────────────────────────────────────────────────
List<List<int>> _runFloodFill(_FloodFillInput input) {
  final data      = input.pixels;
  final width     = input.width;
  final height    = input.height;
  final threshold = input.threshold;

  // ✅ Uint8List flat jauh lebih hemat memori daripada List<List<bool>>
  // List<List<bool>> → height × width objects
  // Uint8List(width × height) → satu alokasi contigus
  final visited = Uint8List(width * height);

  final List<List<int>> result = []; // [minX, minY, maxX, maxY]

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final index = y * width + x;
      if (data[(index) * 4 + 3] < threshold && visited[index] == 0) {
        int minX = x, maxX = x;
        int minY = y, maxY = y;

        // ✅ Stack iteratif (List<int> encoding x + y*width)
        // Menghindari stack overflow untuk frame besar
        final stack = <int>[index];

        while (stack.isNotEmpty) {
          final idx = stack.removeLast();
          if (visited[idx] != 0) continue;

          final px = idx % width;
          final py = idx ~/ width;

          if (data[idx * 4 + 3] >= threshold) continue;

          visited[idx] = 1;

          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;

          if (px + 1 < width)  stack.add(idx + 1);
          if (px - 1 >= 0)     stack.add(idx - 1);
          if (py + 1 < height) stack.add(idx + width);
          if (py - 1 >= 0)     stack.add(idx - width);
        }

        if ((maxX - minX) > 80 && (maxY - minY) > 80) {
          result.add([minX, minY, maxX, maxY]);
        }
      }
    }
  }

  return result;
}

// entry point isolate
void _isolateEntry(List<Object> args) {
  final SendPort sendPort = args[0] as SendPort;
  final input = args[1] as _FloodFillInput;
  sendPort.send(_runFloodFill(input));
}

// ─────────────────────────────────────────────────────────────
// PUBLIC API: detectFrameHoles
// ─────────────────────────────────────────────────────────────
/// Di native (Android/iOS/Desktop): flood fill dijalankan di isolate
/// terpisah sehingga UI tetap smooth.
/// Di web: isolate tidak tersedia, fallback ke compute() yang
/// setidaknya memakai microtask agar tidak blocking terlalu lama.
Future<List<Rect>> detectFrameHoles(ui.Image frame) async {
  final byteData =
      await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = byteData!.buffer.asUint8List();

  final input = _FloodFillInput(pixels, frame.width, frame.height, 10);

  List<List<int>> rawHoles;

  if (kIsWeb) {
    // ✅ compute() di web menggunakan Web Worker (Flutter 3.x)
    // Tetap lebih baik daripada langsung di main thread
    rawHoles = await compute(_runFloodFill, input);
  } else {
    // ✅ Isolate penuh di native — tidak block UI sama sekali
    final receivePort = ReceivePort();
    await Isolate.spawn<List<Object>>(
      _isolateEntry,
      [receivePort.sendPort, input],
    );
    rawHoles = await receivePort.first as List<List<int>>;
  }

  final holes = rawHoles
      .map((r) => Rect.fromLTRB(
            r[0].toDouble(),
            r[1].toDouble(),
            r[2].toDouble(),
            r[3].toDouble(),
          ))
      .toList();

  holes.sort((a, b) {
    if ((a.top - b.top).abs() < 20) return a.left.compareTo(b.left);
    return a.top.compareTo(b.top);
  });

  return holes;
}

// ─────────────────────────────────────────────────────────────
// PUBLIC API: generateImage
// Menerima frameImage & holes opsional agar tidak load/detect ulang
// ─────────────────────────────────────────────────────────────
Future<Uint8List> generateImage(
  List<XFile> images,
  FrameTemplate template, {
  ui.Image? preloadedFrame,    // ✅ terima frame yang sudah di-load
  List<Rect>? preloadedHoles,  // ✅ terima holes yang sudah dideteksi
}) async {
  const double canvasWidth  = 1200;
  const double canvasHeight = 1800;

  final recorder = ui.PictureRecorder();
  final canvas   = ui.Canvas(recorder);
  final paint    = ui.Paint();

  // background putih
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    paint..color = Colors.white,
  );

  // ✅ Gunakan frame yang sudah ada, skip load dari disk
  final ui.Image frameImage =
      preloadedFrame ?? await _loadFrameImage(template);

  // ✅ Gunakan holes yang sudah dideteksi, skip detectFrameHoles
  final List<Rect> holes =
      preloadedHoles ?? await detectFrameHoles(frameImage);

  // ─── Gambar foto ke lubang ───
  for (int i = 0; i < holes.length; i++) {
    if (i >= images.length) break;

    final rect = holes[i];

    final Uint8List imgBytes = await images[i].readAsBytes();
    final codec = await ui.instantiateImageCodec(imgBytes);
    final photo = (await codec.getNextFrame()).image;

    final imageSize = Size(photo.width.toDouble(), photo.height.toDouble());
    final fitted    = applyBoxFit(BoxFit.cover, imageSize, rect.size);

    final inputRect  = Alignment.center.inscribe(fitted.source, Offset.zero & imageSize);
    final outputRect = Alignment.center.inscribe(fitted.destination, rect);

    canvas.drawImageRect(photo, inputRect, outputRect, paint);
  }

  // ─── Gambar frame di atas foto ───
  canvas.drawImageRect(
    frameImage,
    Rect.fromLTWH(
      0, 0,
      frameImage.width.toDouble(),
      frameImage.height.toDouble(),
    ),
    const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    paint,
  );

  final resultImage = await recorder
      .endRecording()
      .toImage(canvasWidth.toInt(), canvasHeight.toInt());

  final byteData =
      await resultImage.toByteData(format: ui.ImageByteFormat.png);

  return byteData!.buffer.asUint8List();
}

// ─────────────────────────────────────────────────────────────
// HELPER: load frame dari asset atau file/network
// ─────────────────────────────────────────────────────────────
Future<ui.Image> _loadFrameImage(FrameTemplate template) async {
  Uint8List bytes;

  if (template.type == 'asset') {
    final data = await rootBundle.load(template.path);
    bytes = data.buffer.asUint8List();
  } else if (kIsWeb) {
    final response = await http.get(Uri.parse(template.path));
    bytes = response.bodyBytes;
  } else {
    bytes = await File(template.path).readAsBytes();
  }

  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}