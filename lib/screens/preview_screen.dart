import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import '../model/template_model.dart';
import '../services/image_service.dart';

/// ================= FILTER MATRIX =================
const List<double> normalMatrix  = [1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0];
const List<double> bwMatrix      = [0.21,0.72,0.07,0,0, 0.21,0.72,0.07,0,0, 0.21,0.72,0.07,0,0, 0,0,0,1,0];
const List<double> sepiaMatrix   = [0.39,0.76,0.18,0,0, 0.35,0.68,0.16,0,0, 0.27,0.53,0.13,0,0, 0,0,0,1,0];
const List<double> coolMatrix    = [1,0,0,0,0, 0,1,0,0,0, 0,0,1.2,0,0, 0,0,0,1,0];
const List<double> warmMatrix    = [1.2,0,0,0,0, 0,1,0,0,0, 0,0,0.9,0,0, 0,0,0,1,0];
const List<double> vintageMatrix = [0.9,0.5,0.1,0,0, 0.3,0.8,0.1,0,0, 0.2,0.3,0.7,0,0, 0,0,0,1,0];

class PreviewScreen extends StatefulWidget {
  final List<XFile> images;
  final FrameTemplate template;

  // ✅ Terima holes & frameImage dari CameraScreen — tidak perlu deteksi ulang
  final List<Rect>? preloadedHoles;
  final ui.Image? frameImage;

  const PreviewScreen({
    super.key,
    required this.images,
    required this.template,
    this.preloadedHoles,
    this.frameImage,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final GlobalKey _renderKey = GlobalKey();
  String currentFilter = 'None';

  // ✅ Sticker disimpan sebagai data, bukan Widget — lebih ringan
  final List<_StickerData> _stickerDataList = [];

  bool _isProcessing = false;

  ui.Image? frameImage;
  List<Rect> holes = [];

  final List<Map<String, dynamic>> filters = [
    {'name': 'None',    'matrix': normalMatrix},
    {'name': 'B&W',     'matrix': bwMatrix},
    {'name': 'Sepia',   'matrix': sepiaMatrix},
    {'name': 'Cool',    'matrix': coolMatrix},
    {'name': 'Warm',    'matrix': warmMatrix},
    {'name': 'Vintage', 'matrix': vintageMatrix},
  ];

  final List<String> stickers = [
    '😀','😂','😍','🥰','😎','🔥','❤️','💛',
    '🌈','⭐','✨','🎉','💫','🌸','🌟','🍀',
  ];

  @override
  void initState() {
    super.initState();

    // ✅ Gunakan data yang sudah diload — skip detectFrameHoles kalau sudah ada
    if (widget.preloadedHoles != null && widget.frameImage != null) {
      holes = widget.preloadedHoles!;
      frameImage = widget.frameImage;
    } else {
      _loadFrame();
    }
  }

  Future<void> _loadFrame() async {
    Uint8List bytes;
    if (widget.template.type == 'asset') {
      final data = await rootBundle.load(widget.template.path);
      bytes = data.buffer.asUint8List();
    } else {
      bytes = await File(widget.template.path).readAsBytes();
    }
    final codec = await ui.instantiateImageCodec(bytes);
    final imgObj = (await codec.getNextFrame()).image;
    final detected = await detectFrameHoles(imgObj);
    if (mounted) {
      setState(() {
        frameImage = imgObj;
        holes = detected;
      });
    }
  }

  /// ================= DOWNLOAD HD =================
  Future<void> _downloadFullImage() async {
    setState(() => _isProcessing = true);
    try {
      await Future.delayed(const Duration(milliseconds: 100));

      RenderRepaintBoundary? boundary =
          _renderKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception("Boundary null");

      if (boundary.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 100));
        return _downloadFullImage();
      }

      final uiImage = await boundary.toImage(pixelRatio: 4.0);
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception("ByteData null");

      final pngBytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(pngBytes);
      await Gal.putImage(path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gambar HD berhasil disimpan!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal download: $e")),
        );
      }
    }
    setState(() => _isProcessing = false);
  }

  /// ================= GIF — dari raw bytes, bukan render boundary =================
  /// ✅ Jauh lebih cepat di web: tidak perlu capture UI frame berulang kali
  Future<void> _downloadAsGif() async {
    setState(() => _isProcessing = true);
    try {
      final encoder = img.GifEncoder();

      for (final file in widget.images) {
        final bytes = kIsWeb
            ? await file.readAsBytes()
            : await File(file.path).readAsBytes();

        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;

        // Resize ke ukuran wajar agar GIF tidak terlalu besar
        final resized = img.copyResize(decoded, width: 600);
        encoder.addFrame(resized, duration: 400);
      }

      final gifBytes = encoder.finish();
      if (gifBytes == null) throw Exception("GIF gagal");

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/gif_${DateTime.now().millisecondsSinceEpoch}.gif';
      await File(path).writeAsBytes(gifBytes);
      await Gal.putImage(path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("GIF berhasil disimpan!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal GIF: $e")),
        );
      }
    }
    setState(() => _isProcessing = false);
  }

  List<Rect> _scaleHoles(List<Rect> holes, double frameW, double frameH, double w, double h) {
    final sx = w / frameW;
    final sy = h / frameH;
    return holes.map((r) => Rect.fromLTWH(
      r.left * sx, r.top * sy, r.width * sx, r.height * sy,
    )).toList();
  }

  Widget _buildImage(XFile file) {
    return kIsWeb
        ? Image.network(file.path, fit: BoxFit.cover)
        : Image.file(File(file.path), fit: BoxFit.cover);
  }

  // ✅ Tambah sticker sebagai data, bukan Widget langsung
  void _addSticker(String emoji) {
    setState(() {
      _stickerDataList.add(_StickerData(emoji: emoji));
    });
  }

  @override
  Widget build(BuildContext context) {
    final matrix = (filters.firstWhere((f) => f['name'] == currentFilter)['matrix'] as List<double>);
    final previewImage = widget.images.isNotEmpty ? widget.images.first : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Photo"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            IconButton(icon: const Icon(Icons.download), onPressed: _downloadFullImage),
            IconButton(icon: const Icon(Icons.gif_box), onPressed: _downloadAsGif),
          ]
        ],
      ),

      body: Row(
        children: [

          /// ================= PREVIEW =================
          Expanded(
            flex: 3,
            child: Center(
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: frameImage == null
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(
                        builder: (context, c) {
                          final scaled = _scaleHoles(
                            holes,
                            frameImage!.width.toDouble(),
                            frameImage!.height.toDouble(),
                            c.maxWidth,
                            c.maxHeight,
                          );

                          return Stack(
                            children: [
                              // ✅ RepaintBoundary hanya membungkus lapisan foto + frame
                              // Sticker di luar boundary agar drag tidak trigger repaint foto
                              RepaintBoundary(
                                key: _renderKey,
                                child: Stack(
                                  children: [
                                    ...List.generate(scaled.length, (i) {
                                      if (i >= widget.images.length) return const SizedBox();
                                      final r = scaled[i];
                                      return Positioned(
                                        left: r.left,
                                        top: r.top,
                                        width: r.width,
                                        height: r.height,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: ColorFiltered(
                                            colorFilter: ColorFilter.matrix(matrix),
                                            child: _buildImage(widget.images[i]),
                                          ),
                                        ),
                                      );
                                    }),

                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: widget.template.type == 'asset'
                                            ? Image.asset(widget.template.path, fit: BoxFit.fill)
                                            : Image.file(File(widget.template.path), fit: BoxFit.fill),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // ✅ Sticker layer di luar RepaintBoundary
                              // Drag sticker tidak rebuild foto sama sekali
                              ..._stickerDataList.map((data) => _DraggableSticker(data: data)),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ),

          /// ================= PANEL =================
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[50],
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Filter", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 3,
                    children: filters.map((f) {
                      return GestureDetector(
                        onTap: () => setState(() => currentFilter = f['name']),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ColorFiltered(
                                  colorFilter: ColorFilter.matrix(f['matrix']),
                                  child: previewImage == null
                                      ? Container(color: Colors.grey)
                                      : _buildImage(previewImage),
                                ),
                              ),
                              Positioned.fill(
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    // ✅ const color — tidak buat object baru tiap build
                                    color: const Color(0x40000000),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    f['name'],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 20),
                  const Text("Stiker", style: TextStyle(fontWeight: FontWeight.bold)),

                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 4,
                      children: stickers.map((e) {
                        return GestureDetector(
                          onTap: () => _addSticker(e),
                          child: Center(
                            child: Text(e, style: const TextStyle(fontSize: 25)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= STICKER DATA MODEL =================
class _StickerData {
  final String emoji;
  // ✅ ValueNotifier: update posisi tanpa setState di parent
  final ValueNotifier<Offset> position;

  _StickerData({required this.emoji})
      : position = ValueNotifier(const Offset(100, 100));
}

// ================= DRAGGABLE STICKER =================
// ✅ Pakai ValueListenableBuilder — hanya widget sticker yang rebuild saat drag
class _DraggableSticker extends StatelessWidget {
  final _StickerData data;
  const _DraggableSticker({required this.data});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset>(
      valueListenable: data.position,
      builder: (_, pos, __) {
        return Positioned(
          left: pos.dx,
          top: pos.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              data.position.value = data.position.value + details.delta;
            },
            child: Text(data.emoji, style: const TextStyle(fontSize: 40)),
          ),
        );
      },
    );
  }
}