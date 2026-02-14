// lib/ui/syllabus_home.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/state/syllabus_vm.dart';

class SyllabusHome extends StatefulWidget {
  const SyllabusHome({super.key, required this.vm});
  final SyllabusViewModel vm;

  @override
  State<SyllabusHome> createState() => _SyllabusHomeState();
}

class _SyllabusHomeState extends State<SyllabusHome> {
  final questionCtrl = TextEditingController();

  @override
  void dispose() {
    questionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndConvert() async {
    final messenger = ScaffoldMessenger.of(context);

    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ["pdf"],
      withData: true,
    );

    if (!mounted) return;
    if (res == null || res.files.isEmpty) return;

    final f = res.files.first;
    final Uint8List? bytes = f.bytes;
    if (bytes == null) {
      messenger.showSnackBar(const SnackBar(content: Text("Could not read file bytes.")));
      return;
    }

    await widget.vm.convert(pdfBytes: bytes, fileName: f.name);

    if (!mounted) return;
    if (widget.vm.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(widget.vm.error!)));
    }
  }

  Future<void> _ask() async {
    final messenger = ScaffoldMessenger.of(context);

    final q = questionCtrl.text.trim();
    if (q.isEmpty) return;

    await widget.vm.askQuestion(q);

    if (!mounted) return;
    if (widget.vm.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(widget.vm.error!)));
    }
  }

  Future<void> _downloadSingleRow() async {
    final vm = widget.vm;

    // ✅ after backend refactor: vm should store docId (not filesystem paths)
    final docId = (vm.docId ?? "").trim();
    if (docId.isEmpty) return;

    final uri = vm.api.csvDownloadByDocIdUri(docId: docId, kind: "single_row");
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (context, _) {
        final vm = widget.vm;

        final hasConverted = vm.hasConverted; // ideally: based on docId != null
        final hasPreview = (vm.singleRowPreview ?? "").trim().isNotEmpty;
        final busy = vm.converting || vm.asking;

        return Scaffold(
          appBar: AppBar(title: const Text("Syllabus Q&A")),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _TopActions(
                    converting: vm.converting,
                    hasConverted: hasConverted,
                    onPickAndConvert: _pickAndConvert,
                  ),

                  const SizedBox(height: 12),

                  // ✅ Stable preview area (doesn't fight Spacer/Expanded)
                  _PreviewPanel(
                    visible: hasPreview,
                    text: vm.singleRowPreview ?? "",
                  ),

                  const SizedBox(height: 12),

                  // ✅ Ask panel pinned to bottom
                  _AskPanel(
                    controller: questionCtrl,
                    asking: vm.asking,
                    canDownload: hasConverted && !vm.converting,
                    onAsk: busy ? null : _ask,
                    onDownload: hasConverted ? _downloadSingleRow : null,
                    answer: vm.answer,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopActions extends StatelessWidget {
  const _TopActions({
    required this.converting,
    required this.hasConverted,
    required this.onPickAndConvert,
  });

  final bool converting;
  final bool hasConverted;
  final VoidCallback onPickAndConvert;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: converting ? null : onPickAndConvert,
          icon: converting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: Text(converting ? "Converting..." : "Upload PDF"),
        ),
        const SizedBox(width: 12),
        if (hasConverted)
          Text("✅ Ready", style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.visible, required this.text});

  final bool visible;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      // keeps layout stable: show a small placeholder box instead of Spacer()
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Text(
          "Upload a PDF to generate a preview.",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260), // ✅ prevents giant Expanded jumps
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Single-row CSV Preview", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  text,
                  style: const TextStyle(fontFamily: "monospace", fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AskPanel extends StatelessWidget {
  const _AskPanel({
    required this.controller,
    required this.asking,
    required this.canDownload,
    required this.onAsk,
    required this.onDownload,
    required this.answer,
  });

  final TextEditingController controller;
  final bool asking;
  final bool canDownload;
  final VoidCallback? onAsk;
  final VoidCallback? onDownload;
  final String? answer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => onAsk?.call(),
          decoration: const InputDecoration(
            labelText: "Ask a question",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: asking ? null : onAsk,
                child: asking
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("Ask"),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: canDownload ? onDownload : null,
              icon: const Icon(Icons.download),
              label: const Text("Download"),
            ),
          ],
        ),
        if (answer != null && answer!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(answer!, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ],
    );
  }
}
