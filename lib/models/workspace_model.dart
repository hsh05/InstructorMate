class Workspace {
  final String id;
  final String title;
  final String semester;
  final int studentCount;
  final int taskCount;
  final bool isArchived;

  Workspace({
    required this.id,
    required this.title,
    required this.semester,
    required this.studentCount,
    required this.taskCount,
    this.isArchived = false,
  });

  // Factory constructor for creating from JSON (future backend integration)
  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace(
    id: json['id'],
    title: json['title'],
    semester: json['semester'],
    studentCount: json['studentCount'],
    taskCount: json['taskCount'],
    isArchived: json['isArchived'] ?? false,
  );

  // Convert to JSON (future backend integration)
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'semester': semester,
    'studentCount': studentCount,
    'taskCount': taskCount,
    'isArchived': isArchived,
  };
}