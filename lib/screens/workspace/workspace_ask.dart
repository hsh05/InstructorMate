// lib/screens/workspace/workspace_ask.dart

import 'package:flutter/material.dart';

// 👉 THE FIX: Added an extra '../' to reach out of the 'workspace' subfolder!
import '../../app_styles.dart';

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
        // 👉 THE FIX: Removed 'const' here since AppStyles might not be const
        decoration: BoxDecoration(
          color: AppStyles.white, 
          border: const Border(top: BorderSide(color: AppStyles.borderLight)), 
        ),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(color: AppStyles.textPrimary, fontSize: 13), 
              decoration: InputDecoration(
                hintText: 'Ask about the syllabus…',
                hintStyle: const TextStyle(color: AppStyles.darkGray), 
                filled: true,
                fillColor: AppStyles.lightGray, 
                border: OutlineInputBorder(
                    borderRadius: AppStyles.borderRadiusXL, 
                    borderSide: BorderSide.none),
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
                color: asking ? AppStyles.darkGray : AppStyles.primaryPurple, 
                borderRadius: AppStyles.borderRadiusXL, 
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
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6747B0), Color(0xFF9B78E0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: AppStyles.borderRadiusXL, 
          ),
          child: Column(children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: AppStyles.borderRadiusL, 
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
            Text('Get instant answers from your workspace syllabus.',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 12),
                textAlign: TextAlign.center),
          ]),
        ),
        const SizedBox(height: 18),
        // 👉 THE FIX: Removed 'const' here
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text('Try asking…',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppStyles.darkGray)), 
        ),
        ...suggestions.map((q) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppStyles.white, 
                borderRadius: AppStyles.borderRadiusM, 
                child: InkWell(
                  onTap: () => onAsk(q),
                  borderRadius: AppStyles.borderRadiusM, 
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                        borderRadius: AppStyles.borderRadiusM, 
                        border: Border.all(color: AppStyles.borderLight)), 
                    child: Row(children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                            color: AppStyles.primaryPurple.withOpacity(0.15), 
                            borderRadius: AppStyles.borderRadiusS), 
                        // 👉 THE FIX: Removed 'const' here
                        child: const Icon(Icons.lightbulb_outline_rounded,
                            color: AppStyles.primaryPurple, size: 15), 
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(q,
                              // 👉 THE FIX: Removed 'const' here
                              style: const TextStyle(
                                  color: AppStyles.textPrimary, 
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500))),
                      // 👉 THE FIX: Removed 'const' here
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 11, color: AppStyles.darkGray), 
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
            color: msg.isUser ? AppStyles.primaryPurple : AppStyles.white, 
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(msg.isUser ? 14 : 3),
              bottomRight: Radius.circular(msg.isUser ? 3 : 14),
            ),
            boxShadow: AppStyles.shadowLight, 
            border: msg.isUser ? null : Border.all(color: AppStyles.borderLight), 
          ),
          child: Text(msg.text,
              style: TextStyle(
                  color: msg.isUser ? Colors.white : AppStyles.textPrimary, 
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
            color: AppStyles.white, 
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomRight: Radius.circular(14),
              bottomLeft: Radius.circular(3),
            ),
            border: Border.all(color: AppStyles.borderLight), 
          ),
          // 👉 THE FIX: Removed 'const' array since children use AppStyles
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.auto_awesome_rounded,
                size: 13, color: AppStyles.primaryPurple), 
            SizedBox(width: 5),
            Text('Thinking…',
                style: TextStyle(
                    color: AppStyles.darkGray, 
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