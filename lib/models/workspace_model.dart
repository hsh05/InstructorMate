import 'package:uuid/uuid.dart';

class Workspace {
  final String id;
  final String title;
  final String semester;
  final bool isArchived;
  final List<String> enrolledStudents; // List of student IDs/emails
  final List<String> tasks;            // List of task IDs/titles

  Workspace({
    String? id,
    required this.title,
    required this.semester,
    this.isArchived = false,
    this.enrolledStudents = const [],
    this.tasks = const [],
  }) : id = id ?? const Uuid().v4(); // Auto-generate ID if not provided

  // Computed properties - derived from lists, never stored manually
  int get studentCount => enrolledStudents.length;
  int get taskCount => tasks.length;

  // Copy with (for updates without mutating)
  Workspace copyWith({
    String? title,
    String? semester,
    bool? isArchived,
    List<String>? enrolledStudents,
    List<String>? tasks,
  }) => Workspace(
    id: id, // Always preserve original ID
    title: title ?? this.title,
    semester: semester ?? this.semester,
    isArchived: isArchived ?? this.isArchived,
    enrolledStudents: enrolledStudents ?? this.enrolledStudents,
    tasks: tasks ?? this.tasks,
  );

  // JSON support for future backend
  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
    id: json['id'],
    title: json['title'],
    semester: json['semester'],
    isArchived: json['isArchived'] ?? false,
    enrolledStudents: List<String>.from(json['enrolledStudents'] ?? []),
    tasks: List<String>.from(json['tasks'] ?? []),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'semester': semester,
    'isArchived': isArchived,
    'enrolledStudents': enrolledStudents,
    'tasks': tasks,
  };
}