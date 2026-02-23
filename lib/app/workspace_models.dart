// lib/app/workspace_models.dart

class WorkspaceSummary {
  final String id;
  final String createdAt;
  final String originalFilename;
  final String pdfHash;
  final String title;
  // FIX: expose status so list UI can show Draft/Ready badge without full fetch
  final String status;

  WorkspaceSummary({
    required this.id,
    required this.createdAt,
    required this.originalFilename,
    required this.pdfHash,
    required this.title,
    required this.status,
  });

  factory WorkspaceSummary.fromJson(Map<String, dynamic> j) {
    final fields = (j['fields'] as Map?) ?? {};
    String title = '';
    for (final key in ['course_name', 'course_title']) {
      final v = (fields[key] ?? '').toString().trim();
      if (v.isNotEmpty) {
        title = v;
        break;
      }
    }

    return WorkspaceSummary(
      id: (j['id'] ?? '').toString(),
      createdAt: (j['created_at'] ?? '').toString(),
      originalFilename: (j['original_filename'] ?? '').toString(),
      pdfHash: (j['pdf_hash'] ?? '').toString(),
      title: title.isEmpty ? 'Untitled Course' : title,
      // FIX: parse status from backend ('draft' | 'ready')
      status: (j['status'] ?? 'draft').toString(),
    );
  }
}

class Workspace {
  final String id;
  final String createdAt;
  final String originalFilename;
  final String pdfHash;
  final String status; // FIX: was missing — backend always sends this
  final Map<String, String> fields;
  final List<Section> sections;
  final int studentsCount;

  Workspace({
    required this.id,
    required this.createdAt,
    required this.originalFilename,
    required this.pdfHash,
    required this.status,
    required this.fields,
    required this.sections,
    required this.studentsCount,
  });

  factory Workspace.fromJson(Map<String, dynamic> j) {
    final fieldsRaw = (j['fields'] as Map?) ?? {};
    final sectionsRaw = (j['sections'] as List?) ?? [];

    return Workspace(
      id: (j['id'] ?? '').toString(),
      createdAt: (j['created_at'] ?? '').toString(),
      originalFilename: (j['original_filename'] ?? '').toString(),
      pdfHash: (j['pdf_hash'] ?? '').toString(),
      // FIX: parse status
      status: (j['status'] ?? 'draft').toString(),
      fields: fieldsRaw.map(
        (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
      ),
      sections: sectionsRaw
          .map((e) => Section.fromJson(e as Map<String, dynamic>))
          .toList(),
      studentsCount: int.tryParse((j['students_count'] ?? 0).toString()) ?? 0,
    );
  }

  bool get isReady => status == 'ready';

  String get title {
    for (final key in [
      'course_name',
      'course_title',
      'course',
      'Course Name',
      'Course Title',
    ]) {
      final v = (fields[key] ?? '').trim();
      if (v.isNotEmpty) return v;
    }
    return 'Untitled Course';
  }

  // FIX: unified office_hours accessor — backend stores 'office_hours' as a
  // single field. The detail page splits it into office_hours_start /
  // office_hours_end locally. This getter returns the raw combined value for
  // display, falling back to the split fields if already saved separately.
  String get officeHours {
    final raw = (fields['office_hours'] ?? '').trim();
    if (raw.isNotEmpty) return raw;
    final start = (fields['office_hours_start'] ?? '').trim();
    final end = (fields['office_hours_end'] ?? '').trim();
    if (start.isNotEmpty && end.isNotEmpty) return '$start – $end';
    if (start.isNotEmpty) return start;
    return '';
  }
}

class Section {
  final String id;
  final String name;
  final String instructorName;
  final String location;
  final SectionSchedule schedule;
  final int studentsCount;

  Section({
    required this.id,
    required this.name,
    required this.instructorName,
    required this.location,
    required this.schedule,
    this.studentsCount = 0,
  });

  factory Section.fromJson(Map<String, dynamic> j) {
    final sch = (j['schedule'] as Map?)?.cast<String, dynamic>() ?? {};
    return Section(
      id: (j['section_id'] ?? j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      instructorName: (j['instructor_name'] ?? '').toString(),
      location: (j['location'] ?? '').toString(),
      schedule: SectionSchedule.fromJson(sch),
      studentsCount: int.tryParse((j['students_count'] ?? 0).toString()) ?? 0,
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
    final daysRaw = (j['days'] as List?) ?? [];
    return SectionSchedule(
      days: daysRaw.map((e) => e.toString()).toList(),
      startTime: (j['start_time'] ?? '').toString(),
      endTime: (j['end_time'] ?? '').toString(),
      timezone: (j['timezone'] ?? 'UTC').toString(),
      reminderMinutes:
          int.tryParse((j['reminder_minutes'] ?? 10).toString()) ?? 10,
    );
  }
}

/// Draft used when creating or editing a section.
class SectionDraft {
  String name = '';
  String instructorName = '';
  String location = '';
  List<String> days = const [];
  String startTime = '';
  String endTime = '';
  String timezone = 'UTC';
  int reminderMinutes = 10;

  Map<String, dynamic> toJson() => {
    'name': name,
    'instructor_name': instructorName,
    'location': location,
    'schedule': {
      'days': days,
      'start_time': startTime,
      'end_time': endTime,
      'timezone': timezone,
      'reminder_minutes': reminderMinutes,
    },
  };
}
