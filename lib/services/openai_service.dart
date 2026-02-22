import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/config_model.dart';
import '../models/question_model.dart';

class OpenAIService {
  static final String _baseUrl = "https://instructormate.onrender.com/";

  // ADDED selectedMaterialIds parameter
  Future<List<QuizQuestion>> generateQuiz(int courseId, List<QuestionTypeConfig> configs, List<int> selectedMaterialIds) async {
    var uri = Uri.parse('$_baseUrl/courses/$courseId/generate-quiz/');
    var response = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "configs": configs.map((c) => {
          'type': c.name, 
          'count': c.count, 
          'difficulty': c.difficulty, // <--- ADD THIS
          'topic': c.topicController.text
        }).toList(),
        "selected_material_ids": selectedMaterialIds,
      }),
    );

    if (response.statusCode == 200) {
        // 1. Get the raw string from the server
        String rawBody = utf8.decode(response.bodyBytes);

        // 2. Sometimes OpenAI wraps the JSON in markdown backticks. We must strip them.
        rawBody = rawBody.trim();
        if (rawBody.startsWith('```json')) {
          rawBody = rawBody.substring(7);
        } else if (rawBody.startsWith('```')) {
          rawBody = rawBody.substring(3);
        }
        if (rawBody.endsWith('```')) {
          rawBody = rawBody.substring(0, rawBody.length - 3);
        }
        rawBody = rawBody.trim();

        // 3. Decode the cleaned string
        final decodedData = jsonDecode(rawBody);

        // 4. Open the "questions" envelope!
        List<dynamic> questionsList;
        if (decodedData is Map && decodedData.containsKey('questions')) {
          questionsList = decodedData['questions'];
        } else if (decodedData is List) {
          // Just in case the AI ignored the prompt and sent a flat list anyway
          questionsList = decodedData;
        } else {
          throw Exception("Unexpected AI response format.");
        }

        // 5. Convert the JSON maps into Dart objects
        return questionsList.map((q) => QuizQuestion.fromJson(q)).toList();
        
      } else {
        // --- NEW BULLETPROOF ERROR PARSING ---
        final errorData = jsonDecode(response.body);
        
        // Grab whichever key the backend happened to send, or fallback to a default string
        String errorMessage = errorData['detail']?.toString() 
                           ?? errorData['message']?.toString() 
                           ?? errorData['error']?.toString() 
                           ?? 'Unknown server error from Render';
                           
        throw Exception(errorMessage);
      }
  }

  Future<QuizQuestion> editQuestionWithAI(QuizQuestion oldQuestion, String instruction) async {
    var uri = Uri.parse('$_baseUrl/edit-question/');
    var response = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"question_data": oldQuestion.toJson(), "instruction": instruction}),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return QuizQuestion.fromJson(data['updated_question']);
    } 
    throw Exception("Failed to edit question");
  }
}