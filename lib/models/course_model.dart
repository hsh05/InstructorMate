class Course {
  final int id;
  final String title;
  final String? description;
  final List<CourseMaterial> materials;

  Course({required this.id, required this.title, this.description, required this.materials});

  factory Course.fromJson(Map<String, dynamic> json) {
    var list = json['materials'] as List? ?? [];
    List<CourseMaterial> materialsList = list.map((i) => CourseMaterial.fromJson(i)).toList();
    return Course(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      materials: materialsList,
    );
  }

  // --- NEW: Add these two overrides so the Dropdown knows how to compare courses ---
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Course && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class CourseMaterial {
  final int id;
  final int courseId;
  final String fileName;
  final String materialType;
  final String filePath;

  CourseMaterial({required this.id, required this.courseId, required this.fileName, required this.materialType, required this.filePath});

  factory CourseMaterial.fromJson(Map<String, dynamic> json) {
    return CourseMaterial(
      id: json['id'],
      courseId: json['course_id'],
      fileName: json['file_name'],
      materialType: json['material_type'],
      filePath: json['file_path'],
    );
  }
}