import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../model/template_model.dart';
import 'camera_screen.dart';

class FrameScreen extends StatefulWidget {
  final List<FrameTemplate> userTemplates;
  // ✅ Tidak perlu cameras — CameraScreen request sendiri saat dibuka
  const FrameScreen({super.key, required this.userTemplates});

  @override
  State<FrameScreen> createState() => _FrameScreenState();
}

class _FrameScreenState extends State<FrameScreen> {
  String selectedFilter = 'all';
  FrameTemplate? selectedFrame;

  double getAspectRatio(String layout) {
    switch (layout) {
      case "grid_2x2":   return 1;
      case "grid_3x2":   return 2 / 3;
      case "strip_1x3":  return 1 / 3;
      default:           return 0.6;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<FrameTemplate> allFrames = [
      FrameTemplate(
        path: "assets/frames/frame 1.png",
        type: "asset",
        layout: "grid_3x2",
        requiredPhotos: 6,
      ),
      FrameTemplate(
        path: "assets/frames/default_3x2.png",
        type: "asset",
        layout: "grid_3x2",
        requiredPhotos: 6,
      ),
      ...widget.userTemplates,
    ];

    final filteredFrames = selectedFilter == 'all'
        ? allFrames
        : allFrames.where((f) => f.layout == selectedFilter).toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Choose Frame"),
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Text(
              "Filter Layout",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),

          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _filterChip("All",  "all"),
                _filterChip("1x3",  "strip_1x3"),
                _filterChip("2x2",  "grid_2x2"),
                _filterChip("3x2",  "grid_3x2"),
              ],
            ),
          ),

          const SizedBox(height: 10),

          Expanded(
            child: filteredFrames.isEmpty
                ? const Center(child: Text("No frames available"))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredFrames.length,
                    itemBuilder: (context, index) {
                      final frame = filteredFrames[index];
                      final isSelected = selectedFrame?.path == frame.path;
                      final borderRadius = frame.layout.contains("2x2") ? 12.0 : 20.0;

                      return GestureDetector(
                        onTap: () => setState(() => selectedFrame = frame),
                        child: AspectRatio(
                          aspectRatio: getAspectRatio(frame.layout),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            margin: const EdgeInsets.only(right: 16, top: 10, bottom: 20),
                            transform: isSelected
                                ? (Matrix4.diagonal3Values(1.08, 1.08, 1.0))
                                : Matrix4.identity(),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(borderRadius),
                              boxShadow: [
                                BoxShadow(
                                  // ✅ const Color — tidak buat object baru tiap build
                                  color: isSelected
                                      ? const Color(0x33000000)
                                      : const Color(0x14000000),
                                  blurRadius: isSelected ? 25 : 10,
                                  offset: const Offset(0, 6),
                                )
                              ],
                              border: isSelected
                                  ? Border.all(color: Colors.black, width: 2)
                                  : Border.all(color: Colors.transparent),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(borderRadius),
                              child: Stack(
                                children: [
                                  Positioned.fill(child: _buildFrameImage(frame)),

                                  Positioned(
                                    bottom: 8,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        frame.layout,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ),

                                  if (isSelected)
                                    Positioned.fill(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(borderRadius),
                                        child: Stack(
                                          children: [
                                            Container(color: Colors.black),
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: Container(
                                                width: 34,
                                                height: 34,
                                                decoration: BoxDecoration(
                                                  color: Colors.black,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                      color: Colors.white, width: 3),
                                                  boxShadow: const [
                                                    // ✅ const boxShadow
                                                    BoxShadow(
                                                      color: Colors.white,
                                                      blurRadius: 6,
                                                    )
                                                  ],
                                                ),
                                                alignment: Alignment.center,
                                                child: const Icon(
                                                  Icons.check,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 0,
                ),
                onPressed: selectedFrame == null
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CameraScreen(template: selectedFrame!),
                          ),
                        );
                      },
                child: const Text(
                  "Continue to Camera",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = selectedFilter == value;

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () => setState(() => selectedFilter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: isSelected ? Colors.black : Colors.black12,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFrameImage(FrameTemplate frame) {
    if (frame.type == "asset") {
      return Image.asset(
        frame.path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image)),
      );
    } else {
      return kIsWeb
          ? Image.network(
              frame.path,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.cloud_off),
            )
          : Image.file(
              File(frame.path),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.file_present),
            );
    }
  }
}