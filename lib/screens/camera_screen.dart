import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';

import '../model/template_model.dart';
import '../services/camera_service.dart';
import '../services/image_service.dart';
import 'preview_screen.dart';

class CameraScreen extends StatefulWidget {
  final FrameTemplate template;
  // ✅ Terima cameras via constructor — tidak pakai global var lagi
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.template, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  int countdown = 0;
  bool isFlashing = false;

  /// REVIEW MODE
  bool isReviewMode = false;
  int reviewSeconds = 30;
  Timer? reviewTimer;

  ui.Image? frameImage;
  List<Rect> holes = [];       // ✅ simpan holes di sini, diteruskan ke PreviewScreen
  List<List<Rect>> columns = [];

  List<XFile?> capturedImages = [];

  // ✅ Guard agar tombol tidak bisa ditekan ganda
  bool _isTaking = false;

  @override
  void initState() {
    super.initState();
    _loadFrame();

    CameraService.init(widget.cameras).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    reviewTimer?.cancel();
    super.dispose();
  }

  /// ================= LOAD FRAME =================
  Future<void> _loadFrame() async {
    Uint8List bytes;

    if (widget.template.type == 'asset') {
      final data = await rootBundle.load(widget.template.path);
      bytes = data.buffer.asUint8List();
    } else {
      bytes = await File(widget.template.path).readAsBytes();
    }

    final codec = await ui.instantiateImageCodec(bytes);
    final img = (await codec.getNextFrame()).image;

    // ✅ detectFrameHoles hanya dipanggil SEKALI di sini
    final detected = await detectFrameHoles(img);
    final grouped = _groupColumns(detected);

    setState(() {
      frameImage = img;
      holes = detected;
      columns = grouped;
      capturedImages = List.filled(detected.length, null);
    });
  }

  /// ================= GROUP =================
  List<List<Rect>> _groupColumns(List<Rect> holes) {
    List<List<Rect>> cols = [];

    for (var h in holes) {
      bool placed = false;

      for (var c in cols) {
        if ((c.first.left - h.left).abs() < 80) {
          c.add(h);
          placed = true;
          break;
        }
      }

      if (!placed) cols.add([h]);
    }

    for (var c in cols) {
      c.sort((a, b) => a.top.compareTo(b.top));
    }

    cols.sort((a, b) => a.first.left.compareTo(b.first.left));

    return cols;
  }

  /// ================= TAKE PHOTO =================
  Future<void> _takePhoto(int index) async {
    for (int i = 3; i > 0; i--) {
      setState(() => countdown = i);
      await Future.delayed(const Duration(milliseconds: 500));
    }

    setState(() => countdown = 0);

    setState(() => isFlashing = true);
    await Future.delayed(const Duration(milliseconds: 120));
    setState(() => isFlashing = false);

    final img = await CameraService.controller!.takePicture();

    setState(() {
      capturedImages[index] = img;
    });
  }

  // ✅ Guard double-tap: _isTaking mencegah _takeAll dipanggil dua kali
  Future<void> _takeAll() async {
    if (_isTaking) return;
    setState(() => _isTaking = true);

    for (int i = 0; i < capturedImages.length; i++) {
      await _takePhoto(i);
    }

    _startReviewTimer();
    setState(() => _isTaking = false);
  }

  /// ================= TIMER =================
  void _startReviewTimer() {
    setState(() {
      isReviewMode = true;
      reviewSeconds = 30;
    });

    reviewTimer?.cancel();

    reviewTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (reviewSeconds > 0) {
        setState(() => reviewSeconds--);
      } else {
        _next();
      }
    });
  }

  /// ================= RETAKE =================
  void _retake(int index) async {
    if (!isReviewMode) return;
    if (_isTaking) return;   // ✅ juga guard saat retake

    setState(() => _isTaking = true);
    await _takePhoto(index);
    setState(() => _isTaking = false);
  }

  void _next() {
    reviewTimer?.cancel();

    final imgs = capturedImages.whereType<XFile>().toList();

    if (imgs.length == capturedImages.length) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            images: imgs,
            template: widget.template,
            // ✅ Teruskan holes yang sudah dideteksi — tidak perlu deteksi ulang
            preloadedHoles: holes,
            frameImage: frameImage,
          ),
        ),
      );
    }
  }

  Widget _img(XFile? file) {
    if (file == null) {
      return const Icon(Icons.camera_alt, color: Colors.black, size: 28);
    }

    return kIsWeb
        ? Image.network(file.path, fit: BoxFit.cover)
        : Image.file(File(file.path), fit: BoxFit.cover);
  }

  @override
  Widget build(BuildContext context) {
    final controller = CameraService.controller;

    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xffeeeeee),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [

              /// HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Photobooth",
                      style: TextStyle(fontWeight: FontWeight.bold)),

                  if (isReviewMode)
                    Text("$reviewSeconds s",
                        style: const TextStyle(color: Colors.red)),
                ],
              ),

              const SizedBox(height: 16),

              Expanded(
                child: Row(
                  children: [

                    /// CAMERA
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [

                                  /// MIRROR
                                  Transform(
                                    alignment: Alignment.center,
                                    transform:
                                        Matrix4.rotationY(3.1416),
                                    child: CameraPreview(controller),
                                  ),

                                  if (countdown > 0)
                                    Center(
                                      child: Text("$countdown",
                                          style: const TextStyle(
                                              fontSize: 80,
                                              color: Colors.white)),
                                    ),

                                  if (isFlashing)
                                    Container(
                                        color: Colors.white.withValues(alpha: 0.8)),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ✅ Tombol disabled saat sedang mengambil foto
                          ElevatedButton(
                            onPressed: _isTaking ? null : _takeAll,
                            child: _isTaking
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text("ambil gambar"),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 16),

                    /// PREVIEW
                    Expanded(
                      flex: 2,
                      child: frameImage == null
                          ? const Center(child: CircularProgressIndicator())
                          : LayoutBuilder(
                              builder: (context, c) {

                                int index = 0;

                                return Row(
                                  children: columns.map((col) {
                                    return Expanded(
                                      child: Column(
                                        children: col.map((_) {

                                          final i = index++;

                                          return Expanded(
                                            child: GestureDetector(
                                              onTap: () => _retake(i),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(6),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  child: _img(
                                                      capturedImages[i]),
                                                ),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _next,
                  child: const Text("lanjutkan"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}