import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Mode: photo-only or video-only
enum CaptureMode { photo, video }

class WebcamCaptureScreen extends StatefulWidget {
  final CaptureMode mode;

  const WebcamCaptureScreen({super.key, this.mode = CaptureMode.photo});

  @override
  State<WebcamCaptureScreen> createState() => _WebcamCaptureScreenState();
}

class _WebcamCaptureScreenState extends State<WebcamCaptureScreen> {
  CameraController? controller;
  bool loading = true;
  String? errorMessage;

  // Video recording state
  bool isRecording = false;
  Duration recordedDuration = Duration.zero;
  DateTime? _recordingStartTime;

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() {
          errorMessage = "No camera found on this device.";
          loading = false;
        });
        return;
      }

      controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: widget.mode == CaptureMode.video,
      );
      await controller!.initialize();

      if (mounted) setState(() => loading = false);
    } catch (e) {
      debugPrint("Camera init error: $e");
      if (mounted) {
        setState(() {
          errorMessage = "Camera error: $e";
          loading = false;
        });
      }
    }
  }

  // ── Photo capture ─────────────────────────────────────────────────────────
  Future<void> capturePhoto() async {
    try {
      if (controller == null || !controller!.value.isInitialized) return;

      final tempDir = await getTemporaryDirectory();
      final path = p.join(
        tempDir.path,
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final file = await controller!.takePicture();
      final saved = await File(file.path).copy(path);

      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      debugPrint("Capture error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Capture failed: $e")));
      }
    }
  }

  // ── Video recording ───────────────────────────────────────────────────────
  Future<void> startRecording() async {
    try {
      if (controller == null || !controller!.value.isInitialized) return;
      await controller!.startVideoRecording();
      setState(() {
        isRecording = true;
        _recordingStartTime = DateTime.now();
      });

      _tickDuration();
    } catch (e) {
      debugPrint("Start recording error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not start recording: $e")),
        );
      }
    }
  }

  void _tickDuration() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !isRecording) return;
      setState(() {
        recordedDuration = DateTime.now().difference(_recordingStartTime!);
      });
      _tickDuration();
    });
  }

  Future<void> stopRecording() async {
    try {
      if (controller == null || !controller!.value.isRecordingVideo) return;

      final XFile videoFile = await controller!.stopVideoRecording();

      setState(() {
        isRecording = false;
        recordedDuration = Duration.zero;
      });

      final tempDir = await getTemporaryDirectory();
      final path = p.join(
        tempDir.path,
        '${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
      final saved = await File(videoFile.path).copy(path);

      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      debugPrint("Stop recording error: $e");
      if (mounted) {
        setState(() => isRecording = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Recording failed: $e")));
      }
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isVideoMode = widget.mode == CaptureMode.video;

    return Scaffold(
      appBar: AppBar(
        title: Text(isVideoMode ? "Record Video" : "Smartboard Camera"),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.camera_alt,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            loading = true;
                            errorMessage = null;
                          });
                          initCamera();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text("Retry"),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Camera preview
                    Expanded(child: CameraPreview(controller!)),

                    if (isVideoMode && isRecording)
                      Container(
                        color: Colors.black87,
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.fiber_manual_record,
                              color: Colors.red,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatDuration(recordedDuration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Action button
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: isVideoMode
                            ? ElevatedButton.icon(
                                onPressed: isRecording
                                    ? stopRecording
                                    : startRecording,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      isRecording ? Colors.red : null,
                                ),
                                icon: Icon(
                                  isRecording
                                      ? Icons.stop
                                      : Icons.fiber_manual_record,
                                ),
                                label: Text(
                                  isRecording
                                      ? "Stop & Save"
                                      : "Start Recording",
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: capturePhoto,
                                icon: const Icon(Icons.camera),
                                label: const Text("Capture"),
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
