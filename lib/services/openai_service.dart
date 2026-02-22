import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/config_model.dart';
import '../models/question_model.dart';

class OpenAIService {
  static final String _baseUrl = "https://instructormateassessment.onrender.com/";

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
      var data = jsonDecode(response.body);
      // The backend returns {'questions': [...]}. We map it to objects here.
      return (data['questions'] as List).map((json) => QuizQuestion.fromJson(json)).toList();
    } 
    throw Exception("Failed to generate quiz: ${response.body}");
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