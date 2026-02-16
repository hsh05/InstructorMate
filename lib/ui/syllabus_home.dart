import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app/state/syllabus_vm.dart';

class SyllabusHome extends StatefulWidget {
  const SyllabusHome({super.key, required this.vm});
  final SyllabusViewModel vm;

  @override
  State<SyllabusHome> createState() => _SyllabusHomeState();
}

class _SyllabusHomeState extends State<SyllabusHome> {
  bool showPreview = false;

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final size = MediaQuery.of(context).size;
    final ui = UiScale(size.width, size.height);

    return AnimatedBuilder(
      animation: vm,
      builder: (_, __) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F1FF),
          body: Column(
            children: [
              _topBar(vm, ui),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _chatSection(vm, ui)),
                    if (ui.isDesktop)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        width: showPreview ? 520 : 0,
                        child: showPreview
                            ? _previewSlider(vm, ui)
                            : const SizedBox(),
                      ),
                  ],
                ),
              ),
              _composer(vm, ui),
            ],
          ),
        );
      },
    );
  }

  // ================= TOP BAR =================

  Widget _topBar(SyllabusViewModel vm, UiScale ui) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(ui.px(20)),
        child: Row(
          children: [
            const Text(
              "InstructorMate",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (vm.hasConverted)
              IconButton(
                icon: const Icon(Icons.visibility_outlined),
                onPressed: () {
                  if (ui.isDesktop) {
                    setState(() => showPreview = !showPreview);
                  } else {
                    _openMobilePreview(vm, ui);
                  }
                },
              ),
            IconButton(
              icon: const Icon(Icons.upload_file),
              onPressed: vm.isBusy ? null : () => vm.pickPdf(),
            ),
          ],
        ),
      ),
    );
  }

  // ================= CHAT =================

  Widget _chatSection(SyllabusViewModel vm, UiScale ui) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ui.px(24)),
      child: Column(
        children: [
          if (!vm.hasConverted)
            Container(
              margin: EdgeInsets.only(bottom: ui.px(20)),
              padding: EdgeInsets.all(ui.px(18)),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ui.cardRadius),
              ),
              child: const Text(
                "Upload a syllabus PDF to begin.",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: vm.scrollCtrl,
              itemCount:
                  vm.messages.length + (vm.asking || vm.converting ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= vm.messages.length) {
                  return _loadingBubble(ui);
                }

                final msg = vm.messages[i];

                if (msg.role == ChatRole.status ||
                    msg.role == ChatRole.system) {
                  return const SizedBox(); // remove status visually
                }

                return _bubble(msg, ui);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage msg, UiScale ui) {
    final isUser = msg.role == ChatRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: ui.px(14)),
        padding: EdgeInsets.all(ui.px(14)),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  colors: [Color(0xFF7C6CF6), Color(0xFF9B8CFF)],
                )
              : const LinearGradient(
                  colors: [Colors.white, Color(0xFFF3F0FA)],
                ),
          borderRadius: BorderRadius.circular(ui.bubbleRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _loadingBubble(UiScale ui) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: ui.px(14)),
        padding: EdgeInsets.symmetric(
          horizontal: ui.px(18),
          vertical: ui.px(14),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ui.bubbleRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF7C6CF6),
              ),
            ),
            SizedBox(width: 12),
            Text(
              "Processing...",
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  // ================= COMPOSER =================

  Widget _composer(SyllabusViewModel vm, UiScale ui) {
    return Container(
      padding: EdgeInsets.all(ui.px(20)),
      color: Colors.white,
      child: Column(
        children: [
          if (vm.hasConverted)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip("When is Quiz 1?", vm),
                  SizedBox(width: ui.px(10)),
                  _chip("Grading breakdown?", vm),
                  SizedBox(width: ui.px(10)),
                  _chip("Main topics?", vm),
                ],
              ),
            ),
          SizedBox(height: ui.px(14)),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: vm.inputCtrl,
                  focusNode: vm.inputFocus,
                  decoration: InputDecoration(
                    hintText: "Ask anything...",
                    filled: true,
                    fillColor: const Color(0xFFF3F0FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SizedBox(width: ui.px(12)),
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C6CF6), Color(0xFF9B8CFF)],
                  ),
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed:
                      vm.asking || !vm.hasConverted ? null : vm.sendQuestion,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, SyllabusViewModel vm) {
    return InkWell(
      onTap: () => vm.sendQuick(text),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEDE9FF),
          borderRadius: BorderRadius.circular(999),
        ),
        child:
            Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ================= PREVIEW =================

Widget _previewSlider(SyllabusViewModel vm, UiScale ui) {
  final raw = vm.preview?.text ?? "";

  return Container(
    width: double.infinity,
    height: double.infinity,
    padding: EdgeInsets.all(ui.px(24)),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(ui.cardRadius),
        bottomLeft: Radius.circular(ui.cardRadius),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 30,
          offset: const Offset(-4, 0),
        )
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Generated CSV",
          style: TextStyle(
            fontSize: ui.px(18),
            fontWeight: FontWeight.w800,
          ),
        ),

        SizedBox(height: ui.px(16)),

        // CSV VIEW
        Expanded(
          child: Container(
            padding: EdgeInsets.all(ui.px(14)),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F5FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE6E0FF)),
            ),
            child: raw.trim().isEmpty
                ? Center(
                    child: Text(
                      "No CSV generated yet.",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withOpacity(0.6),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: SelectableText(
                      raw,
                      style: TextStyle(
                        fontFamily: "monospace",
                        fontSize: ui.px(13),
                        height: 1.5,
                        color: Colors.black.withOpacity(0.85),
                      ),
                    ),
                  ),
          ),
        ),

        SizedBox(height: ui.px(18)),

        // DOWNLOAD BUTTON
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C6CF6), Color(0xFF9B8CFF)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ElevatedButton.icon(
            onPressed: () => vm.downloadCsv(),
            icon: const Icon(Icons.download, color: Colors.white),
            label: const Text(
              "Download CSV",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: EdgeInsets.symmetric(vertical: ui.px(14)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}


void _openMobilePreview(SyllabusViewModel vm, UiScale ui) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent, // important
    builder: (_) => ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(24), // rounded top
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.80,
        width: double.infinity,
        child: _previewSlider(vm, ui),
      ),
    ),
  );
}


}

// ================= SCALE =================

class UiScale {
  UiScale(this.w, this.h);
  final double w;
  final double h;

  bool get isDesktop => w >= 1024;

  double get _s =>
      (math.min(w, h) / 430).clamp(0.92, 1.18).toDouble();

  double px(double v) => v * _s;

  double get cardRadius => px(22);
  double get bubbleRadius => px(18);
}
