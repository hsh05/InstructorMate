// lib/app/models/workspace_models.dart

class WorkspaceSummary {
  final String id;
  final String createdAt;
  final String originalFilename;
  final String pdfHash; // FIX #6: was syllabusHash, backend sends pdf_hash
  final String title;

  WorkspaceSummary({
    required this.id,
    required this.createdAt,
    required this.originalFilename,
    required this.pdfHash,
    required this.title,
  });

  factory WorkspaceSummary.fromJson(Map<String, dynamic> j) {
    // Derive title from fields if present, fallback to course_name/course_title
    final fields = (j["fields"] as Map?) ?? {};
    String title = "";
    for (final key in ["course_name", "course_title"]) {
      final v = (fields[key] ?? "").toString().trim();
      if (v.isNotEmpty) {
        title = v;
        break;
      }
    }

    return WorkspaceSummary(
      id: (j["id"] ?? "").toString(),
      createdAt: (j["created_at"] ?? "").toString(),
      originalFilename: (j["original_filename"] ?? "").toString(),
      // FIX #6: backend key is pdf_hash, not syllabus_hash
      pdfHash: (j["pdf_hash"] ?? "").toString(),
      title: title.isEmpty ? "Untitled Course" : title,
    );
  }
}

class Workspace {
  final String id;
  final String createdAt;
  final String originalFilename;
  final String pdfHash; // FIX #6: was syllabusHash

  final Map<String, String> fields;
  final List<Section> sections;
  final int studentsCount;

  Workspace({
    required this.id,
    required this.createdAt,
    required this.originalFilename,
    required this.pdfHash,
    required this.fields,
    required this.sections,
    required this.studentsCount,
  });

  factory Workspace.fromJson(Map<String, dynamic> j) {
    final fieldsRaw = (j["fields"] as Map?) ?? {};
    final sectionsRaw = (j["sections"] as List?) ?? [];

    return Workspace(
      id: (j["id"] ?? "").toString(),
      createdAt: (j["created_at"] ?? "").toString(),
      originalFilename: (j["original_filename"] ?? "").toString(),
      // FIX #6: backend key is pdf_hash
      pdfHash: (j["pdf_hash"] ?? "").toString(),
      fields: fieldsRaw.map(
        (k, v) => MapEntry(k.toString(), (v ?? "").toString()),
      ),
      sections: sectionsRaw
          .map((e) => Section.fromJson(e as Map<String, dynamic>))
          .toList(),
      studentsCount: int.tryParse((j["students_count"] ?? 0).toString()) ?? 0,
    );
  }

  String get title {
    for (final key in [
      "course_name",
      "course_title",
      "course",
      "Course Name",
      "Course Title",
    ]) {
      final v = (fields[key] ?? "").trim();
      if (v.isNotEmpty) return v;
    }
    return "Untitled Course";
  }
}

class Section {
  final String id;
  final String name;
  final String instructorName;
  final String location;
  final SectionSchedule schedule;

  Section({
    required this.id,
    required this.name,
    required this.instructorName,
    required this.location,
    required this.schedule,
  });

  factory Section.fromJson(Map<String, dynamic> j) {
    final sch = (j["schedule"] as Map?)?.cast<String, dynamic>() ?? {};
    return Section(
      // FIX #7: backend returns "section_id", not "id"
      id: (j["section_id"] ?? j["id"] ?? "").toString(),
      name: (j["name"] ?? "").toString(),
      instructorName: (j["instructor_name"] ?? "").toString(),
      location: (j["location"] ?? "").toString(),
      schedule: SectionSchedule.fromJson(sch),
    );
  }
}

class SectionSchedule {
  final List<String> days;
  final String startTime;
  final String endTime;
  final String timezone;
  final int reminderMinutes;

  SectionSchedule({
    required this.days,
    required this.startTime,
    required this.endTime,
    required this.timezone,
    required this.reminderMinutes,
  });

  factory SectionSchedule.fromJson(Map<String, dynamic> j) {
    final daysRaw = (j["days"] as List?) ?? [];
    return SectionSchedule(
      days: daysRaw.map((e) => e.toString()).toList(),
      startTime: (j["start_time"] ?? "").toString(),
      endTime: (j["end_time"] ?? "").toString(),
      timezone: (j["timezone"] ?? "UTC").toString(),
      reminderMinutes:
          int.tryParse((j["reminder_minutes"] ?? 10).toString()) ?? 10,
    );
  }
}

// Draft for create/update section
class SectionDraft {
  String name = "";
  String instructorName = "";
  String location = "";
  List<String> days = const [];
  String startTime = "";
  String endTime = "";
  String timezone = "UTC";
  int reminderMinutes = 10;

  Map<String, dynamic> toJson() => {
    "name": name,
    "instructor_name": instructorName,
    "location": location,
    "schedule": {
      "days": days,
      "start_time": startTime,
      "end_time": endTime,
      "timezone": timezone,
      "reminder_minutes": reminderMinutes,
    },
  };
}
