// lib/ui/widgets/chat_widgets.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/syllabus_vm.dart'; // ChatMessage, ChatRole, SyllabusViewModel
import '../ui_scale.dart';

// =============================
// MESSAGE BUBBLES
// =============================
class ElegantMessage extends StatelessWidget {
  const ElegantMessage({
    super.key,
    required this.ui,
    required this.message,
    required this.showAvatar,
    required this.compactTop,
    required this.compactBottom,
  });

  final UiScale ui;
  final ChatMessage message;
  final bool showAvatar;
  final bool compactTop;
  final bool compactBottom;

  String _time(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final isUser = message.role == ChatRole.user;
    final isSystem = message.role == ChatRole.system;
    final isStatus = message.role == ChatRole.status;

    if (isSystem) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: ui.px(10)),
        child: Center(
          child: Container(
            padding: EdgeInsets.all(ui.px(14)),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(ui.innerRadius),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: cs.primary, size: ui.icon),
                SizedBox(width: ui.px(10)),
                Expanded(
                  child: MiniMarkdownText(
                    text: message.text,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.84),
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      fontSize: ui.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isStatus) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: ui.px(10)),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TypingPill(ui: ui, label: message.text),
        ),
      );
    }

    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    final bubbleBg = isUser
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, cs.primary.withValues(alpha: 0.80)],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.surface, cs.surfaceContainerHighest.withValues(alpha: 0.45)],
          );

    final fg = isUser ? cs.onPrimary : cs.onSurface.withValues(alpha: 0.88);

    final radius = isUser
        ? BorderRadius.only(
            topLeft: Radius.circular(ui.bubbleRadius),
            topRight: Radius.circular(ui.bubbleRadius),
            bottomLeft: Radius.circular(ui.bubbleRadius),
            bottomRight: Radius.circular(ui.px(8)),
          )
        : BorderRadius.only(
            topLeft: Radius.circular(compactTop ? ui.px(12) : ui.bubbleRadius),
            topRight: Radius.circular(ui.bubbleRadius),
            bottomLeft: Radius.circular(compactBottom ? ui.px(12) : ui.px(8)),
            bottomRight: Radius.circular(ui.bubbleRadius),
          );

    return Align(
      alignment: align,
      child: Padding(
        padding: EdgeInsets.only(
          top: compactTop ? ui.px(3) : ui.px(10),
          bottom: compactBottom ? ui.px(3) : ui.px(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isUser) ...[
              SizedBox(
                width: ui.px(34),
                child: showAvatar
                    ? Avatar(
                        ui: ui,
                        bg: cs.primary.withValues(alpha: 0.14),
                        fg: cs.primary,
                        icon: Icons.auto_awesome_rounded,
                      )
                    : SizedBox(height: ui.px(34)),
              ),
              SizedBox(width: ui.px(8)),
            ] else
              const Spacer(),
            Flexible(
              child: LayoutBuilder(
                builder: (context, c) {
                  final maxW = ui.bubbleMaxWidth(c.maxWidth, isUser: isUser);
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxW),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(ui.bubblePadH, ui.bubblePadV, ui.px(10), ui.px(10)),
                      decoration: BoxDecoration(
                        gradient: bubbleBg,
                        borderRadius: radius,
                        border: isUser ? null : Border.all(color: cs.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isUser ? 0.09 : 0.05),
                            blurRadius: ui.px(22),
                            offset: Offset(0, ui.px(12)),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MiniMarkdownText(
                            text: message.text,
                            style: TextStyle(
                              color: fg,
                              fontSize: ui.body,
                              height: 1.33,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: ui.px(8)),
                          Wrap(
                            spacing: ui.px(8),
                            runSpacing: ui.px(6),
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                _time(message.createdAt),
                                style: TextStyle(
                                  color: fg.withValues(alpha: isUser ? 0.75 : 0.55),
                                  fontSize: ui.px(11.5),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              MiniIconButton(
                                ui: ui,
                                tooltip: "Copy",
                                icon: Icons.copy_rounded,
                                onTap: () async {
                                  await Clipboard.setData(ClipboardData(text: message.text));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text("Copied"),
                                        duration: const Duration(milliseconds: 850),
                                        backgroundColor: cs.inverseSurface,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (isUser) ...[
              SizedBox(width: ui.px(8)),
              SizedBox(
                width: ui.px(34),
                child: Avatar(
                  ui: ui,
                  bg: const Color(0xFF6D5EF6),
                  fg: Colors.white,
                  icon: Icons.person_rounded,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.ui, required this.bg, required this.fg, required this.icon});
  final UiScale ui;
  final Color bg;
  final Color fg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: ui.px(16),
      backgroundColor: bg,
      child: Icon(icon, color: fg, size: ui.px(18)),
    );
  }
}

class MiniIconButton extends StatelessWidget {
  const MiniIconButton({super.key, required this.ui, required this.tooltip, required this.icon, required this.onTap});
  final UiScale ui;
  final String tooltip;
  final IconData icon;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(ui.px(10)),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(ui.px(6)),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.50),
            borderRadius: BorderRadius.circular(ui.px(10)),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Icon(icon, size: ui.smallIcon, color: cs.onSurface.withValues(alpha: 0.62)),
        ),
      ),
    );
  }
}

// =============================
// HERO CARD (Analyze first)
// =============================
class AnalyzeFirstCard extends StatelessWidget {
  const AnalyzeFirstCard({
    super.key,
    required this.ui,
    required this.vm,
    required this.onAnalyze,
  });

  final UiScale ui;
  final SyllabusViewModel vm;
  final Future<void> Function() onAnalyze;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final hasPdf = vm.hasPdf;
    final analyzing = vm.converting; // your VM flag
    final ready = vm.hasConverted;

    final title = analyzing
        ? "Analyzing your syllabus…"
        : (ready ? "Syllabus ready" : "Analyze your syllabus first");
    final subtitle = analyzing
        ? "Extracting course structure so Q&A is accurate."
        : (ready ? "You can start chatting below." : "Upload a PDF, then analyze. After that, you can ask questions.");

    return Container(
      margin: EdgeInsets.only(bottom: ui.px(14)),
      padding: EdgeInsets.all(ui.px(14)),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(ui.px(20)),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: ui.px(26),
            offset: Offset(0, ui.px(14)),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: ui.px(52),
            height: ui.px(52),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ui.px(16)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primary, cs.primary.withValues(alpha: 0.72)],
              ),
            ),
            child: Icon(Icons.menu_book_rounded, color: Colors.white, size: ui.px(24)),
          ),
          SizedBox(width: ui.px(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: ui.px(16.5)),
                ),
                SizedBox(height: ui.px(6)),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    fontSize: ui.px(13.2),
                  ),
                ),
                SizedBox(height: ui.px(12)),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [cs.primary, cs.primary.withValues(alpha: 0.80)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(ui.px(16)),
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.18),
                              blurRadius: ui.px(18),
                              offset: Offset(0, ui.px(10)),
                            ),
                          ],
                        ),
                        child: TextButton.icon(
                          onPressed: (!hasPdf || analyzing || ready) ? null : onAnalyze,
                          icon: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: ui.px(18)),
                          label: Text(
                            analyzing
                                ? "Analyzing…"
                                : (ready ? "Analyzed" : "Analyze PDF"),
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: ui.px(14)),
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: ui.px(12)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ui.px(16))),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================
// Minimal markdown renderer for **bold**
// =============================
class MiniMarkdownText extends StatelessWidget {
  const MiniMarkdownText({super.key, required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(children: _parseBold(text, style)),
      selectionControls: materialTextSelectionControls,
    );
  }

  List<InlineSpan> _parseBold(String input, TextStyle base) {
    final spans = <InlineSpan>[];
    final re = RegExp(r"\*\*(.*?)\*\*");
    var index = 0;

    for (final m in re.allMatches(input)) {
      if (m.start > index) {
        spans.add(TextSpan(text: input.substring(index, m.start), style: base));
      }
      final boldText = m.group(1) ?? "";
      spans.add(TextSpan(text: boldText, style: base.copyWith(fontWeight: FontWeight.w900)));
      index = m.end;
    }

    if (index < input.length) {
      spans.add(TextSpan(text: input.substring(index), style: base));
    }

    return spans;
  }
}

// =============================
// Typing pill
// =============================
class TypingPill extends StatefulWidget {
  const TypingPill({super.key, required this.ui, required this.label});
  final UiScale ui;
  final String label;

  @override
  State<TypingPill> createState() => _TypingPillState();
}

class _TypingPillState extends State<TypingPill> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ui = widget.ui;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: ui.px(12), vertical: ui.px(9)),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.label, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900, fontSize: ui.px(13))),
          SizedBox(width: ui.px(10)),
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final v = _c.value;
              var dots = (v * 3).floor() + 1;
              if (dots > 3) dots = 3;
              return Text(
                "." * dots,
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900, fontSize: ui.px(13)),
              );
            },
          ),
        ],
      ),
    );
  }
}

// =============================
// Composer (bottom, ChatGPT-style)
// =============================
class Composer extends StatefulWidget {
  const Composer({super.key, required this.ui, required this.vm});
  final UiScale ui;
  final SyllabusViewModel vm;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  @override
  void initState() {
    super.initState();
    widget.vm.inputCtrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.vm.inputCtrl.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final ui = widget.ui;
    final cs = Theme.of(context).colorScheme;

    const sendIntent = _SendIntent();
    final canSend = vm.inputCtrl.text.trim().isNotEmpty && !vm.asking && vm.hasConverted;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.enter): sendIntent,
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SendIntent: CallbackAction<_SendIntent>(
            onInvoke: (intent) async {
              final pressed = HardwareKeyboard.instance.logicalKeysPressed;
              final shift = pressed.contains(LogicalKeyboardKey.shiftLeft) || pressed.contains(LogicalKeyboardKey.shiftRight);
              if (shift) return null;
              if (!vm.inputFocus.hasFocus) return null;

              await vm.sendQuestion();
              vm.inputFocus.requestFocus();
              return null;
            },
          ),
        },
        child: Container(
          padding: EdgeInsets.fromLTRB(ui.px(14), ui.px(10), ui.px(14), ui.px(14)),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.97),
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.50),
                    borderRadius: BorderRadius.circular(ui.innerRadius),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: TextField(
                    focusNode: vm.inputFocus,
                    controller: vm.inputCtrl,
                    enabled: !vm.asking,
                    minLines: 1,
                    maxLines: 6,
                    style: TextStyle(fontSize: ui.px(14), fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: vm.hasConverted ? "Ask anything…" : "Analyze the PDF first to enable chat…",
                      hintStyle: TextStyle(
                        fontSize: ui.hint,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: ui.px(14), vertical: ui.px(12)),
                    ),
                  ),
                ),
              ),
              SizedBox(width: ui.px(10)),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: canSend ? 1.0 : 0.55,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primary, cs.primary.withValues(alpha: 0.80)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(ui.px(16)),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.22),
                        blurRadius: ui.px(18),
                        offset: Offset(0, ui.px(10)),
                      ),
                    ],
                  ),
                  child: IconButton(
                    tooltip: "Send",
                    onPressed: canSend ? () async => vm.sendQuestion() : null,
                    icon: Icon(Icons.send_rounded, color: Colors.white, size: ui.px(18)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}
