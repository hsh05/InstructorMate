// lib/app/workspace_models.dart
//
// FIX: SectionSchedule.formattedTimeRange now uses 12-h AM/PM format
//      so "08:00 – 09:30" displays as "8:00 AM – 9:30 AM" in the UI.
// FIX: Workspace.officeHours correctly parses both the combined 'office_hours'
//      field and the split start/end UI fields.
// FIX: Student moved here from api_client.dart — one canonical model.

import '../utils/schedule_utils.dart';

class WorkspaceSummary {
  final String id;
  final String createdAt;
  final String originalFilename;
  final String pdfHash;
  final String title;
  final String status;

  const WorkspaceSummary({
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
      status: (j['status'] ?? 'draft').toString(),
    );
  }
}

class Workspace {
  final String id;
  final String createdAt;
  final String originalFilename;
  final String pdfHash;
  final String status;
  final Map<String, String> fields;
  final List<Section> sections;
  final int studentsCount;

  const Workspace({
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

  /// Returns the raw office_hours string, falling back to merged start–end.
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

  const Section({
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

// lib/app/workspace_models.dart
// (only the changed parts shown — merge into full file)

class SectionSchedule {
  final List<String> days;
  final String startTime;
  final String endTime;
  final String timezone;
  final int reminderMinutes;

  const SectionSchedule({
    required this.days,
    required this.startTime,
    required this.endTime,
    required this.timezone,
    required this.reminderMinutes,
  });

  factory SectionSchedule.fromJson(Map<String, dynamic> j) {
    final daysRaw = (j['days'] as List?) ?? [];

    // FIX: guard end_time — if it's missing or equals the timezone string,
    // treat as empty. Previously a missing end_time key fell back to
    // j['timezone'] in some call paths, causing "UTC" to render as the time.
    final rawEnd = (j['end_time'] ?? '').toString().trim();
    final rawStart = (j['start_time'] ?? '').toString().trim();
    final rawTz = (j['timezone'] ?? 'UTC').toString().trim();

    return SectionSchedule(
      days: daysRaw.map((e) => e.toString()).toList(),
      startTime: rawStart,
      // FIX: never let endTime hold a timezone string
      endTime:
          (rawEnd == rawTz ||
              rawEnd.toUpperCase() == 'UTC' &&
                  rawStart.isNotEmpty &&
                  rawEnd == rawTz)
          ? ''
          : rawEnd,
      timezone: rawTz,
      reminderMinutes:
          int.tryParse((j['reminder_minutes'] ?? 10).toString()) ?? 10,
    );
  }

  String get formattedTimeRange {
    final s = startTime.isNotEmpty ? ScheduleUtils.formatTime(startTime) : '';
    final e = endTime.isNotEmpty ? ScheduleUtils.formatTime(endTime) : '';
    if (s.isEmpty && e.isEmpty) return '—';
    if (e.isEmpty) return s;
    return '$s – $e';
  }

  String get formattedStartTime =>
      startTime.isNotEmpty ? ScheduleUtils.formatTime(startTime) : '';
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

/// FIX: Moved from api_client.dart — one canonical Student model.
class Student {
  final String studentId;
  final String name;
  final String email;
  final String studentNo;

  const Student({
    required this.studentId,
    required this.name,
    required this.email,
    required this.studentNo,
  });

  factory Student.fromJson(Map<String, dynamic> j) => Student(
    studentId: (j['student_id'] ?? j['id'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    email: (j['email'] ?? '').toString(),
    studentNo: (j['student_no'] ?? '').toString(),
  );
}
