import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart'; 

class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  // FIXED: Using your real ApiService
  final ApiService _apiService = ApiService();

  bool loading = false;
  String statusText = 'Idle';
  String? fileName;

  Future<void> pickFile() async {
    setState(() {
      loading = true;
      statusText = 'Picking file...';
      fileName = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          loading = false;
          statusText = 'Cancelled';
        });
        return;
      }

      final file = File(result.files.single.path!);

      setState(() {
        fileName = result.files.single.name;
        statusText = 'Uploading...';
      });

      // FIXED: Calling the function we just added to api_service.dart
      final res = await _apiService.uploadStudentList(file: file);

      if (res['ok'] == true) {
        setState(() {
          loading = false;
          // Added a little bonus: showing how many students were inserted!
          statusText = 'Uploaded successfully ✅ (${res['inserted']} students)';
        });
      } else {
        throw Exception(res['error'] ?? 'Upload failed');
      }
    } catch (e) {
      setState(() {
        loading = false;
        statusText = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Upload Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: loading ? null : pickFile,
                icon: const Icon(Icons.upload_file),
                label: Text(loading ? 'Loading...' : 'Upload Student List'),
              ),
            ),

            const SizedBox(height: 20),

            // File preview
            if (fileName != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(fileName!, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Status
            Text(statusText, style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }
}