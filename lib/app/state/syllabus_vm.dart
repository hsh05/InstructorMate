// lib/app/state/syllabus_vm.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';

import '../models/chat_models.dart';

export '../models/chat_models.dart';
//import '../../ui/widgets/chat_widgets.dart';


class SyllabusViewModel extends ChangeNotifier {
  SyllabusViewModel({required this.api});

  final ApiClient api;

  // Controllers used by UI
  final ScrollController scrollCtrl = ScrollController();
  final TextEditingController inputCtrl = TextEditingController();
  final FocusNode inputFocus = FocusNode();

  // Data
  Uint8List? _pdfBytes;
  String? _fileName;

  // Backend identifier (docId-only flow)
  String? docId;

  // UI state flags
  bool picking = false;
  bool converting = false;
  bool asking = false;
  bool viewing = false;

  // Preview holder
  CsvPreview? preview;

  // Chat messages
  final List<ChatMessage> messages = [];

  // ----- Derived -----
  bool get hasPdf => _pdfBytes != null && (_fileName?.isNotEmpty ?? false);
  bool get hasConverted => (docId != null && docId!.trim().isNotEmpty);
  bool get isBusy => picking || converting || asking || viewing;

  FlowStage get stage {
    if (!hasPdf) return FlowStage.upload;
    if (!hasConverted) return FlowStage.convert;
    return FlowStage.ask;
  }

  double get stageProgress {
    if (!hasPdf) return 0.05;
    if (converting) return 0.50;
    if (hasConverted && asking) return 0.85;
    if (hasConverted) return 0.70;
    return 0.35;
  }

  String get fileNameShort {
    final f = _fileName ?? "";
    if (f.length <= 26) return f;
    return "${f.substring(0, 14)}…${f.substring(f.length - 10)}";
  }

  // ----- lifecycle -----
  void init() {
    messages
      ..clear()
      ..add(
        ChatMessage(
          role: ChatRole.system,
          text: "Welcome 👋\nUpload a syllabus PDF, convert, then ask questions.",
        ),
      );
    notifyListeners();
    _scrollToBottom(jump: true);
  }

  // -----------------------
  // Actions
  // -----------------------

Future<void> pickPdf() async {
  if (picking) return;

  picking = true;
  notifyListeners();

  try {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );

    if (res == null || res.files.isEmpty) return;

    final f = res.files.first;
    _pdfBytes = f.bytes;
    _fileName = f.name;

    docId = null;
    preview = null;
    messages.clear();

    // ✅ auto convert after upload
    await convertPdf();

  } catch (_) {
    // keep your existing error handling if any
  } finally {
    picking = false;
    notifyListeners();
  }
}


  Future<void> convertPdf() async {
    if (converting || !hasPdf) return;
    converting = true;
    notifyListeners();

    try {
      _pushStatus("Uploading & converting…");

      // ✅ your ApiClient returns docId
      final id = await api.convertUploadGetDocId(
        pdfBytes: _pdfBytes!,
        fileName: _fileName!,
      );

      docId = id;
      await viewCsv();
      _pushAssistant("Converted ✅\nYou can now ask questions.");
    } catch (e) {
      _pushAssistant("Conversion failed: $e");
    } finally {
      converting = false;
      notifyListeners();
      _scrollToBottom();
    }
  }

  Future<void> viewCsv() async {
    if (viewing || !hasConverted) return;
    viewing = true;
    notifyListeners();

    try {
      final text = await api.fetchCsvTextByDocId(
        docId: docId!,
        kind: "single_row",
      );
      preview = CsvPreview(title: "Single-row CSV", text: text);
    } catch (e) {
      _pushAssistant("View CSV failed: $e");
    } finally {
      viewing = false;
      notifyListeners();
    }
  }

  Future<void> downloadCsv() async {
    if (!hasConverted) return;
    try {
      final uri = api.csvDownloadByDocIdUri(
        docId: docId!,
        kind: "single_row",
      );
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _pushAssistant("Could not open download link.");
    } catch (e) {
      _pushAssistant("Download failed: $e");
    } finally {
      notifyListeners();
    }
  }

  Future<void> sendQuick(String text) async {
    inputCtrl.text = text;
    await sendQuestion();
  }

  Future<void> sendQuestion() async {
    final q = inputCtrl.text.trim();
    if (q.isEmpty || asking) return;

    if (!hasConverted) {
      _pushAssistant("Upload + Convert first, then ask questions.");
      return;
    }

    asking = true;
    notifyListeners();

    _pushUser(q);
    inputCtrl.clear();
    _scrollToBottom();

    try {
      _pushStatus("Answering…");

      // ✅ your ApiClient returns String answer
      final answer = await api.ask(question: q, docId: docId!);

      if (answer.trim().isEmpty) {
        _pushAssistant("No answer returned.");
      } else {
        _pushAssistant(answer);
      }
    } catch (e) {
      _pushAssistant("Ask failed: $e");
    } finally {
      asking = false;
      notifyListeners();
      _scrollToBottom();
    }
  }

  void clearEverything() {
    _pdfBytes = null;
    _fileName = null;
    docId = null;
    preview = null;

    messages
      ..clear()
      ..add(
        ChatMessage(
          role: ChatRole.system,
          text: "Welcome 👋\nUpload a syllabus PDF, convert, then ask questions.",
        ),
      );

    notifyListeners();
    _scrollToBottom(jump: true);
  }

  // -----------------------
  // helpers
  // -----------------------

  void _pushUser(String t) {
    messages.add(ChatMessage(role: ChatRole.user, text: t));
    notifyListeners();
  }

  void _pushAssistant(String t) {
    messages.add(ChatMessage(role: ChatRole.assistant, text: t));
    notifyListeners();
  }

  void _pushStatus(String t) {
    messages.add(ChatMessage(role: ChatRole.status, text: t));
    notifyListeners();
  }

  void _scrollToBottom({bool jump = false}) {
    if (!scrollCtrl.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollCtrl.hasClients) return;
      final target = scrollCtrl.position.maxScrollExtent + 200;

      if (jump) {
        scrollCtrl.jumpTo(target);
      } else {
        scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    scrollCtrl.dispose();
    inputCtrl.dispose();
    inputFocus.dispose();
    super.dispose();
  }
}
