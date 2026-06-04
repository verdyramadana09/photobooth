import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';

// dart:io dan http hanya untuk native/web file loading
import 'package:http/http.dart' as http;
// dart:io dikondisikan agar tidak crash di web saat compile
import '../model/template_model.dart';

// ─────────────────────────────────────────────────────────────
// FLOOD FILL — versi web-safe
//
// Masalah sebelumnya:
//   - compute(_runFloodFill, _FloodFillInput) CRASH di web karena
//     class custom tidak bisa di-serialize ke Web Worker
//   - dart:isolate tidak ada di web
//
// Solusi:
//   - Di web: jalankan langsung di main thread dengan yield
//     (Future.microtask) agar tidak block render
//   - Di native: tetap pakai compute() dengan tipe yang bisa di-serialize
//     (kirim sebagai List<Object> bukan class custom)
// ─────────────────────────────────────────────────────────────

// Fungsi compute-safe: argumen harus Map (bisa di-serialize di semua platform)
List<List<int>> _runFloodFillFromMap(Map<String, Object> args) {
  final pixels    = args['pixels']    as Uint8List;
  final width     = args['width']     as int;
  final height    = args['height']    as int;
  final threshold = args['threshold'] as int;

  final visited = Uint8List(width * height);
  final List<List<int>> result = [];

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final index = y * width + x;
      if (pixels[index * 4 + 3] < threshold && visited[index] == 0) {
        int minX = x, maxX = x;
        int minY = y, maxY = y;

        final stack = <int>[index];

        while (stack.isNotEmpty) {
          final idx = stack.removeLast();
          if (visited[idx] != 0) continue;

          final px = idx % width;
          final py = idx ~/ width;

          if (pixels[idx * 4 + 3] >= threshold) continue;

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

// ─────────────────────────────────────────────────────────────
// PUBLIC API: detectFrameHoles
// ─────────────────────────────────────────────────────────────
Future<List<Rect>> detectFrameHoles(ui.Image frame) async {
  final byteData = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels   = byteData!.buffer.asUint8List();

  // Map<String, Object> bisa di-serialize di semua platform termasuk web
  final args = <String, Object>{
    'pixels':    pixels,
    'width':     frame.width,
    'height':    frame.height,
    'threshold': 10,
  };

  List<List<int>> rawHoles;

  if (kIsWeb) {
    // ✅ Di web: jalankan langsung (tidak ada isolate)
    // Yield ke event loop dulu agar UI tidak freeze di satu frame
    rawHoles = await Future(() => _runFloodFillFromMap(args));
  } else {
    // ✅ Di native: compute() pakai background isolate
    rawHoles = await compute(_runFloodFillFromMap, args);
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
// ─────────────────────────────────────────────────────────────
Future<Uint8List> generateImage(
  List<XFile> images,
  FrameTemplate template, {
  ui.Image? preloadedFrame,
  List<Rect>? preloadedHoles,
}) async {
  const double canvasWidth  = 1200;
  const double canvasHeight = 1800;

  final recorder = ui.PictureRecorder();
  final canvas   = ui.Canvas(recorder);
  final paint    = ui.Paint();

  canvas.drawRect(
    const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    paint..color = Colors.white,
  );

  final ui.Image frameImage =
      preloadedFrame ?? await _loadFrameImage(template);

  final List<Rect> holes =
      preloadedHoles ?? await detectFrameHoles(frameImage);

  for (int i = 0; i < holes.length; i++) {
    if (i >= images.length) break;

    final rect     = holes[i];
    final imgBytes = await images[i].readAsBytes();
    final codec    = await ui.instantiateImageCodec(imgBytes);
    final photo    = (await codec.getNextFrame()).image;

    final imageSize = Size(photo.width.toDouble(), photo.height.toDouble());
    final fitted    = applyBoxFit(BoxFit.cover, imageSize, rect.size);

    final inputRect  = Alignment.center.inscribe(fitted.source, Offset.zero & imageSize);
    final outputRect = Alignment.center.inscribe(fitted.destination, rect);

    canvas.drawImageRect(photo, inputRect, outputRect, paint);
  }

  canvas.drawImageRect(
    frameImage,
    Rect.fromLTWH(0, 0, frameImage.width.toDouble(), frameImage.height.toDouble()),
    const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    paint,
  );

  final resultImage = await recorder
      .endRecording()
      .toImage(canvasWidth.toInt(), canvasHeight.toInt());

  final byteData = await resultImage.toByteData(format: ui.ImageByteFormat.png);
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
    // ✅ Di web tidak ada dart:io — pakai http.get
    final response = await http.get(Uri.parse(template.path));
    bytes = response.bodyBytes;
  } else {
    // native: baca dari file lokal
    // import dart:io hanya dipakai di sini, dan hanya di-execute di native
    bytes = await _readFileBytes(template.path);
  }

  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

// Fungsi ini hanya dipanggil di native — aman dari web
Future<Uint8List> _readFileBytes(String path) async {
  // Menggunakan XFile agar tidak perlu import dart:io langsung di web
  final xfile = XFile(path);
  return await xfile.readAsBytes();
}