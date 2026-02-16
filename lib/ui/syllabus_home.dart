import 'dart:ui';
import 'package:flutter/material.dart';
import '../app/state/syllabus_vm.dart';
import 'widgets/chat_widgets.dart';
import 'ui_scale.dart';


class SyllabusHome extends StatefulWidget {
  const SyllabusHome({super.key, required this.vm});
  final SyllabusViewModel vm;

  @override
  State<SyllabusHome> createState() => _SyllabusHomeState();
}

class _SyllabusHomeState extends State<SyllabusHome>
    with TickerProviderStateMixin {
  bool showPreview = false;

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;

    return AnimatedBuilder(
      animation: vm,
      builder: (_, __) {
        final isDesktop = MediaQuery.of(context).size.width > 1000;

        return Scaffold(
          backgroundColor: const Color(0xFFF6F4FB),
          body: Stack(
            children: [
              // ================= BACKGROUND GRADIENT =================
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFFF6F4FB),
                      Color(0xFFECE8FA),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),

              // ================= MAIN CONTENT =================
              SafeArea(
                child: Column(
                  children: [
                    _floatingTopBar(vm),
                    Expanded(
                      child: isDesktop
                          ? Row(
                              children: [
                                Expanded(child: _chatArea(vm)),
                                if (vm.hasConverted && showPreview)
                                  SizedBox(
                                    width: 520,
                                    child: _previewCard(vm),
                                  ),
                              ],
                            )
                          : _chatArea(vm),
                    ),
                    _composer(vm),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================
  // FLOATING BLURRED TOP BAR
  // =========================================================

  Widget _floatingTopBar(SyllabusViewModel vm) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.65),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: Colors.white.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.school, size: 22),
                const SizedBox(width: 12),
                const Text(
                  "Syllabus Q&A",
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
                const Spacer(),

                if (vm.hasConverted)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        showPreview = !showPreview;
                      });
                    },
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(showPreview
                        ? "Hide Preview"
                        : "View Preview"),
                  ),

                IconButton(
                  icon: const Icon(Icons.upload_file),
                  onPressed: vm.isBusy
                      ? null
                      : () async => vm.pickPdf(),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: vm.isBusy
                      ? null
                      : () => vm.clearEverything(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // CHAT AREA (dominant)
  // =========================================================

 Widget _chatArea(SyllabusViewModel vm) {
  final size = MediaQuery.of(context).size;
  final ui = UiScale(size.width, size.height);

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: ListView.builder(
      controller: vm.scrollCtrl,
      padding: const EdgeInsets.only(bottom: 140),
      itemCount: vm.messages.length,
      itemBuilder: (_, i) {
        final message = vm.messages[i];
        final previous = i > 0 ? vm.messages[i - 1] : null;

        final grouped =
            previous != null && previous.role == message.role;

        return AnimatedSlide(
          duration: const Duration(milliseconds: 250),
          offset: const Offset(0, 0.05),
          child: ElegantMessage(
            ui: ui, // ✅ FIXED
            message: message,
            showAvatar: !grouped,
            compactTop: grouped,
            compactBottom: false,
          ),
        );
      },
    ),
  );
}

  // =========================================================
  // COMPOSER (ChatGPT style)
  // =========================================================

  Widget _composer(SyllabusViewModel vm) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (vm.hasConverted)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 8,
                children: [
                  _suggested("When is Quiz 1?", vm),
                  _suggested("Grading breakdown", vm),
                  _suggested("Main topics", vm),
                ],
              ),
            ),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: vm.inputCtrl,
                  focusNode: vm.inputFocus,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: "Ask anything...",
                    filled: true,
                    fillColor: const Color(0xFFF2F0FA),
                    contentPadding:
                        const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF7B6CF6),
                      Color(0xFF9A88FF),
                    ],
                  ),
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_upward,
                      color: Colors.white),
                  onPressed:
                      vm.asking ? null : () => vm.sendQuestion(),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggested(String text, SyllabusViewModel vm) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => vm.sendQuick(text),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEDE9FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ),
    );
  }

  // =========================================================
  // STRUCTURED PREVIEW CARD
  // =========================================================

  Widget _previewCard(SyllabusViewModel vm) {
    if (vm.preview == null ||
        vm.preview!.text.trim().isEmpty) {
      return const Center(
        child: Text("No structured preview available."),
      );
    }

    final lines = vm.preview!.text.split('\n');
    final Map<String, String> grouped = {};

    for (var line in lines) {
      if (!line.contains(',')) continue;
      final index = line.indexOf(',');
      grouped[line.substring(0, index)] =
          line.substring(index + 1);
    }

    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
          )
        ],
      ),
      child: ListView(
        children: [
          const Text(
            "Preview of Selected Syllabus",
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),

          ...grouped.entries.map((e) {
            return Padding(
              padding:
                  const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(e.key,
                      style: const TextStyle(
                          fontWeight:
                              FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(e.value),
                ],
              ),
            );
          }),

          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: () => vm.downloadCsv(),
            icon: const Icon(Icons.download),
            label: const Text("Download CSV"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
