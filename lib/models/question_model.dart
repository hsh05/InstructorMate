class QuizQuestion {
  final String type;
  final String question;
  final List<String>? options; 
  final String answer;
  final String? explanation;
  final String? generalFeedback; // <--- NEW VARIABLE

  QuizQuestion({
    required this.type,
    required this.question,
    this.options,
    required this.answer,
    this.explanation,
    this.generalFeedback, // <--- ADD TO CONSTRUCTOR
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      type: json['type'] ?? 'Unknown',
      question: json['question'] ?? '',
      options: json['options'] != null ? List<String>.from(json['options']) : null,
      answer: json['answer'] ?? '',
      explanation: json['explanation'],
      generalFeedback: json['general_feedback'], // <--- CATCH IT FROM JSON
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'question': question,
      'options': options,
      'answer': answer,
      'explanation': explanation,
      'general_feedback': generalFeedback, // <--- ADD TO JSON
    };
  }
}