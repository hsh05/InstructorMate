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
      // The ?.toString() ?? '' guarantees it will ALWAYS be a String
      type: json['type']?.toString() ?? 'Unknown',
      question: json['question']?.toString() ?? '',
      
      // Safely map through the list, converting any null items to empty strings
      options: json['options'] != null 
          ? (json['options'] as List).map((e) => e?.toString() ?? '').toList() 
          : null,
          
      answer: json['answer']?.toString() ?? '',
      explanation: json['explanation']?.toString(),
      generalFeedback: json['general_feedback']?.toString(),
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