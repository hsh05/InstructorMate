// lib/screens/workspace/generate_encodings_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/api_service.dart';
import 'package:desktop_drop/desktop_drop.dart';

class GenerateEncodingsScreen extends StatefulWidget {
  const GenerateEncodingsScreen({super.key});

  @override
  State<GenerateEncodingsScreen> createState() =>
      _GenerateEncodingsScreenState();
}

class _GenerateEncodingsScreenState extends State<GenerateEncodingsScreen> {
  final ApiService api = ApiService();
  final TextEditingController studentIdCtrl = TextEditingController();

  List<File> selectedImages = [];
  List<dynamic> studentsWithEncodings = [];

  bool loading = false;
  bool isDragging = false;
  // for mobile panel switching
  bool showRightPanel = false;

  @override
  void initState() {
    super.initState();
    loadStudents();
  }

  // =============================
  // Load ONLY students with encodings
  // =============================
  Future<void> loadStudents() async {
    try {
      final data = await api.getEncodingStudents();
      final filtered = data.where((s) => s["has_encoding"] == true).toList();
      setState(() => studentsWithEncodings = filtered);
    } catch (e) {
      print("Error loading students: $e");
    }
  }

  // =============================
  // Pick Images
  // =============================
  Future<void> pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );

    if (result != null) {
      final newFiles = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();

      setState(() {
        selectedImages = [
          ...selectedImages,
          ...newFiles.where(
            (f) => !selectedImages.any((e) => e.path == f.path),
          ),
        ].take(5).toList();
      });
    }
  }

  // =============================
  // Upload + Override
  // =============================
  Future<void> upload({bool override = false}) async {
    if (studentIdCtrl.text.isEmpty || selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter ID and select images")),
      );
      return;
    }
    setState(() => loading = true);

    final res = await api.uploadEncoding(
      studentId: studentIdCtrl.text.trim(),
      images: selectedImages,
      override: override,
    );
    setState(() => loading = false);

    // Override check
    if (res["needs_override"] == true) {
      final confirm = await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Override Encoding"),
          content: const Text(
            "This student already has encoding.\nDo you want to override?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Override"),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await upload(override: true);
      }
      return;
    }

    // Success
    if (res["ok"] == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Encoding saved ✅")));
      setState(() {
        selectedImages = [];
        studentIdCtrl.clear();
      });
      await loadStudents();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res["message"] ?? "Error")));
    }
  }

  // =============================
  // LEFT PANEL
  // =============================
  Widget _buildLeftPanel() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Upload Images",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: studentIdCtrl,
                  decoration: InputDecoration(
                    labelText: "Student ID",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: pickImages,
                  icon: const Icon(Icons.upload_file),
                  label: const Text("Select Images (max 5)"),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.image, size: 16, color: Colors.blue),
                      const SizedBox(width: 6),
                      Text(
                        "Selected: ${selectedImages.length}",
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selectedImages.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        selectedImages.clear();
                      });
                    },
                    child: const Text("Clear All"),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton.icon(
                    onPressed: loading ? null : upload,
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(
                      loading ? "Processing..." : "Generate Encoding",
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(height: 24),
                SizedBox(
                  height: 140,
                  child: DropTarget(
                    onDragDone: (detail) async {
                      final newFiles = detail.files
                          .map((f) => File(f.path))
                          .toList();
                      final combined = [...selectedImages, ...newFiles];

                      if (combined.length > 3) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Maximum 5 images allowed"),
                          ),
                        );
                      }

                      setState(() {
                        selectedImages = combined.take(5).toList();
                      });
                    },
                    onDragEntered: (_) => setState(() => isDragging = true),
                    onDragExited: (_) => setState(() => isDragging = false),
                    child: Container(
                      width: double.infinity,
                      color: isDragging
                          ? Colors.blue.withOpacity(0.05)
                          : Colors.transparent,
                      child: selectedImages.isEmpty
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.cloud_upload,
                                  size: 30,
                                  color: isDragging ? Colors.blue : Colors.grey,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isDragging
                                      ? "Release to upload"
                                      : "Drag & drop images here",
                                  style: TextStyle(
                                    color: isDragging
                                        ? Colors.blue
                                        : Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Rcommended 3-5 images",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            )
                          : Wrap(
                              spacing: 8,
                              children: List.generate(selectedImages.length, (
                                index,
                              ) {
                                final img = selectedImages[index];
                                return Stack(
                                  children: [
                                    Image.file(
                                      img,
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    ),
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            selectedImages.removeAt(index);
                                          });
                                        },
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =============================
  // RIGHT PANEL
  // =============================
  Widget _buildRightPanel() {
    return Expanded(
      child: Container(
        color: Colors.transparent,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    "Live DB",
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "|  Students with Encodings",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: studentsWithEncodings.isEmpty
                  ? const Center(child: Text("No encodings yet"))
                  : ListView.builder(
                      itemCount: studentsWithEncodings.length,
                      itemBuilder: (_, i) {
                        final s = studentsWithEncodings[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color.fromARGB(
                                255,
                                227,
                                236,
                                238,
                              ),
                              child: const Icon(
                                Icons.person,
                                color: Colors.blue,
                              ),
                            ),
                            title: Text(
                              s["name"],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(s["student_id"]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // =============================
  // UI
  // =============================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(
          // On mobile, show which panel the user is on
          isMobile
              ? (showRightPanel
                    ? "Students with Encodings"
                    : "Generate Encodings")
              : "Generate Encodings",
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          if (isMobile)
            TextButton.icon(
              onPressed: () {
                setState(() => showRightPanel = !showRightPanel);
              },
              icon: Icon(
                showRightPanel ? Icons.upload_file : Icons.people,
                color: Colors.blue,
              ),
              label: Text(
                showRightPanel ? "Upload" : "Students",
                style: const TextStyle(color: Colors.blue),
              ),
            ),
        ],
      ),
      body: isMobile
          // MOBILE: show ONE full-width panel at a time
          ? Row(
              children: [
                showRightPanel ? _buildRightPanel() : _buildLeftPanel(),
              ],
            )
          // DESKTOP: show BOTH panels side by side
          : Row(children: [_buildLeftPanel(), _buildRightPanel()]),
    );
  }
}