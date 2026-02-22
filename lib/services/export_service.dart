import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/question_model.dart';

class ExportService {
  
  Future<void> exportToMoodle(BuildContext context, List<QuizQuestion> questions) async {
    StringBuffer xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<quiz>');
    
    for (var q in questions) {
      String moodleType = "multichoice";
      
      // Determine type using simple string comparisons
      bool isExplicitTF = (q.type == "True/False");
      // Use ?.length and ?? 0 for null-safe comparison
      bool isImplicitTF = (q.type == "MCQ" && (q.options?.length ?? 0) == 2 && 
          q.options!.any((o) => o.toLowerCase() == "true") && 
          q.options!.any((o) => o.toLowerCase() == "false"));

      if (isExplicitTF || isImplicitTF) {
        moodleType = "truefalse";
      } else if (q.type == "Essay") {
        moodleType = "essay";
      }

      xml.writeln('  <question type="$moodleType">');
      xml.writeln('    <name><text>${q.question.substring(0, q.question.length > 40 ? 40 : q.question.length)}...</text></name>');
      xml.writeln('    <questiontext format="html"><text><![CDATA[${q.question}]]></text></questiontext>');
      // Fallback to the 'answer' or 'explanation' if the AI forgot to generate the specific feedback field
      String feedbackText = q.generalFeedback ?? q.explanation ?? "Model Answer: ${q.answer}";
      xml.writeln('    <generalfeedback format="html"><text><![CDATA[<p>$feedbackText</p>]]></text></generalfeedback>');
      // ------------------------------------
      
      if (moodleType == "essay") {
        xml.writeln('    <responseformat>editor</responseformat>');
        xml.writeln('    <responserequired>1</responserequired>');
      }
      else if (moodleType == "truefalse") {
        bool isTrueCorrect = q.answer.toLowerCase().contains("true");
        
        xml.writeln('    <answer fraction="${isTrueCorrect ? 100 : 0}" format="html">');
        xml.writeln('      <text>true</text>');
        xml.writeln('      <feedback><text>${isTrueCorrect ? "Correct!" : "Incorrect."}</text></feedback>');
        xml.writeln('    </answer>');

        xml.writeln('    <answer fraction="${!isTrueCorrect ? 100 : 0}" format="html">');
        xml.writeln('      <text>false</text>');
        xml.writeln('      <feedback><text>${!isTrueCorrect ? "Correct!" : "Incorrect."}</text></feedback>');
        xml.writeln('    </answer>');
      } 
      else {
        // Standard MCQ logic: check if the option string matches the answer string
        if (q.options != null) {
          for (var opt in q.options!) {
            int grade = (opt == q.answer) ? 100 : 0;
            xml.writeln('    <answer fraction="$grade" format="html"><text><![CDATA[$opt]]></text></answer>');
          }
        }
      }
      xml.writeln('  </question>');
    }
    xml.writeln('</quiz>');
    await _saveFile(context, xml.toString(), "quiz_moodle.xml");
  }

  Future<void> exportToWord(BuildContext context, List<QuizQuestion> questions) async {
    StringBuffer html = StringBuffer();
    html.writeln('<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns="http://www.w3.org/TR/REC-html40">');
    html.writeln('<head><meta charset="utf-8"><title>InstructorMate Quiz</title>');
    html.writeln('<style>body { font-family: Calibri, sans-serif; } .key { color: green; font-weight: bold; } .model { color: #555; font-style: italic; border: 1px solid #ccc; padding: 10px; background: #f9f9f9; }</style></head><body>');
    html.writeln('<h1>InstructorMate Quiz</h1>');
    
    for (int i = 0; i < questions.length; i++) {
      var q = questions[i];
      html.writeln('<p><b>${i+1}. ${q.question}</b></p>');
      
      if (q.type == 'Essay') {
        html.writeln('<div class="model"><p><b>Model Answer:</b> ${q.answer}</p></div>');
      } else if (q.options != null) {
        html.writeln('<ul>');
        for (var o in q.options!) {
          bool isCorrect = (o == q.answer);
          String style = isCorrect ? "class='key'" : "";
          String marker = isCorrect ? "(Correct) " : "";
          html.writeln('<li $style>$marker$o</li>');
        }
        html.writeln('</ul>');
      }
      html.writeln('<hr>');
    }
    html.writeln('</body></html>');
    await _saveFile(context, html.toString(), "quiz_word.doc");
  }

  Future<void> exportToPDF(BuildContext context, List<QuizQuestion> questions) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Header(level: 0, child: pw.Text("InstructorMate Exam", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 20),
          ...questions.asMap().entries.map((entry) {
            int idx = entry.key + 1;
            var q = entry.value;
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("$idx. ${q.question}", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                if (q.type == 'Essay')
                   pw.Container(
                     margin: const pw.EdgeInsets.only(top: 5),
                     padding: const pw.EdgeInsets.all(10),
                     decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), color: PdfColors.grey100),
                     child: pw.Text("Model Answer: ${q.answer}", style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: PdfColors.grey700))
                   )
                else if (q.options != null)
                  ...q.options!.map((o) {
                    bool isCorrect = (o == q.answer);
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 10, top: 2),
                      child: pw.Text("${isCorrect ? '[X]' : '[ ]'} $o")
                    );
                  }),
                pw.SizedBox(height: 15),
              ]
            );
          })
        ]
      )
    );
    await _saveFile(context, null, "quiz_exam.pdf", bytes: await pdf.save());
  }

  Future<void> _saveFile(BuildContext context, String? content, String filename, {List<int>? bytes}) async {
    try {
      String? outputPath;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        outputPath = await FilePicker.platform.saveFile(dialogTitle: 'Save your quiz', fileName: filename);
        if (outputPath == null) return;
      } else {
        var status = await Permission.storage.status;
        if (!status.isGranted) await Permission.storage.request();
        Directory? dir = (await getExternalStorageDirectory()) ?? (await getApplicationDocumentsDirectory());
        outputPath = '${dir.path}/$filename';
      }

      final file = File(outputPath);
      if (bytes != null) {
        await file.writeAsBytes(bytes);
      } else {
        await file.writeAsString(content!);
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved to: $outputPath"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving: $e"), backgroundColor: Colors.red));
      }
    }
  }
}