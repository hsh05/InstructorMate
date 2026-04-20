import 'package:flutter/material.dart';
import '../../models/question_model.dart';
import '../../services/export_service.dart';
import '../../services/api_service.dart'; // 👉 THE FIX: Changed from openai_service.dart
import '../../app_styles.dart';           // 👉 THE FIX: Added AppStyles

class ReviewScreen extends StatefulWidget {
  final List<QuizQuestion> questions;
  const ReviewScreen({super.key, required this.questions});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final ExportService _exportService = ExportService();
  final ApiService _apiService = ApiService(); // 👉 THE FIX: Using ApiService

  void _showExportOptions() {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        backgroundColor: AppStyles.white,
        builder: (ctx) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Wrap(children: [
                                ListTile(
                    leading: const Icon(Icons.code, color: AppStyles.warning),
                    title: const Text('Moodle XML', style: TextStyle(color: AppStyles.textPrimary, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _exportService.exportToMoodle(context, widget.questions);
                    }),
                                ListTile(
                    leading: const Icon(Icons.picture_as_pdf, color: AppStyles.error),
                    title: const Text('PDF Document', style: TextStyle(color: AppStyles.textPrimary, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _exportService.exportToPDF(context, widget.questions);
                    }),
                                ListTile(
                    leading: const Icon(Icons.description, color: AppStyles.primary),
                    title: const Text('Word Document (.doc)', style: TextStyle(color: AppStyles.textPrimary, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _exportService.exportToWord(context, widget.questions);
                    }),
                              ]),
                )));
  }

  void _promptAIEdit(int index) {
    TextEditingController instructionCtrl = TextEditingController();

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: AppStyles.white,
              shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusL),
              title: Row(children: const [
                Icon(Icons.auto_fix_high_rounded, color: AppStyles.primary),
                SizedBox(width: 10),
                Text("AI Editor", style: AppStyles.headingSmall)
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("How should the AI change this question?", style: AppStyles.bodyMedium),
                  const SizedBox(height: 16),
                  TextField(
                    controller: instructionCtrl,
                    style: const TextStyle(color: AppStyles.textPrimary, fontSize: 14),
                    decoration: AppStyles.inputDecoration(
                      labelText: "Instructions",
                      icon: Icons.chat_bubble_outline_rounded,
                      iconColor: AppStyles.primary,
                    ).copyWith(hintText: "e.g. 'Make it harder'"),
                    maxLines: 2,
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel", style: TextStyle(color: AppStyles.darkGray, fontWeight: FontWeight.w600))),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppStyles.primary,
                        foregroundColor: AppStyles.white,
                        shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _performAIEdit(index, instructionCtrl.text);
                    },
                    child: const Text("Generate Change", style: TextStyle(fontWeight: FontWeight.w700)))
              ],
            ));
  }

  Future<void> _performAIEdit(int index, String instruction) async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppStyles.primary)));

    try {
      // 👉 THE FIX: Routing the AI request securely through ApiService
      QuizQuestion newQuestion = await _apiService.editQuestionWithAI(
          widget.questions[index], instruction);

      if (mounted) {
        Navigator.pop(context);
        setState(() {
          widget.questions[index] = newQuestion;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Question updated!"), 
          backgroundColor: AppStyles.success, // Mapped from green
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
        ));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Error: $e"), 
        backgroundColor: AppStyles.error, // Mapped from red
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
      ));
    }
  }

  void _editQuestion(int index) {
    final q = widget.questions[index];
    TextEditingController qCtrl = TextEditingController(text: q.question);
    TextEditingController aCtrl = TextEditingController(text: q.answer);
    
    TextEditingController feedbackCtrl = TextEditingController(text: q.generalFeedback ?? q.explanation ?? '');
    
    List<TextEditingController> optControllers = (q.options ?? [])
        .map((opt) => TextEditingController(text: opt))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppStyles.white,
          shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusL),
          title: const Text("Manual Edit", style: AppStyles.headingSmall),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: qCtrl, maxLines: null, 
                  style: const TextStyle(color: AppStyles.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(labelText: "Question", labelStyle: TextStyle(color: AppStyles.darkGray))
                ),
                const SizedBox(height: 10),
                
                TextField(
                  controller: feedbackCtrl, 
                  maxLines: 2, 
                  style: const TextStyle(color: AppStyles.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(labelText: "General Feedback (for Moodle)", labelStyle: TextStyle(color: AppStyles.darkGray))
                ),
                const SizedBox(height: 16),

                if (q.type == 'Essay')
                  TextField(
                    controller: aCtrl, maxLines: 3, 
                    style: const TextStyle(color: AppStyles.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(labelText: "Model Answer", labelStyle: TextStyle(color: AppStyles.darkGray))
                  )
                else ...[
                  const Text("Options (Mark correct answer in text field below)", style: TextStyle(fontSize: 12, color: AppStyles.primary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...optControllers.map((ctrl) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: TextField(
                      controller: ctrl,
                      style: const TextStyle(color: AppStyles.textPrimary, fontSize: 14),
                      decoration: const InputDecoration(isDense: true)
                    ),
                  )),
                  const SizedBox(height: 10),
                  TextField(
                    controller: aCtrl, 
                    style: const TextStyle(color: AppStyles.success, fontSize: 14, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(labelText: "Correct Answer Text", labelStyle: TextStyle(color: AppStyles.darkGray))
                  ),
                ]
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx), 
              child: const Text("Cancel", style: TextStyle(color: AppStyles.darkGray, fontWeight: FontWeight.w600))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppStyles.primary,
                  foregroundColor: AppStyles.white,
                  shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM)),
              onPressed: () {
                setState(() {
                  widget.questions[index] = QuizQuestion(
                    type: q.type,
                    question: qCtrl.text,
                    answer: aCtrl.text,
                    options: optControllers.map((c) => c.text).toList(),
                    explanation: q.explanation, 
                    generalFeedback: feedbackCtrl.text.isNotEmpty ? feedbackCtrl.text : null, 
                  );
                });
                Navigator.pop(ctx);
              },
              child: const Text("Save", style: TextStyle(fontWeight: FontWeight.w700)),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.lightGray,
      appBar: AppBar(
        title: const Text("Review Quiz", style: TextStyle(color: AppStyles.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppStyles.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppStyles.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              itemCount: widget.questions.length,
              itemBuilder: (ctx, i) {
                final q = widget.questions[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppStyles.borderRadiusL,
                    side: const BorderSide(color: AppStyles.borderLight),
                  ),
                  elevation: 0,
                  color: AppStyles.white,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      iconColor: AppStyles.primary,
                      collapsedIconColor: AppStyles.darkGray,
                      title: Text("${i + 1}. ${q.question}", style: const TextStyle(fontWeight: FontWeight.bold, color: AppStyles.textPrimary)),
                      subtitle: Text(q.type, style: const TextStyle(color: AppStyles.darkGray, fontSize: 12)),
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(icon: const Icon(Icons.auto_fix_high_rounded, color: AppStyles.primary), onPressed: () => _promptAIEdit(i)),
                            IconButton(icon: const Icon(Icons.edit_rounded, color: AppStyles.darkGray), onPressed: () => _editQuestion(i)),
                            const SizedBox(width: 8),
                          ],
                        ),
                        
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text("Correct Answer: ${q.answer}", style: const TextStyle(color: AppStyles.success, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              
                              if (q.generalFeedback != null || q.explanation != null)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppStyles.mediumGray, 
                                    borderRadius: AppStyles.borderRadiusM,
                                  ),
                                  child: Text(
                                    "Feedback: ${q.generalFeedback ?? q.explanation}", 
                                    style: const TextStyle(color: AppStyles.textPrimary, fontStyle: FontStyle.italic, fontSize: 13)
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),

                        if (q.options != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Column(
                              children: q.options!.map((opt) => ListTile(
                                leading: Icon(
                                  opt == q.answer ? Icons.check_circle_rounded : Icons.circle_outlined, 
                                  color: opt == q.answer ? AppStyles.success : AppStyles.darkGray,
                                  size: 20,
                                ),
                                title: Text(opt, style: TextStyle(color: opt == q.answer ? AppStyles.textPrimary : AppStyles.darkGray)),
                                dense: true,
                                visualDensity: VisualDensity.compact,
                              )).toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppStyles.white,
              border: Border(top: BorderSide(color: AppStyles.borderLight)),
            ),
            child: Container(
              height: AppStyles.buttonHeightL,
              width: double.infinity,
              decoration: AppStyles.buttonDecoration,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.download_rounded, color: AppStyles.white),
                label: const Text("Export Quiz", style: AppStyles.buttonText),
                onPressed: _showExportOptions,
                style: AppStyles.elevatedButtonStyle,
              ),
            ),
          )
        ],
      ),
    );
  }
}