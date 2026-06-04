import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

import '../model/template_model.dart';
import '../services/image_service.dart';

class ResultScreen extends StatefulWidget {
  final List<XFile> images;
  final FrameTemplate template;
  final List<double> filterMatrix;
  final List<Widget> stickers;

  const ResultScreen({
    super.key,
    required this.images,
    required this.template,
    required this.filterMatrix,
    required this.stickers,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  Uint8List? _finalBytes;

  @override
  void initState() {
    super.initState();
    _generateFinal();
  }

  /// ================= GENERATE FINAL =================
  Future<void> _generateFinal() async {
    final bytes = await generateImage(widget.images, widget.template);
    if (mounted) {
      setState(() => _finalBytes = bytes);
    }
  }

  /// ================= DOWNLOAD =================
  Future<void> _download() async {
    if (_finalBytes == null) return;
    await Gal.putImageBytes(_finalBytes!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Downloaded")),
      );
    }
  }

  /// ================= GIF =================
  Future<void> _downloadGif() async {
    final encoder = img.GifEncoder();

    for (var file in widget.images) {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) continue;
      encoder.addFrame(img.copyResize(decoded, width: 480), duration: 50);
    }

    final gifBytes = encoder.finish();
    if (gifBytes == null) return;

    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/gif_${DateTime.now().millisecondsSinceEpoch}.gif';
    await File(path).writeAsBytes(gifBytes);
    await Gal.putImage(path);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("GIF Downloaded")),
      );
    }
  }

  /// ================= PRINT =================
  void _print() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Print (coming soon)")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffeeeeee),
      body: SafeArea(
        child: Column(
          children: [

            /// HEADER
            const Padding(
              padding: EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Photobooth",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),

            /// RESULT IMAGE
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: _finalBytes == null
                      ? const Center(child: CircularProgressIndicator())
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.memory(
                            _finalBytes!,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
              ),
            ),

            /// BUTTONS
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _btn("Print", _print),
                  const SizedBox(width: 16),
                  _btn("Download Gif", _downloadGif),
                  const SizedBox(width: 16),
                  _btn("Download", _download),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(String text, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      onPressed: onTap,
      child: Text(text),
    );
  }
}