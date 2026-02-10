// lib/ui/widgets/top_bar.dart
import 'package:flutter/material.dart';
import '../../app/state/syllabus_vm.dart';

// =============================
// RESPONSIVE SCALE (shared)
// =============================
class UiScale {
  UiScale(this.w, this.h);

  final double w;
  final double h;

  double get _base => w < h ? w : h;
  double get s => (_base / 420.0).clamp(0.92, 1.18);
  double px(double v) => v * s;

  double get pagePad => px(16);
  double get topPad => px(12);
  double get cardRadius => px(24);
  double get innerRadius => px(18);
  double get bubbleRadius => px(18);
  double get bubblePadH => px(14);
  double get bubblePadV => px(12);
  double get icon => px(20);
  double get smallIcon => px(14);
  double get title => px(20);
  double get body => px(14.6);
  double get hint => px(12.5);
  double get chip => px(12);
  double get stepDot => px(26);

  double bubbleMaxWidth(double available, {required bool isUser}) {
    final fraction = isUser ? 0.72 : 0.78;
    final cap = px(720);
    final target = available * fraction;
    return target.clamp(0.0, cap);
  }
}

// =============================
// TOP BAR
// =============================
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.ui,
    required this.title,
    required this.subtitle,
    required this.fileChipText,
    required this.stage,
    required this.stageProgress,
    required this.busy,
    required this.onUpload,
    required this.onConvert,
    required this.onPreview,
    required this.onDownload,
    required this.onClear,
  });

  final UiScale ui;
  final String title;
  final String subtitle;
  final String? fileChipText;

  final FlowStage stage;
  final double stageProgress;
  final bool busy;

  final Future<void> Function()? onUpload;
  final Future<void> Function()? onConvert;
  final Future<void> Function()? onPreview;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final actions = ActionCluster(
      ui: ui,
      items: [
        ActionItem(tooltip: "Upload PDF", icon: Icons.upload_file_rounded, onTap: onUpload),
        ActionItem(tooltip: "Convert", icon: Icons.autorenew_rounded, onTap: onConvert),
        ActionItem(tooltip: "Preview CSV", icon: Icons.table_view_rounded, onTap: onPreview),
        ActionItem(tooltip: "Download CSV", icon: Icons.download_rounded, onTap: onDownload),
        ActionItem(tooltip: "Clear all", icon: Icons.delete_outline_rounded, onTap: onClear),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;

        final header = Row(
          children: [
            BrandMark(ui: ui, color: cs.primary),
            SizedBox(width: ui.px(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.35,
                            fontSize: ui.title,
                          ),
                        ),
                      ),
                      if (fileChipText != null) ...[
                        SizedBox(width: ui.px(10)),
                        FileChip(ui: ui, text: fileChipText!),
                      ],
                    ],
                  ),
                  SizedBox(height: ui.px(4)),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.62),
                      fontWeight: FontWeight.w700,
                      fontSize: ui.px(13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!narrow)
              Row(
                children: [
                  Expanded(child: header),
                  SizedBox(width: ui.px(10)),
                  actions,
                ],
              )
            else ...[
              header,
              SizedBox(height: ui.px(10)),
              actions,
            ],
            SizedBox(height: ui.px(10)),
            ProgressStepper(ui: ui, stage: stage, progress: stageProgress, busy: busy),
          ],
        );
      },
    );
  }
}

class ActionItem {
  const ActionItem({required this.tooltip, required this.icon, required this.onTap});
  final String tooltip;
  final IconData icon;
  final Future<void> Function()? onTap;
}

class ActionCluster extends StatelessWidget {
  const ActionCluster({super.key, required this.ui, required this.items});
  final UiScale ui;
  final List<ActionItem> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.all(ui.px(6)),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(ui.innerRadius),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((it) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: ui.px(2)),
            child: Tooltip(
              message: it.tooltip,
              child: IconButton(
                onPressed: it.onTap == null ? null : () => it.onTap!.call(),
                icon: Icon(it.icon, size: ui.icon),
                style: IconButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                  foregroundColor: cs.onSurface.withValues(alpha: 0.80),
                  disabledForegroundColor: cs.onSurface.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ui.px(14))),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class ProgressStepper extends StatelessWidget {
  const ProgressStepper({
    super.key,
    required this.ui,
    required this.stage,
    required this.progress,
    required this.busy,
  });

  final UiScale ui;
  final FlowStage stage;
  final double progress;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final index = switch (stage) {
      FlowStage.upload => 0,
      FlowStage.convert => 1,
      FlowStage.ask => 2,
    };

    String badgeText() {
      if (busy) {
        if (stage == FlowStage.convert) return "Converting…";
        if (stage == FlowStage.ask) return "Answering…";
        return "Working…";
      }
      if (stage == FlowStage.upload) return "Upload";
      if (stage == FlowStage.convert) return "Convert";
      return "Ask";
    }

    return Container(
      padding: EdgeInsets.fromLTRB(ui.px(14), ui.px(12), ui.px(14), ui.px(12)),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(ui.innerRadius),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              StepDot(ui: ui, label: "Upload", active: index >= 0, done: index > 0),
              Expanded(child: StepLine(ui: ui, active: index >= 1)),
              StepDot(ui: ui, label: "Convert", active: index >= 1, done: index > 1),
              Expanded(child: StepLine(ui: ui, active: index >= 2)),
              StepDot(ui: ui, label: "Ask", active: index >= 2, done: false),
              SizedBox(width: ui.px(10)),
              Badge(ui: ui, text: badgeText()),
            ],
          ),
          SizedBox(height: ui.px(10)),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) {
                return LinearProgressIndicator(
                  value: v,
                  minHeight: ui.px(8),
                  backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class StepDot extends StatelessWidget {
  const StepDot({super.key, required this.ui, required this.label, required this.active, required this.done});
  final UiScale ui;
  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color bg;
    final IconData icon;

    if (done) {
      bg = cs.primary;
      icon = Icons.check_rounded;
    } else if (active) {
      bg = cs.primary.withValues(alpha: 0.22);
      icon = Icons.circle;
    } else {
      bg = cs.outlineVariant.withValues(alpha: 0.65);
      icon = Icons.circle_outlined;
    }

    return Column(
      children: [
        Container(
          width: ui.stepDot,
          height: ui.stepDot,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Icon(icon, size: ui.px(14), color: done ? cs.onPrimary : cs.primary),
        ),
        SizedBox(height: ui.px(6)),
        Text(
          label,
          style: TextStyle(
            fontSize: ui.px(11),
            fontWeight: FontWeight.w900,
            color: active ? cs.onSurface.withValues(alpha: 0.78) : cs.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}

class StepLine extends StatelessWidget {
  const StepLine({super.key, required this.ui, required this.active});
  final UiScale ui;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: ui.px(2),
      margin: EdgeInsets.symmetric(horizontal: ui.px(8)),
      decoration: BoxDecoration(
        color: active ? cs.primary.withValues(alpha: 0.6) : cs.outlineVariant,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class Badge extends StatelessWidget {
  const Badge({super.key, required this.ui, required this.text});
  final UiScale ui;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: ui.px(10), vertical: ui.px(6)),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900, fontSize: ui.px(12)),
      ),
    );
  }
}

class FileChip extends StatelessWidget {
  const FileChip({super.key, required this.ui, required this.text});
  final UiScale ui;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: ui.px(10), vertical: ui.px(6)),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.picture_as_pdf_rounded, size: ui.px(16), color: cs.primary),
          SizedBox(width: ui.px(6)),
          Text(text, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900, fontSize: ui.chip)),
        ],
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.ui, required this.color});
  final UiScale ui;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ui.px(38),
      height: ui.px(38),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ui.px(13)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.70)],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.16),
            blurRadius: ui.px(18),
            offset: Offset(0, ui.px(10)),
          ),
        ],
      ),
      child: Icon(Icons.school_rounded, color: Colors.white, size: ui.px(20)),
    );
  }
}
