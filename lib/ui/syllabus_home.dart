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
        final theme = Theme.of(context);
        final cs = theme.colorScheme;

        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;

            // ✅ Breakpoints
            final isMobile = w < 600;
            final isTablet = w >= 600 && w < 1024;
            final isDesktop = w >= 1024;

            // ✅ Build UiScale from *actual* available constraints (not just full screen)
            final ui = UiScale(w, h);

            // ✅ Responsive page padding to avoid "crowded" look on medium widths
            final pagePad = isDesktop ? ui.px(20) : (isTablet ? ui.px(14) : ui.px(12));
            final topPad = isDesktop ? ui.px(14) : ui.px(10);

            // ✅ Responsive chat list padding (this is a BIG part of the crowded feel)
            final listPad = EdgeInsets.fromLTRB(
              isDesktop ? ui.px(16) : ui.px(12),
              isDesktop ? ui.px(16) : ui.px(12),
              isDesktop ? ui.px(16) : ui.px(12),
              isDesktop ? ui.px(20) : ui.px(16),
            );

            // ✅ Slightly reduce card radius on narrow screens (looks less “squeezed”)
            final cardRadius = isDesktop ? ui.cardRadius : ui.px(18);

            // ✅ Optional: constrain content width on desktop so it doesn’t stretch too wide
            final maxContentWidth = isDesktop ? 1100.0 : double.infinity;

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
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxContentWidth),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(pagePad, topPad, pagePad, pagePad),
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
                                    : (vm.hasPdf
                                        ? "PDF selected • Convert to enable Q&A"
                                        : "Upload a syllabus PDF to begin"),
                                onUpload: vm.picking ? null : vm.pickPdf,
                                onConvert: (!vm.hasPdf || vm.converting) ? null : vm.convertPdf,
                                onPreview: (!vm.hasConverted || vm.viewing) ? null : _openCsvPreviewSheet,
                                onDownload: (!vm.hasConverted) ? null : vm.downloadCsv,
                                onClear: vm.isBusy ? null : vm.clearEverything,
                              ),
                              SizedBox(height: ui.px(isMobile ? 10 : 12)),
                              Expanded(
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: cs.surface.withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(cardRadius),
                                    border: Border.all(color: cs.outlineVariant),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: ui.px(isMobile ? 20 : 34),
                                        offset: Offset(0, ui.px(isMobile ? 10 : 16)),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(cardRadius),
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: Scrollbar(
                                            controller: vm.scrollCtrl,
                                            thumbVisibility: kIsWeb,
                                            child: ListView.builder(
                                              controller: vm.scrollCtrl,
                                              padding: listPad,
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
                                            padding: EdgeInsets.fromLTRB(
                                              ui.px(isMobile ? 10 : 12),
                                              0,
                                              ui.px(isMobile ? 10 : 12),
                                              ui.px(isMobile ? 6 : 8),
                                            ),
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
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
