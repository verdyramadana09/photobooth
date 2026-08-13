import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraService {
  static CameraController? controller;

  // ✅ Guard: jangan init ulang jika sudah berjalan
  static bool get isReady =>
      controller != null && controller!.value.isInitialized;

  static Future<void> init(List<CameraDescription> cameras) async {
    if (cameras.isEmpty) return;

    // Kalau sudah ada controller aktif, dispose dulu dengan aman
    if (controller != null) {
      await dispose();
    }

    final CameraDescription selected = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    // ✅ Web tidak support ResolutionPreset.high dengan baik
    // Pakai medium di web agar tidak freeze saat inisialisasi
    final resolution =
        kIsWeb ? ResolutionPreset.medium : ResolutionPreset.high;

controller = CameraController(
      selected,
      resolution,
      enableAudio: false,
      // HAPUS baris imageFormatGroup di bawah ini:
      // imageFormatGroup: ImageFormatGroup.jpeg, 
    );

    try {
      await controller!.initialize();
    } catch (e) {
      // ✅ Jika gagal (misalnya permission ditolak atau kamera tidak tersedia)
      // buang controller agar tidak dipakai dalam keadaan rusak
      controller?.dispose();
      controller = null;
      rethrow; // biarkan caller handle error ini
    }
  }

  // ✅ Dispose yang aman: tidak crash jika controller null
  static Future<void> dispose() async {
    final c = controller;
    controller = null;
    await c?.dispose();
  }
}
