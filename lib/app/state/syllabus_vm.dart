// lib/app/state/syllabus_vm.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';

enum ChatRole { system, user, assistant, status }
enum FlowStage { upload, convert, ask }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final ChatRole role;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        "role": role.name,
        "text": text,
        "createdAt": createdAt.toIso8601String(),
      };

  static ChatMessage fromJson(Map<String, dynamic> j) {
    final roleStr = (j["role"] ?? "assistant").toString();
    final role = ChatRole.values.firstWhere(
      (r) => r.name == roleStr,
      orElse: () => ChatRole.assistant,
    );
    return ChatMessage(
      role: role,
      text: (j["text"] ?? "").toString(),
      createdAt: DateTime.tryParse((j["createdAt"] ?? "").toString()) ?? DateTime.now(),
    );
  }
}

class CsvPreview {
  CsvPreview({required this.title, required this.text});
  final String title;
  final String text;
}

class ChatStore {
  static const String _chatKey = "syllabus_chat_v6";
  static const String _pathsKey = "syllabus_paths_v6";

  static Future<List<ChatMessage>> loadChat() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chatKey);
    if (raw == null || raw.trim().isEmpty) return [];

    try {
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      return list.map((e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveChat(List<ChatMessage> msgs) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(msgs.map((m) => m.toJson()).toList());
    await prefs.setString(_chatKey, raw);
  }

  static Future<void> clearChat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chatKey);
  }

  static Future<void> savePaths({
    required String? chunksCsvPath,
    required String? mainCsvPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pathsKey, jsonEncode({"chunks": chunksCsvPath, "main": mainCsvPath}));
  }

  static Future<Map<String, String?>> loadPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pathsKey);
    if (raw == null || raw.trim().isEmpty) return {"chunks": null, "main": null};

    try {
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return {
        "chunks": (j["chunks"] as dynamic)?.toString(),
        "main": (j["main"] as dynamic)?.toString(),
      };
    } catch (_) {
      return {"chunks": null, "main": null};
    }
  }

  static Future<void> clearPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pathsKey);
  }
}

class SyllabusViewModel extends ChangeNotifier {
  SyllabusViewModel({required this.api});
  final ApiClient api;

  final TextEditingController inputCtrl = TextEditingController();
  final ScrollController scrollCtrl = ScrollController();
  final FocusNode inputFocus = FocusNode();

  PlatformFile? pickedFile;
  Uint8List? fileBytes;

  String? chunksCsvPath;
  String? mainCsvPath;

  CsvPreview? preview;
  String? error;

  bool picking = false;
  bool converting = false;
  bool asking = false;
  bool viewing = false;

  final List<ChatMessage> messages = [];

  bool get hasPdf => pickedFile != null && fileBytes != null;

  bool get hasConverted =>
      (chunksCsvPath != null && chunksCsvPath!.isNotEmpty) &&
      (mainCsvPath != null && mainCsvPath!.isNotEmpty);

  bool get isBusy => picking || converting || asking || viewing;

  FlowStage get stage {
    if (!hasPdf) return FlowStage.upload;
    if (!hasConverted) return FlowStage.convert;
    return FlowStage.ask;
  }

  double get stageProgress {
    if (!hasPdf) return picking ? 0.12 : 0.06;
    if (!hasConverted) return converting ? 0.58 : 0.40;
    return asking ? 0.92 : 0.78;
  }

  String get fileNameShort {
    final n = pickedFile?.name ?? "";
    if (n.isEmpty) return "";
    if (n.length <= 24) return n;
    return "${n.substring(0, 14)}…${n.substring(n.length - 8)}";
  }

  @override
  void dispose() {
    inputCtrl.dispose();
    scrollCtrl.dispose();
    inputFocus.dispose();
    super.dispose();
  }

  Future<void> init() async {
    final stored = await ChatStore.loadChat();
    messages
      ..clear()
      ..addAll(stored);

    final paths = await ChatStore.loadPaths();
    chunksCsvPath = paths["chunks"];
    mainCsvPath = paths["main"];

    if (messages.isEmpty) {
      _addSystem("Welcome 👋\nUpload a syllabus PDF, convert to CSV, then ask questions.");
      await _persist();
    }

    notifyListeners();
  }

  Future<void> clearEverything() async {
    pickedFile = null;
    fileBytes = null;
    chunksCsvPath = null;
    mainCsvPath = null;
    preview = null;
    error = null;

    messages
      ..clear()
      ..add(ChatMessage(role: ChatRole.system, text: "Welcome 👋\nUpload a syllabus PDF, convert to CSV, then ask questions.", createdAt: DateTime.now()));

    await ChatStore.clearChat();
    await ChatStore.clearPaths();
    await _persist();

    notifyListeners();
  }

  Future<void> _persist() async {
    await ChatStore.saveChat(messages);
    await ChatStore.savePaths(chunksCsvPath: chunksCsvPath, mainCsvPath: mainCsvPath);
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollCtrl.hasClients) return;
      scrollCtrl.animateTo(
        scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _cleanException(Object e) {
    final s = e.toString();
    return s.startsWith("Exception: ") ? s.substring("Exception: ".length) : s;
  }

  void _addSystem(String text) => messages.add(ChatMessage(role: ChatRole.system, text: text, createdAt: DateTime.now()));
  void _addUser(String text) => messages.add(ChatMessage(role: ChatRole.user, text: text, createdAt: DateTime.now()));
  void _addAssistant(String text) => messages.add(ChatMessage(role: ChatRole.assistant, text: text, createdAt: DateTime.now()));
  void _addStatus(String text) => messages.add(ChatMessage(role: ChatRole.status, text: text, createdAt: DateTime.now()));

  void _removeLastStatusIfAny() {
    if (messages.isNotEmpty && messages.last.role == ChatRole.status) messages.removeLast();
  }

  Future<void> pickPdf() async {
    if (picking) return;
    picking = true;
    error = null;

    _addStatus("Opening file picker…");
    notifyListeners();
    _scrollToBottomSoon();

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      _removeLastStatusIfAny();

      if (result == null || result.files.isEmpty) {
        _addAssistant("No file selected.");
        await _persist();
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _addAssistant("Could not read file bytes. Try again.");
        await _persist();
        return;
      }

      pickedFile = file;
      fileBytes = bytes;

      chunksCsvPath = null;
      mainCsvPath = null;

      _addAssistant("Selected: **${file.name}**\nTap **Convert**.");
      await _persist();
    } catch (e) {
      _removeLastStatusIfAny();
      error = _cleanException(e);
      _addAssistant("Error selecting file: ${_cleanException(e)}");
      await _persist();
    } finally {
      picking = false;
      notifyListeners();
      _scrollToBottomSoon();
    }
  }

  Future<void> convertPdf() async {
    if (converting) return;
    if (!hasPdf) {
      _addAssistant("Upload a PDF first.");
      notifyListeners();
      _scrollToBottomSoon();
      return;
    }

    converting = true;
    error = null;

    _addStatus("Uploading PDF…");
    notifyListeners();
    _scrollToBottomSoon();

    try {
      final data = await api.convertUpload(pdfBytes: fileBytes!, fileName: pickedFile!.name);

      _removeLastStatusIfAny();
      _addStatus("Generating CSV…");
      notifyListeners();
      _scrollToBottomSoon();

      final chunks = (data["chunks_csv"] ?? "").toString();
      final main = (data["single_row_csv"] ?? "").toString();

      chunksCsvPath = chunks.isEmpty ? null : chunks;
      mainCsvPath = main.isEmpty ? null : main;

      _removeLastStatusIfAny();

      if (!hasConverted) {
        _addAssistant("Conversion finished, but no CSV paths were returned.");
      } else {
        _addAssistant("✅ CSV ready. You can **Preview**, **Download**, and start asking.");
      }

      await _persist();
    } catch (e) {
      _removeLastStatusIfAny();
      error = _cleanException(e);
      _addAssistant("Conversion failed: ${_cleanException(e)}");
      await _persist();
    } finally {
      converting = false;
      notifyListeners();
      _scrollToBottomSoon();
    }
  }

  Future<void> viewCsv() async {
    if (viewing) return;
    if (mainCsvPath == null || mainCsvPath!.isEmpty) {
      _addAssistant("No CSV yet. Convert your PDF first.");
      notifyListeners();
      _scrollToBottomSoon();
      return;
    }

    viewing = true;
    error = null;

    _addStatus("Loading preview…");
    notifyListeners();
    _scrollToBottomSoon();

    try {
      final text = await api.fetchCsvText(csvPath: mainCsvPath!);
      _removeLastStatusIfAny();
      preview = CsvPreview(title: "Main CSV Preview", text: text);
    } catch (e) {
      _removeLastStatusIfAny();
      error = _cleanException(e);
      _addAssistant("Preview failed: ${_cleanException(e)}");
      await _persist();
    } finally {
      viewing = false;
      notifyListeners();
      _scrollToBottomSoon();
    }
  }

  Future<void> downloadCsv() async {
    if (mainCsvPath == null || mainCsvPath!.isEmpty) {
      _addAssistant("No CSV to download yet.");
      notifyListeners();
      _scrollToBottomSoon();
      return;
    }

    final uri = api.csvDownloadUri(csvPath: mainCsvPath!);
    final ok = await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );

    if (!ok) {
      _addAssistant("Could not open the download link.");
      notifyListeners();
      _scrollToBottomSoon();
    }
  }

  Future<void> sendQuestion() async {
    if (asking) return;

    final q = inputCtrl.text.trim();
    if (q.isEmpty) return;

    _addUser(q);
    inputCtrl.clear();
    notifyListeners();
    _scrollToBottomSoon();

    if (chunksCsvPath == null || chunksCsvPath!.isEmpty) {
      _addAssistant("Convert the PDF first, then ask questions.");
      await _persist();
      notifyListeners();
      _scrollToBottomSoon();
      return;
    }

    asking = true;
    error = null;

    _addStatus("Typing");
    notifyListeners();
    _scrollToBottomSoon();

    try {
      final data = await api.askFromChunksPath(question: q, chunksCsvPath: chunksCsvPath!);
      final a = (data["answer"] ?? "").toString().trim();

      _removeLastStatusIfAny();
      _addAssistant(a.isEmpty ? "No answer returned." : a);

      await _persist();
    } catch (e) {
      _removeLastStatusIfAny();
      error = _cleanException(e);
      _addAssistant("Ask failed: ${_cleanException(e)}");
      await _persist();
    } finally {
      asking = false;
      notifyListeners();
      _scrollToBottomSoon();
    }
  }

  Future<void> sendQuick(String text) async {
    inputCtrl.text = text;
    await sendQuestion();
    inputFocus.requestFocus();
  }
}
