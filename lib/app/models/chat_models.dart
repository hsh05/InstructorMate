// lib/app/models/chat_models.dart

enum ChatRole { user, assistant, system, status }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final ChatRole role;
  final String text;
  final DateTime createdAt;
}

class CsvPreview {
  CsvPreview({required this.title, required this.text});
  final String title;
  final String text;
}

enum FlowStage { upload, convert, ask }
