// lib/ui/syllabus_home.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/state/syllabus_vm.dart';
import 'widgets/top_bar.dart';
import 'widgets/chat_widgets.dart';

class SyllabusHome extends StatefulWidget {
  const SyllabusHome({super.key, required this.vm});
  final SyllabusViewModel vm;

  @override
  State<SyllabusHome> createState() => _SyllabusHomeState();
}

class _SyllabusHomeState extends State<SyllabusHome> {
  SyllabusViewModel get vm => widget.vm;

  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  Future<void> _openCsvPreviewSheet() async {
    await vm.viewCsv();
    if (!mounted) return;
    final preview = vm.preview;
    if (preview == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => CsvPreviewSheet(
        title: preview.title,
        csvText: preview.text,
        onDownload: (vm.mainCsvPath == null) ? null : vm.downloadCsv,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        final hookup = Theme.of(context);
        final cs = hookup.colorScheme;

        final size = MediaQuery.of(context).size;
        final ui = UiScale(size.width, size.height);

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFF7F2FF),
                        cs.primary.withValues(alpha: 0.06),
                        const Color(0xFFFCFAFF),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.15, -0.85),
                        radius: 1.2,
                        colors: [
                          Colors.white.withValues(alpha: 0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(ui.pagePad, ui.topPad, ui.pagePad, ui.pagePad),
                  child: Column(
                    children: [
                      TopBar(
                        ui: ui,
                        title: "Syllabus Q&A",
                        fileChipText: vm.hasPdf ? vm.fileNameShort : null,
                        stage: vm.stage,
                        stageProgress: vm.stageProgress,
                        busy: vm.isBusy,
                        subtitle: vm.hasConverted
                            ? "Ready • Ask anything"
                            : (vm.hasPdf ? "PDF selected • Convert to enable Q&A" : "Upload a syllabus PDF to begin"),
                        onUpload: vm.picking ? null : vm.pickPdf,
                        onConvert: (!vm.hasPdf || vm.converting) ? null : vm.convertPdf,
                        onPreview: (!vm.hasConverted || vm.viewing) ? null : _openCsvPreviewSheet,
                        onDownload: (!vm.hasConverted) ? null : vm.downloadCsv,
                        onClear: vm.isBusy ? null : vm.clearEverything,
                      ),
                      SizedBox(height: ui.px(12)),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(ui.cardRadius),
                            border: Border.all(color: cs.outlineVariant),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: ui.px(34),
                                offset: Offset(0, ui.px(16)),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(ui.cardRadius),
                            child: Column(
                              children: [
                                Expanded(
                                  child: Scrollbar(
                                    controller: vm.scrollCtrl,
                                    thumbVisibility: kIsWeb,
                                    child: ListView.builder(
                                      controller: vm.scrollCtrl,
                                      padding: EdgeInsets.fromLTRB(ui.px(14), ui.px(14), ui.px(14), ui.px(18)),
                                      itemCount: vm.messages.length,
                                      itemBuilder: (context, i) {
                                        final m = vm.messages[i];
                                        final prev = (i > 0) ? vm.messages[i - 1] : null;
                                        final next = (i < vm.messages.length - 1) ? vm.messages[i + 1] : null;

                                        final samePrev = prev != null && prev.role == m.role;
                                        final sameNext = next != null && next.role == m.role;

                                        return ElegantMessage(
                                          ui: ui,
                                          message: m,
                                          showAvatar: m.role == ChatRole.assistant && !samePrev,
                                          compactTop: m.role == ChatRole.assistant && samePrev,
                                          compactBottom: m.role == ChatRole.assistant && sameNext,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                if (vm.hasConverted && !vm.asking)
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(ui.px(12), 0, ui.px(12), ui.px(8)),
                                    child: QuickPrompts(ui: ui, onPick: vm.sendQuick),
                                  ),
                                Composer(ui: ui, vm: vm),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
