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
  // ✅ Tidak perlu cameras dari luar — request sendiri saat layar dibuka
  const CameraScreen({super.key, required this.template});

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

  // Guard agar tombol tidak bisa ditekan ganda
  bool _isTaking = false;

  // Toggle flip/mirror preview kamera
  bool _isMirrored = true;

  // Simpan pesan error kamera — null berarti tidak ada error
  String? _cameraError;

@override
  void initState() {
    super.initState();
    // Panggil fungsi berurutan, bukan bersamaan
    _setupSequentially();
  }

  Future<void> _setupSequentially() async {
    // 1. Nyalakan kamera terlebih dahulu sampai selesai
    await _initCamera();
    
    // 2. Beri nafas pada browser sebentar untuk me-render UI kamera
    await Future.delayed(const Duration(milliseconds: 500));

    // 3. Setelah kamera aman, baru jalankan komputasi frame yang berat
    await _loadFrame();
  }

  Future<void> _initCamera() async {
    try {
      // ✅ Request availableCameras() di sini — bukan di main()
      // Ini memastikan browser hanya minta izin saat user memang
      // masuk ke halaman kamera, bukan saat app pertama dibuka.
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('Tidak ada kamera yang ditemukan di perangkat ini.');
      }
      await CameraService.init(cameras);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError = _friendlyError(e.toString()));
      }
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('cameraNotReadable') || raw.contains('hardware')) {
      return 'Kamera tidak bisa diakses.\n\nKemungkinan kamera sedang dipakai aplikasi lain (Zoom, Teams, dll).\n\nTutup aplikasi tersebut lalu refresh halaman ini.';
    }
    if (raw.contains('Permission') || raw.contains('denied') || raw.contains('NotAllowed')) {
      return 'Izin kamera ditolak.\n\nKlik ikon kunci di address bar browser dan izinkan kamera, lalu refresh halaman.';
    }
    if (raw.contains('NotFound') || raw.contains('DevicesNotFound')) {
      return 'Kamera tidak ditemukan.\n\nPastikan perangkat memiliki kamera yang terhubung.';
    }
    return 'Kamera tidak tersedia. Refresh halaman dan izinkan akses kamera.\n\nDetail: $raw';
  }

@override
  void dispose() {
    reviewTimer?.cancel();
    // Gunakan fungsi dispose() bawaan dari CameraService agar nilainya di-set ke null
    CameraService.dispose(); 
    super.dispose();
  }
  /// ================= LOAD FRAME =================
Future<void> _loadFrame() async {
    Uint8List bytes;

    if (widget.template.type == 'asset') {
      final data = await rootBundle.load(widget.template.path);
      bytes = data.buffer.asUint8List();
    } else {
      // ✅ Gunakan XFile agar aman di web (tidak crash seperti dart:io)
      final xfile = XFile(widget.template.path);
      bytes = await xfile.readAsBytes();
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

    // Tampilkan error yang jelas jika kamera gagal
    if (_cameraError != null) {
      return Scaffold(
        backgroundColor: const Color(0xffeeeeee),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_off_rounded, size: 64, color: Colors.black38),
                const SizedBox(height: 24),
                Text(
                  _cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba Lagi'),
                  onPressed: () {
                    setState(() => _cameraError = null);
                    _initCamera();
                  },
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kembali'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Masih loading (belum init, belum error)
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

                  Row(
                    children: [
                      if (isReviewMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text("$reviewSeconds s",
                              style: const TextStyle(color: Colors.red)),
                        ),

                      // Tombol toggle flip/mirror
                      GestureDetector(
                        onTap: () => setState(() => _isMirrored = !_isMirrored),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isMirrored ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.black26),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.flip,
                                size: 16,
                                color: _isMirrored ? Colors.white : Colors.black,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isMirrored ? "Mirror ON" : "Mirror OFF",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _isMirrored ? Colors.white : Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
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

                                  /// MIRROR — bisa di-toggle
                                  Transform(
                                    alignment: Alignment.center,
                                    transform: _isMirrored
                                        ? Matrix4.rotationY(3.1416)
                                        : Matrix4.identity(),
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
