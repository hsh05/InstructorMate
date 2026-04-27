import 'package:flutter/material.dart';

class QuestionTypeConfig {
  final String name;
  bool isSelected;
  int count;
  String difficulty; // NEW: Added difficulty
  TextEditingController topicController; 

  QuestionTypeConfig({
    required this.name,
    required this.isSelected,
    required this.count,
    this.difficulty = 'Medium', // Default to Medium
    TextEditingController? topicController,
  }) : topicController = topicController ?? TextEditingController();
}