import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../model/template_model.dart';
import 'frame_screen.dart';

class StartScreen extends StatefulWidget {
  // ✅ Tidak perlu cameras — kamera di-request saat masuk CameraScreen
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  List<FrameTemplate> customTemplates = [];

  Future<String?> _askForLayout(BuildContext context) async {
    return showModalBottomSheet<String>(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _layoutItem("Strip 4 Foto", "strip_1x4"),
              _layoutItem("Strip 3 Foto", "strip_1x3"),
              _layoutItem("Grid 2x2",     "grid_2x2"),
              _layoutItem("Grid 3x2",     "grid_3x2"),
            ],
          ),
        );
      },
    );
  }

  Widget _layoutItem(String title, String value) {
    return ListTile(
      title: Text(title),
      onTap: () => Navigator.pop(context, value),
    );
  }

  Future<void> _pickTemplate() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final selectedLayout = await _askForLayout(context);
    if (selectedLayout == null) return;

    int    photos = 4;
    double hPad   = 20.0;
    double vPad   = 40.0;
    double ratio  = 1.0;

    if (selectedLayout == 'strip_1x3') {
      photos = 3; hPad = 65.0; ratio = 1.3;
    } else if (selectedLayout == 'grid_3x2') {
      photos = 6; hPad = 12.0; vPad = 45.0; ratio = 0.82;
    } else if (selectedLayout == 'strip_1x4') {
      photos = 4; hPad = 65.0;
    }

    setState(() {
      customTemplates.add(FrameTemplate(
        path: file.path,
        type: 'file',
        layout: selectedLayout,
        requiredPhotos: photos,
        horizontalPadding: hPad,
        verticalPadding: vPad,
        aspectRatio: ratio,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              const Text(
                "Photobooth",
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              const Text(
                "Capture your moments beautifully",
                style: TextStyle(color: Colors.grey),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FrameScreen(
                          userTemplates: customTemplates,
                        ),
                      ),
                    );
                  },
                  child: const Text("Start Session"),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickTemplate,
                  icon: const Icon(Icons.upload),
                  label: const Text("Upload Template"),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}