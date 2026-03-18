// lib/app/workspace_models.dart
//
// FIX: SectionSchedule.formattedTimeRange now uses 12-h AM/PM format
//      so "08:00 – 09:30" displays as "8:00 AM – 9:30 AM" in the UI.
// FIX: Student moved here from api_client.dart — one canonical model.
// UPDATE: WorkspaceSummary now includes sectionsCount, studentsCount, updatedAt
//         so the home screen can display real numbers without opening each workspace.
// FIX: WorkspaceSummary.isProcessing — true when status is 'draft' and no name
//      has been extracted yet. Card shows shimmer instead of "Untitled Course".
// FIX: updatedAtRaw is null when backend updated_at == created_at (new workspace)
//      so the home card never shows "updated just now" on a fresh import.

import '../utils/schedule_utils.dart';

class WorkspaceSummary {
  final String id;
  final String createdAt;
  final String? updatedAtRaw;
  final String originalFilename;
  final String pdfHash;
  final String title;
  final String status;
  final int sectionsCount;
  final int studentsCount;

  const WorkspaceSummary({
    required this.id,
    required this.createdAt,
    this.updatedAtRaw,
    required this.originalFilename,
    required this.pdfHash,
    required this.title,
    required this.status,
    this.sectionsCount = 0,
    this.studentsCount = 0,
  });

  /// True when the workspace is still being processed by the backend LLM
  /// and no name has been extracted yet — show a loading card, not "Untitled".
  bool get isProcessing => status == 'draft' && title.isEmpty;

  /// Returns the real backend updated_at timestamp, or null if none.
  /// Does NOT fall back to created_at — that caused opening a workspace
  /// to appear as a content update.
  DateTime? get updatedAt {
    if (updatedAtRaw?.isNotEmpty != true) return null;
    try {
      return DateTime.parse(updatedAtRaw!);
    } catch (_) {
      return null;
    }
  }

  factory WorkspaceSummary.fromJson(Map<String, dynamic> j) {
    final fields = (j['fields'] as Map?) ?? {};
    final status = (j['status'] ?? 'draft').toString();

    // Resolve title from fields map
    String title = '';
    for (final key in ['course_name', 'course_title']) {
      final v = (fields[key] ?? '').toString().trim();
      if (v.isNotEmpty) {
        title = v;
        break;
      }
    }

    // Only fall back to 'Untitled Course' when status is ready (extraction done).
    // While draft with no name, keep title empty so isProcessing returns true
    // and the card shows a loading shimmer instead of "Untitled Course".
    if (title.isEmpty && status == 'ready') {
      title = 'Untitled Course';
    }

    // sections_count: backend may expose this at the summary level
    final sectionsRaw = j['sections'] as List?;
    final sectionsCount = sectionsRaw != null
        ? sectionsRaw.length
        : (int.tryParse(
                (j['sections_count'] ?? j['section_count'] ?? 0).toString()) ??
            0);

    // students_count: total across all sections
    int studentsCount = int.tryParse(
            (j['students_count'] ?? j['student_count'] ?? 0).toString()) ??
        0;
    // If sections list is embedded, sum from there as well
    if (sectionsRaw != null && studentsCount == 0) {
      for (final s in sectionsRaw) {
        final sc = s as Map?;
        if (sc == null) continue;
        studentsCount +=
            int.tryParse((sc['students_count'] ?? 0).toString()) ?? 0;
      }
    }

    // Only use updated_at if it's genuinely different from created_at.
    // On creation the backend sets both to the same timestamp — showing
    // "updated just now" on a brand new import is misleading.
    final createdAt = (j['created_at'] ?? '').toString();
    final rawUpdated = j['updated_at']?.toString();
    final updatedAtRaw =
        (rawUpdated != null && rawUpdated.isNotEmpty && rawUpdated != createdAt)
            ? rawUpdated
            : null;

    return WorkspaceSummary(
      id: (j['id'] ?? '').toString(),
      createdAt: createdAt,
      updatedAtRaw: updatedAtRaw,
      originalFilename: (j['original_filename'] ?? '').toString(),
      pdfHash: (j['file_hash'] ?? '').toString(),
      title: title,
      status: status,
      sectionsCount: sectionsCount,
      studentsCount: studentsCount,
    );
  }
}

class Workspace {
  final String id;
  final String createdAt;
  final String? updatedAtRaw;
  final String originalFilename;
  final String pdfHash;
  final String status;
  final Map<String, String> fields;
  final List<Section> sections;
  final int studentsCount;

  const Workspace({
    required this.id,
    required this.createdAt,
    this.updatedAtRaw,
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

    // Only use updated_at if it's genuinely different from created_at.
    // On creation the backend sets both to the same timestamp — showing
    // "updated just now" on a brand new import is misleading.
    final createdAt = (j['created_at'] ?? '').toString();
    final rawUpdated = j['updated_at']?.toString();
    final updatedAtRaw =
        (rawUpdated != null && rawUpdated.isNotEmpty && rawUpdated != createdAt)
            ? rawUpdated
            : null;

    return Workspace(
      id: (j['id'] ?? '').toString(),
      createdAt: createdAt,
      updatedAtRaw: updatedAtRaw,
      originalFilename: (j['original_filename'] ?? '').toString(),
      pdfHash: (j['file_hash'] ?? '').toString(),
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

  /// True when backend is still extracting — no name yet and still draft.
  bool get isProcessing => status == 'draft' && title.isEmpty;

  DateTime? get updatedAt {
    if (updatedAtRaw?.isNotEmpty != true) return null;
    try {
      return DateTime.parse(updatedAtRaw!);
    } catch (_) {
      return null;
    }
  }

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
    // Only show "Untitled Course" when ready — during draft/processing show nothing
    return isReady ? 'Untitled Course' : '';
  }

  /// Converts this full Workspace into a WorkspaceSummary with real counts.
  WorkspaceSummary toSummary() {
    int totalStudents = studentsCount;
    if (totalStudents == 0) {
      for (final s in sections) {
        totalStudents += s.studentsCount;
      }
    }
    return WorkspaceSummary(
      id: id,
      createdAt: createdAt,
      updatedAtRaw: updatedAtRaw,
      originalFilename: originalFilename,
      pdfHash: pdfHash,
      title: title,
      status: status,
      sectionsCount: sections.length,
      studentsCount: totalStudents,
    );
  }
}

class Section {
  final String id;
  final String name;
  final String instructorName;
  final String location;
  final SectionSchedule schedule;
  final int studentsCount;
  final String lastImportHash;

  const Section({
    required this.id,
    required this.name,
    required this.instructorName,
    required this.location,
    required this.schedule,
    this.studentsCount = 0,
    this.lastImportHash = '',
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
      lastImportHash: (j['last_import_hash'] ?? '').toString(),
    );
  }
}

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
    final rawEnd = (j['end_time'] ?? '').toString().trim();
    final rawStart = (j['start_time'] ?? '').toString().trim();
    final rawTz = (j['timezone'] ?? 'UTC').toString().trim();

    return SectionSchedule(
      days: daysRaw.map((e) => e.toString()).toList(),
      startTime: rawStart,
      endTime: (rawEnd == rawTz ||
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
