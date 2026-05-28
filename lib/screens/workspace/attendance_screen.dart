// lib/screens/workspace/attendance_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../widgets/student_preview_card.dart';
import 'statistics_screen.dart';
import '../../utils/file_saver.dart';
import 'generate_encodings_screen.dart';
import 'webcam_capture_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final int workspaceId;
  final String sectionId;
  final String courseTitle;

  const AttendanceScreen({
    super.key,
    required this.workspaceId,
    required this.sectionId,
    required this.courseTitle,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final ApiService api = ApiService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController lectureCtrl = TextEditingController(text: "1");

  bool loading = false;
  String statusText = 'Idle';
  int lectureNumber = 1;
  int? lastLectureFromDb;
  List<int> availableLectures = [];
  bool showUploadPanel = false;
  Map<String, String> studentNameMap = {};
  String? hoveredAction;

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  Future<void> _initLoad() async {
    await loadLastLecture(); // sets lectureNumber to latest FIRST
    loadAvailableLectures(); // runs in parallel after
    loadStudents(); // now uses correct lectureNumber
  }

  Future<void> loadAvailableLectures() async {
    try {
      final list = await api.getAvailableLectures(
        workspaceId: widget.workspaceId,
        sectionId: widget.sectionId,
      );
      setState(() {
        availableLectures = list;
      });
    } catch (e) {
      print("Error loading available lectures: $e");
    }
  }

  Future<void> loadStudents() async {
    try {
      final students = await api.getStudentsForSection(
        workspaceId: widget.workspaceId,
        sectionId: widget.sectionId,
      );

      studentNameMap = {for (var s in students) s["student_id"]: s["name"]};

      final rows = students.map((s) {
        return {
          "StudentID": s["student_id"],
          "Name": s["name"],
          "Status": null,
          "Confidence": "Unknown",
        };
      }).toList();

      setState(() {
        previewRows = rows;
      });
      await loadAttendanceForLecture();
    } catch (e) {
      print("Error loading students: $e");
    }
  }

  Future<void> loadAttendanceForLecture() async {
    try {
      final rows = await api.getAttendanceForLecture(
        workspaceId: widget.workspaceId,
        sectionId: widget.sectionId,
        lectureNumber: lectureNumber,
      );

      for (var r in previewRows) {
        r["Status"] = null;
        r["Confidence"] = "Unknown";
      }

      for (var dbRow in rows) {
        final index = previewRows.indexWhere(
          (r) => r["StudentID"] == dbRow["student_id"],
        );

        if (index != -1) {
          previewRows[index]["Status"] = dbRow["status"];
          previewRows[index]["Confidence"] = dbRow["confidence"];
        }
      }

      setState(() {});
    } catch (e) {
      print("Error loading attendance: $e");
    }
  }

  // =============================
  // Export from DB (collapsed UI)
  // =============================
  bool showDbExport = false;
  final TextEditingController dbExportLectureCtrl = TextEditingController(
    text: '1',
  );

  List<Map<String, dynamic>> previewRows = [];

  bool uploadedOk = false;
  List<String> uploadedFileNames = [];
  List<String> uploadedVideoIds = [];
  List<File> _pickedVideoFiles = [];
  List<File> selectedImages = [];

  Future<void> loadLastLecture() async {
    try {
      final last = await api.getLastLecture(
        workspaceId: widget.workspaceId,
        sectionId: widget.sectionId,
      );
      setState(() {
        lastLectureFromDb = last;
        lectureNumber = last ?? 1;
        lectureCtrl.text = lectureNumber.toString();
      });
    } catch (e) {
      print("Error loading last lecture: $e");
    }
  }

  // =============================
  // Helper to map backend rows to UI
  // =============================
  void _applyPreviewRows(List<dynamic> rowsRaw) {
    for (var r in rowsRaw) {
      final sid = r["student_id"];
      final status = r["status"];
      final confidence = r["confidence"];
      final index = previewRows.indexWhere((x) => x["StudentID"] == sid);

      if (index != -1) {
        final currentStatus = previewRows[index]["Status"];

        if (currentStatus == "Present") {
        } else if (status == "Present") {
          previewRows[index]["Status"] = "Present";
          previewRows[index]["Confidence"] = confidence;
        } else if (currentStatus == null) {
          previewRows[index]["Status"] = status;
          previewRows[index]["Confidence"] = confidence;
        }
      }
    }
  }

  // =============================
  // Step 1a: Pick video from files (no processing yet)
  // =============================
  Future<void> pickAndUploadVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.video);

      if (result == null ||
          result.files.isEmpty ||
          result.files.first.path == null) {
        return;
      }

      final file = File(result.files.first.path!);

      setState(() {
        _pickedVideoFiles.add(file);
        uploadedVideoIds.add("picked_video_${uploadedVideoIds.length}");
        uploadedFileNames.add(result.files.first.name);
        uploadedOk = false;
        statusText = 'Video selected. Press "Take Attendance" to process.';
      });
    } catch (e) {
      setState(() {
        statusText = 'Error picking video: $e';
      });
    }
  }

  // =============================
  // Step 1b: Capture video from camera (no processing yet)
  // =============================
  Future<void> captureAndUploadVideo() async {
    try {
      File? file;

      if (Platform.isWindows) {
        file = await Navigator.push<File>(
          context,
          MaterialPageRoute(
            builder: (_) => const WebcamCaptureScreen(mode: CaptureMode.video),
          ),
        );
      } else {
        final XFile? captured = await _picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 30),
        );

        if (captured != null) {
          file = File(captured.path);
        }
      }

      if (file == null) return;

      setState(() {
        _pickedVideoFiles.add(file!);

        uploadedVideoIds.add(
          "captured_video_${uploadedVideoIds.length}",
        );

        uploadedFileNames.add(
          "Captured Video ${uploadedFileNames.length + 1}",
        );

        uploadedOk = false;

        statusText = 'Video captured. Press "Take Attendance" to process.';
      });
    } catch (e) {
      setState(() {
        statusText = 'Error capturing video: $e';
      });
    }
  }

  Future<void> pickImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'jfif',
          'webp',
        ],
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final files = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();

      if (files.isEmpty) {
        return;
      }

      setState(() {
        selectedImages.addAll(
          files.where(
            (f) => !selectedImages.any(
              (e) => e.path == f.path,
            ),
          ),
        );

        // limit max images
        selectedImages = selectedImages.take(10).toList();

        uploadedOk = false;

        statusText = 'Images selected. Press "Take Attendance" to process.';
      });
    } catch (e) {
      setState(() {
        statusText = 'Error picking images: $e';
      });
    }
  }

  Future<void> captureImage() async {
    try {
      File? file;

      if (Platform.isWindows) {
        file = await Navigator.push<File>(
          context,
          MaterialPageRoute(
            builder: (_) => const WebcamCaptureScreen(
              mode: CaptureMode.photo,
            ),
          ),
        );
      } else {
        final XFile? captured = await _picker.pickImage(
          source: ImageSource.camera,
        );

        if (captured != null) {
          file = File(captured.path);
        }
      }

      if (file == null) {
        return;
      }

      setState(() {
        selectedImages.add(file!);

        uploadedOk = false;

        statusText = 'Image captured. Press "Take Attendance" to process.';
      });
    } catch (e) {
      setState(() {
        statusText = 'Error capturing image: $e';
      });
    }
  }

  // =============================
  // Step 2: Send video to backend and process attendance
  // =============================
  Future<void> runPreview() async {
    if (_pickedVideoFiles.isEmpty && selectedImages.isEmpty) {
      setState(() {
        statusText = 'Please select at least one image or video.';
      });
      return;
    }

    setState(() {
      loading = true;
      statusText = 'Processing media...';

      for (var r in previewRows) {
        r["Status"] = null;
        r["Confidence"] = "Unknown";
      }
    });

    try {
      // =============================
      // Process Images First
      // =============================
      if (selectedImages.isNotEmpty) {
        final data = await api.previewImagesAttendance(
          lectureNumber: lectureNumber,
          workspaceId: widget.workspaceId,
          sectionId: widget.sectionId,
          images: selectedImages,
        );

        if (data['ok'] == true) {
          final rowsRaw = (data['rows'] as List).cast<dynamic>();
          _applyPreviewRows(rowsRaw);
        } else {
          throw Exception(
            data['error'] ?? 'Image processing failed',
          );
        }
      }

      // =============================
      // Process Videos
      // =============================
      if (_pickedVideoFiles.isNotEmpty) {
        final futures = _pickedVideoFiles
            .map(
              (file) => api.uploadCheck(
                videoFile: file,
                lectureNumber: lectureNumber,
                workspaceId: widget.workspaceId,
                sectionId: widget.sectionId,
              ),
            )
            .toList();

        final results = await Future.wait(futures);

        for (var upload in results) {
          if (upload['ok'] == true) {
            final rowsRaw = (upload['rows'] as List).cast<dynamic>();
            _applyPreviewRows(rowsRaw);
          } else {
            throw Exception(
              upload['error'] ?? 'Video processing failed',
            );
          }
        }
      }

      setState(() {
        uploadedOk = true;
        loading = false;
        statusText = 'Attendance preview ready ✅';
      });
    } catch (e) {
      setState(() {
        loading = false;
        statusText = 'Error: $e';
      });
    }
  }

  // =============================
  // Export Attendance
  // =============================
  Future<void> exportAttendance() async {
    try {
      setState(() {
        loading = true;
        statusText = 'Exporting...';
      });

      final bytes = await api.exportAttendanceCsvFromDb(
        lectureNumber: lectureNumber,
        workspaceId: widget.workspaceId,
        sectionId: widget.sectionId,
      );

      String cleanCourse =
          widget.courseTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();

      final fileName = '$cleanCourse-${widget.sectionId}(L$lectureNumber).csv';

      final savedPath = await FileSaver.saveToDownloads(
        bytes: bytes,
        fileName: fileName,
      );

      setState(() {
        loading = false;
        statusText = 'Exported ✅';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to Downloads:\n$savedPath')),
        );
      }
    } catch (e) {
      setState(() {
        loading = false;
        statusText = 'Export failed: $e';
      });
    }
  }

  // =============================
  // Export ALL lectures
  // =============================
  Future<void> exportAllAttendance() async {
    try {
      setState(() {
        loading = true;
        statusText = 'Exporting ALL...';
      });

      final bytes = await api.exportAttendanceCsvFromDb(
        workspaceId: widget.workspaceId,
        sectionId: widget.sectionId,
        lectureNumber: null,
      );

      String cleanCourse =
          widget.courseTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();

      final fileName = '$cleanCourse-${widget.sectionId}(ALL).csv';

      final savedPath = await FileSaver.saveToDownloads(
        bytes: bytes,
        fileName: fileName,
      );

      setState(() {
        loading = false;
        statusText = 'Exported ALL ✅';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to Downloads:\n$savedPath')),
        );
      }
    } catch (e) {
      setState(() {
        loading = false;
        statusText = 'Export ALL failed: $e';
      });
    }
  }

  // =============================
  // Confirm and save to db button
  // =============================
  Future<void> confirmAndSave() async {
    bool hasUnmarked = previewRows.any((r) => r["Status"] == null);

    if (hasUnmarked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please mark all students before saving ⚠️"),
        ),
      );
      return;
    }

    if (previewRows.isEmpty) {
      setState(() => statusText = 'No preview to save');
      return;
    }

    setState(() {
      loading = true;
      statusText = 'Saving attendance...';
    });

    try {
      final rowsForApi = previewRows.map((r) {
        return {
          "student_id": r["StudentID"].toString(),
          "status": (r["Status"] ?? "Absent").toString(),
          "confidence": (r["Confidence"] ?? "Unknown").toString(),
        };
      }).toList();

      final res = await api.confirmAttendance(
        lectureNumber: lectureNumber,
        workspaceId: widget.workspaceId,
        sectionId: widget.sectionId,
        rows: rowsForApi,
      );

      if (res["ok"] != true) {
        throw Exception(res["error"] ?? "Save failed");
      }

      setState(() {
        loading = false;
        statusText = 'Attendance saved successfully ✅';
      });

      // Refresh available lectures and last lecture indicator
      // WITHOUT changing the current lectureNumber the user is on
      loadAvailableLectures();
      try {
        final last = await api.getLastLecture(
          workspaceId: widget.workspaceId,
          sectionId: widget.sectionId,
        );
        setState(() {
          lastLectureFromDb = last;
          // intentionally NOT changing lectureNumber or lectureCtrl
        });
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance saved successfully ✅')),
        );
      }
    } catch (e) {
      setState(() {
        loading = false;
        statusText = 'Save failed: $e';
      });
    }
  }

  // =============================
  // Status toggle
  // =============================
  void setStatus(int i, String status) {
    setState(() {
      previewRows[i]['Status'] = status;
    });
  }

  void setAllStatus(String status) {
    setState(() {
      for (var r in previewRows) {
        r['Status'] = status;
      }
    });
  }

  int get presentCount =>
      previewRows.where((r) => r['Status'] == 'Present').length;

  int get absentCount =>
      previewRows.where((r) => r['Status'] == 'Absent').length;

  int get excusedCount =>
      previewRows.where((r) => r['Status'] == 'Excused').length;

  // =============================
  // UI helpers
  // =============================
  Widget countPill(String label, int v, Color c) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            v.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  Widget statusBtn(String t, bool active, Color c, VoidCallback tap) {
    return OutlinedButton(
      onPressed: tap,
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? c.withOpacity(.15) : null,
        side: BorderSide(color: active ? c : Colors.grey),
      ),
      child: Text(
        t,
        style: TextStyle(
          color: active ? c : Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  void dispose() {
    dbExportLectureCtrl.dispose();
    super.dispose();
  }

  bool get isLectureAlreadyRecorded {
    return availableLectures.contains(lectureNumber);
  }

  // =============================
  // Build
  // =============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.courseTitle} - Section ${widget.sectionId}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.face_retouching_natural, size: 32),
            tooltip: "Student Face Encodings",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GenerateEncodingsScreen(),
                ),
              );
            },
          ),
          // Your existing Statistics Button
          IconButton(
            icon: const Icon(Icons.analytics,
                size: 36), // slightly resized to match
            tooltip: "View Statistics",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StatisticsScreen(
                    workspaceId: widget.workspaceId,
                    sectionId: widget.sectionId,
                    courseTitle: widget.courseTitle,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8), // Just a little padding on the right edge
        ],
      ),
      body: Column(
        children: [
          // TOP CONTROLS (scrollable on mobile if content is tall)
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    const Text(
                      'Lecture',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 6),

                    IconButton(
                      onPressed: lectureNumber <= 1
                          ? null
                          : () {
                              setState(() {
                                lectureNumber--;
                                lectureCtrl.text = lectureNumber.toString();
                                loadAttendanceForLecture();
                              });
                            },
                      icon: const Icon(Icons.remove),
                    ),

                    SizedBox(
                      width: 45,
                      child: TextField(
                        controller: lectureCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 4,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (value) {
                          int num = int.tryParse(value) ?? 1;
                          if (num < 1) num = 1;
                          setState(() {
                            lectureNumber = num;
                          });
                          loadAttendanceForLecture();
                        },
                      ),
                    ),

                    const SizedBox(width: 10),

                    IconButton(
                      onPressed: () {
                        setState(() {
                          lectureNumber++;
                          lectureCtrl.text = lectureNumber.toString();
                          loadAttendanceForLecture();
                        });
                      },
                      icon: const Icon(Icons.add),
                    ),

                    const SizedBox(width: 10),

                    // Blue info pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        lastLectureFromDb == null
                            ? 'No records'
                            : 'Last: $lastLectureFromDb',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Red warning (only if duplicate)
                    if (isLectureAlreadyRecorded)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '⚠️ Attendance already taken',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 4),

                // Upload + Capture - Collapsible Panel
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => showUploadPanel = !showUploadPanel);
                    },
                    icon: Icon(
                      showUploadPanel ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: const Text('Take Attendnace by Face Recognition'),
                  ),
                ),

                if (showUploadPanel)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Upload + Capture buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: loading
                                    ? null
                                    : () async {
                                        final result =
                                            await showModalBottomSheet<String>(
                                          context: context,
                                          builder: (_) {
                                            return SafeArea(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ListTile(
                                                    leading:
                                                        const Icon(Icons.image),
                                                    title: const Text(
                                                        "Upload Images"),
                                                    onTap: () => Navigator.pop(
                                                      context,
                                                      "images",
                                                    ),
                                                  ),
                                                  ListTile(
                                                    leading: const Icon(
                                                        Icons.videocam),
                                                    title: const Text(
                                                        "Upload Video"),
                                                    onTap: () => Navigator.pop(
                                                      context,
                                                      "video",
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );

                                        if (result == "images") {
                                          pickImages();
                                        } else if (result == "video") {
                                          pickAndUploadVideo();
                                        }
                                      },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.grey.shade400,
                                    width: 1.2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.upload_file, size: 18),
                                label: const Text(
                                  'Upload Media',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: loading
                                    ? null
                                    : () async {
                                        final result =
                                            await showModalBottomSheet<String>(
                                          context: context,
                                          builder: (_) {
                                            return SafeArea(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ListTile(
                                                    leading: const Icon(
                                                        Icons.camera_alt),
                                                    title: const Text(
                                                        "Capture Image"),
                                                    onTap: () => Navigator.pop(
                                                      context,
                                                      "image",
                                                    ),
                                                  ),
                                                  ListTile(
                                                    leading: const Icon(
                                                        Icons.videocam),
                                                    title: const Text(
                                                        "Capture Video"),
                                                    onTap: () => Navigator.pop(
                                                      context,
                                                      "video",
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );

                                        if (result == "image") {
                                          captureImage();
                                        } else if (result == "video") {
                                          captureAndUploadVideo();
                                        }
                                      },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.grey.shade400,
                                    width: 1.2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.camera_alt, size: 18),
                                label: const Text(
                                  'Capture Media',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // Video Preview
                        if (uploadedVideoIds.isNotEmpty)
                          Column(
                            children: List.generate(uploadedVideoIds.length, (
                              index,
                            ) {
                              return Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.videocam,
                                      size: 18,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        uploadedFileNames[index],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          uploadedVideoIds.removeAt(index);
                                          uploadedFileNames.removeAt(index);
                                          _pickedVideoFiles.removeAt(index);
                                        });
                                      },
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
// Image Preview
                        if (selectedImages.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                List.generate(selectedImages.length, (index) {
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      selectedImages[index],
                                      width: 90,
                                      height: 90,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
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
                                        padding: const EdgeInsets.all(3),
                                        child: const Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        const SizedBox(height: 10),

                        // Take Attendance button
                        SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: ElevatedButton(
                              onPressed: (loading ||
                                      (_pickedVideoFiles.isEmpty &&
                                          selectedImages.isEmpty))
                                  ? null
                                  : runPreview,
                              style: ElevatedButton.styleFrom(
                                elevation: 7,
                                shadowColor: Colors.black.withOpacity(0.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text(
                                "Take Attendance",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),

                const SizedBox(height: 6),

                // Pills + bulk action buttons
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            countPill('Present', presentCount, Colors.green),
                            const SizedBox(width: 8),
                            countPill('Absent', absentCount, Colors.red),
                            const SizedBox(width: 8),
                            countPill('Excused', excusedCount, Colors.orange),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => setAllStatus('Present'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.green,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Text("Present all"),
                        ),
                        const SizedBox(width: 4),
                        Container(width: 1, height: 16, color: Colors.black54),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: () => setAllStatus('Absent'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text("Absent all"),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 5),
              ],
            ),
          ),

          //STUDENT LIST
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                itemCount: previewRows.length,
                itemBuilder: (_, i) => StudentCard(
                  row: previewRows[i],
                  index: i,
                  onPresent: () => setStatus(i, 'Present'),
                  onAbsent: () => setStatus(i, 'Absent'),
                  onExcused: () => setStatus(i, 'Excused'),
                ),
              ),
            ),
          ),

          // BOTTOM ACTIONS
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Column(
              children: [
                // Confirm & Save
                SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: (loading || previewRows.isEmpty)
                          ? null
                          : confirmAndSave,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.grey.shade500,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle),
                      label: const Text(
                        'Confirm & Save',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )),

                const SizedBox(height: 6),

                // Export Attendance
                SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: previewRows.isEmpty ? null : exportAttendance,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: BorderSide(
                            color: const Color.fromARGB(255, 145, 78, 167),
                            width: 1.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.ios_share),
                      label: const Text(
                        'Export Attendance',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    )),

                // Collapsed: Export from DB (History)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => showDbExport = !showDbExport);
                    },
                    icon: Icon(
                      showDbExport ? Icons.expand_less : Icons.expand_more,
                    ),
                    label: const Text(
                      'Export from database…',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                if (showDbExport)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Lecture',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'Lecture:',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.remove),
                              onPressed: () {
                                final value =
                                    int.tryParse(dbExportLectureCtrl.text) ?? 1;
                                if (value > 1) {
                                  dbExportLectureCtrl.text =
                                      (value - 1).toString();
                                }
                              },
                            ),
                            SizedBox(
                              width: 40,
                              child: TextField(
                                controller: dbExportLectureCtrl,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: const InputDecoration(
                                  border: UnderlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () {
                                final value =
                                    int.tryParse(dbExportLectureCtrl.text) ?? 0;
                                dbExportLectureCtrl.text =
                                    (value + 1).toString();
                                setState(() {});
                              },
                            ),
                            const Spacer(),
                            SizedBox(
                              height: 32,
                              child: OutlinedButton(
                                onPressed: loading ? null : exportAllAttendance,
                                child: const Text('ALL'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: loading
                                ? null
                                : () async {
                                    try {
                                      setState(() {
                                        loading = true;
                                        statusText = 'Exporting from DB...';
                                      });

                                      final text =
                                          dbExportLectureCtrl.text.trim();
                                      int lec = int.tryParse(text) ?? 1;
                                      if (lec < 1) lec = 1;

                                      if (!availableLectures.contains(lec)) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              "No attendance recorded for this lecture",
                                            ),
                                          ),
                                        );
                                        setState(() {
                                          loading = false;
                                        });
                                        return;
                                      }

                                      final bytes =
                                          await api.exportAttendanceCsvFromDb(
                                        lectureNumber: lec,
                                        workspaceId: widget.workspaceId,
                                        sectionId: widget.sectionId,
                                      );

                                      String cleanCourse = widget.courseTitle
                                          .replaceAll(
                                            RegExp(r'[\\/:*?"<>|]'),
                                            '',
                                          )
                                          .trim();

                                      final fileName =
                                          '$cleanCourse-${widget.sectionId}(L$lec).csv';

                                      final savedPath =
                                          await FileSaver.saveToDownloads(
                                        bytes: bytes,
                                        fileName: fileName,
                                      );

                                      setState(() {
                                        loading = false;
                                        statusText = 'Exported ✅';
                                      });

                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Saved to Downloads:\n$savedPath',
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      setState(() {
                                        loading = false;
                                        statusText = 'Export failed: $e';
                                      });
                                    }
                                  },
                            icon: const Icon(Icons.download),
                            label: const Text('Download CSV'),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 6),
                Text(statusText, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
