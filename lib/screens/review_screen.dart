import 'package:flutter/material.dart';
import '../models/question_model.dart';
import '../services/export_service.dart';
import '../services/openai_service.dart';

class ReviewScreen extends StatefulWidget {
  final List<QuizQuestion> questions;
  const ReviewScreen({super.key, required this.questions});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final ExportService _exportService = ExportService();
  final OpenAIService _aiService = OpenAIService();

  void _showExportOptions() {
    showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
                child: Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.code, color: Colors.orange),
                  title: const Text('Moodle XML'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportService.exportToMoodle(context, widget.questions);
                  }),
              ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: const Text('PDF Document'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportService.exportToPDF(context, widget.questions);
                  }),
              ListTile(
                  leading: const Icon(Icons.description, color: Colors.blue),
                  title: const Text('Word Document (.doc)'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportService.exportToWord(context, widget.questions);
                  }),
            ])));
  }

  void _promptAIEdit(int index) {
    TextEditingController instructionCtrl = TextEditingController();

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Row(children: [
                Icon(Icons.auto_fix_high, color: Colors.purple),
                SizedBox(width: 10),
                Text("AI Editor")
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("How should the AI change this question?"),
                  const SizedBox(height: 10),
                  TextField(
                    controller: instructionCtrl,
                    decoration: const InputDecoration(
                        hintText: "e.g. 'Make it harder'",
                        border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel")),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _performAIEdit(index, instructionCtrl.text);
                    },
                    child: const Text("Generate Change"))
              ],
            ));
  }

  Future<void> _performAIEdit(int index, String instruction) async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()));

    try {
      QuizQuestion newQuestion = await _aiService.editQuestionWithAI(
          widget.questions[index], instruction);

      if (mounted) {
        Navigator.pop(context);
        setState(() {
          widget.questions[index] = newQuestion;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Question updated!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  void _editQuestion(int index) {
    final q = widget.questions[index];
    TextEditingController qCtrl = TextEditingController(text: q.question);
    TextEditingController aCtrl = TextEditingController(text: q.answer);
    
    // --- NEW: Controller for the General Feedback ---
    TextEditingController feedbackCtrl = TextEditingController(text: q.generalFeedback ?? q.explanation ?? '');
    
    List<TextEditingController> optControllers = (q.options ?? [])
        .map((opt) => TextEditingController(text: opt))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Manual Edit"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: qCtrl, maxLines: null, decoration: const InputDecoration(labelText: "Question")),
                const SizedBox(height: 10),
                
                // --- NEW: Input field for General Feedback ---
                TextField(
                  controller: feedbackCtrl, 
                  maxLines: 2, 
                  decoration: const InputDecoration(labelText: "General Feedback (for Moodle)")
                ),
                const SizedBox(height: 10),

                if (q.type == 'Essay')
                  TextField(controller: aCtrl, maxLines: 3, decoration: const InputDecoration(labelText: "Model Answer"))
                else ...[
                  const Text("Options (Mark correct answer in text field below)"),
                  ...optControllers.map((ctrl) => TextField(controller: ctrl)),
                  const SizedBox(height: 10),
                  TextField(controller: aCtrl, decoration: const InputDecoration(labelText: "Correct Answer Text")),
                ]
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  widget.questions[index] = QuizQuestion(
                    type: q.type,
                    question: qCtrl.text,
                    answer: aCtrl.text,
                    options: optControllers.map((c) => c.text).toList(),
                    explanation: q.explanation, 
                    // --- NEW: Save the feedback ---
                    generalFeedback: feedbackCtrl.text.isNotEmpty ? feedbackCtrl.text : null, 
                  );
                });
                Navigator.pop(ctx);
              },
              child: const Text("Save"),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Review Quiz")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: widget.questions.length,
              itemBuilder: (ctx, i) {
                final q = widget.questions[i];
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ExpansionTile(
                    title: Text("${i + 1}. ${q.question}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(q.type),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(icon: const Icon(Icons.auto_fix_high, color: Colors.purple), onPressed: () => _promptAIEdit(i)),
                          IconButton(icon: const Icon(Icons.edit), onPressed: () => _editQuestion(i)),
                        ],
                      ),
                      
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text("Correct Answer: ${q.answer}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            
                            // --- NEW: Display the General Feedback in the UI ---
                            if (q.generalFeedback != null || q.explanation != null)
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50, 
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue.shade200)
                                ),
                                child: Text(
                                  "Feedback: ${q.generalFeedback ?? q.explanation}", 
                                  style: TextStyle(color: Colors.blue.shade900, fontStyle: FontStyle.italic)
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (q.options != null)
                        ...q.options!.map((opt) => ListTile(
                              leading: Icon(opt == q.answer ? Icons.check_circle : Icons.circle_outlined, color: opt == q.answer ? Colors.green : Colors.grey),
                              title: Text(opt),
                              dense: true,
                            )),
                      const SizedBox(height: 10),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: const Text("Export Quiz"),
                onPressed: _showExportOptions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo, 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15)
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}