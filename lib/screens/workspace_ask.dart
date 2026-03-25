// lib/ui/workspace_ask.dart

import 'package:flutter/material.dart';
import '../config/app_colors.dart';

// ─── TAB 4 — Ask AI ───────────────────────────────────────────────────────────
class AskTab extends StatelessWidget {
  const AskTab({
    super.key,
    required this.chat,
    required this.ctrl,
    required this.scrollCtrl,
    required this.asking,
    required this.onAsk,
  });
  final List<ChatMsg> chat;
  final TextEditingController ctrl;
  final ScrollController scrollCtrl;
  final bool asking;
  final Future<void> Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: chat.isEmpty
            ? AskEmptyState(onAsk: onAsk)
            : ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(14),
                itemCount: chat.length + (asking ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == chat.length) return const TypingIndicator();
                  return ChatBubble(msg: chat[i]);
                },
              ),
      ),
      Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(color: AppColors.ink, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ask about the syllabus…',
                hintStyle: const TextStyle(color: AppColors.inkLight),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                border: OutlineInputBorder(
                    borderRadius: AppColors.r20, borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              ),
              onSubmitted: onAsk,
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: asking ? null : () => onAsk(ctrl.text),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: asking ? AppColors.inkLight : AppColors.primary,
                borderRadius: AppColors.r20,
              ),
              child: asking
                  ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ─── Ask Empty State ──────────────────────────────────────────────────────────
class AskEmptyState extends StatelessWidget {
  const AskEmptyState({super.key, required this.onAsk});
  final Future<void> Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    final suggestions = [
      'What is the grading breakdown?',
      'What are the attendance rules?',
      'What textbooks are required?',
      'When is the midterm?',
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6747B0), Color(0xFF9B78E0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: AppColors.r20,
          ),
          child: Column(children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: AppColors.r16,
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 26),
            ),
            const SizedBox(height: 12),
            const Text('Ask Your Syllabus',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text('Get instant answers from your course syllabus.',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 12),
                textAlign: TextAlign.center),
          ]),
        ),
        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text('Try asking…',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkMid)),
        ),
        ...suggestions.map((q) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.surface,
                borderRadius: AppColors.r12,
                child: InkWell(
                  onTap: () => onAsk(q),
                  borderRadius: AppColors.r12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                        borderRadius: AppColors.r12,
                        border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: AppColors.r8),
                        child: const Icon(Icons.lightbulb_outline_rounded,
                            color: AppColors.primary, size: 15),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(q,
                              style: const TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500))),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 11, color: AppColors.inkLight),
                    ]),
                  ),
                ),
              ),
            )),
      ],
    );
  }
}

// ─── Chat Bubble ──────────────────────────────────────────────────────────────
class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.msg});
  final ChatMsg msg;

  @override
  Widget build(BuildContext context) => Align(
        alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: msg.isUser ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(msg.isUser ? 14 : 3),
              bottomRight: Radius.circular(msg.isUser ? 3 : 14),
            ),
            boxShadow: AppColors.shadowSm,
            border: msg.isUser ? null : Border.all(color: AppColors.border),
          ),
          child: Text(msg.text,
              style: TextStyle(
                  color: msg.isUser ? Colors.white : AppColors.ink,
                  fontSize: 13,
                  height: 1.5)),
        ),
      );
}

// ─── Typing Indicator ─────────────────────────────────────────────────────────
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomRight: Radius.circular(14),
              bottomLeft: Radius.circular(3),
            ),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.auto_awesome_rounded,
                size: 13, color: AppColors.primary),
            SizedBox(width: 5),
            Text('Thinking…',
                style: TextStyle(
                    color: AppColors.inkLight,
                    fontSize: 12,
                    fontStyle: FontStyle.italic)),
          ]),
        ),
      );
}

// ─── Chat Message Model ───────────────────────────────────────────────────────
class ChatMsg {
  const ChatMsg({required this.text, required this.isUser});
  final String text;
  final bool isUser;

  Map<String, String> toHistoryEntry() => {
        'role': isUser ? 'user' : 'assistant',
        'content': text,
      };
}
