// lib/models/workspace_model.dart

import '../utils/schedule_utils.dart';

// =============================================================================
// ── WORKSPACE SUMMARY (Used for list views) ──────────────────────────────────
// =============================================================================

class WorkspaceSummary {
  final int id; // 👉 Bridged to NeonDB: Now an int
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

  bool get isProcessing => status == 'draft' && title.isEmpty;

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

    // 👉 Bridged Title Logic: Checks both old fields and new DB columns
    String title = (j['workspace_title'] ?? '').toString();
    if (title.isEmpty) {
      for (final key in ['workspace_name', 'workspace_title']) {
        final v = (fields[key] ?? '').toString().trim();
        if (v.isNotEmpty) {
          title = v;
          break;
        }
      }
    }

    if (title.isEmpty && status == 'ready') {
      title = 'Untitled workspace';
    }

    final sectionsRaw = j['sections'] as List?;
    final sectionsCount = sectionsRaw != null
        ? sectionsRaw.length
        : (int.tryParse((j['sections_count'] ?? j['section_count'] ?? 0).toString()) ?? 0);

    int studentsCount = int.tryParse((j['students_count'] ?? j['student_count'] ?? 0).toString()) ?? 0;
    if (sectionsRaw != null && studentsCount == 0) {
      for (final s in sectionsRaw) {
        final sc = s as Map?;
        if (sc == null) continue;
        studentsCount += int.tryParse((sc['students_count'] ?? 0).toString()) ?? 0;
      }
    }

    final createdAt = (j['created_at'] ?? '').toString();
    final rawUpdated = j['updated_at']?.toString();
    final parsedCreated = DateTime.tryParse(createdAt);
    final parsedUpdated = rawUpdated != null ? DateTime.tryParse(rawUpdated) : null;
    final updatedAtRaw = (parsedUpdated != null &&
            parsedCreated != null &&
            parsedUpdated.difference(parsedCreated).inSeconds >= 5)
        ? rawUpdated
        : null;

    return WorkspaceSummary(
      // 👉 Safe int parsing regardless of endpoint
      id: int.tryParse((j['id'] ?? j['workspace_id'] ?? '0').toString()) ?? 0,
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

// =============================================================================
// ── FULL WORKSPACE (Used for details & AI Generation) ────────────────────────
// =============================================================================

class Workspace {
  final int id; // 👉 Bridged to NeonDB: Now an int
  final String createdAt;
  final String? updatedAtRaw;
  final String originalFilename;
  final String pdfHash;
  final String status;
  final Map<String, String> fields;
  final List<Section> sections;
  final int studentsCount;
  final List<WorkspaceMaterial> materials; // 👉 Merged from your models!

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
    required this.materials,
  });

  factory Workspace.fromJson(Map<String, dynamic> j) {
    final fieldsRaw = (j['fields'] as Map?) ?? {};
    
    // Safety mapping for our new optimized DB schema
    if (j.containsKey('workspace_code')) fieldsRaw['workspace_code'] = j['workspace_code'];
    if (j.containsKey('workspace_title')) fieldsRaw['workspace_title'] = j['workspace_title'];
    if (j.containsKey('semester')) fieldsRaw['semester'] = j['semester'];

    final sectionsRaw = (j['sections'] as List?) ?? [];
    final matsRaw = (j['materials'] as List?) ?? [];

    final createdAt = (j['created_at'] ?? '').toString();
    final rawUpdated = j['updated_at']?.toString();
    final parsedCreated = DateTime.tryParse(createdAt);
    final parsedUpdated = rawUpdated != null ? DateTime.tryParse(rawUpdated) : null;
    final updatedAtRaw = (parsedUpdated != null &&
            parsedCreated != null &&
            parsedUpdated.difference(parsedCreated).inSeconds >= 5)
        ? rawUpdated
        : null;

    return Workspace(
      // 👉 Safe int parsing
      id: int.tryParse((j['id'] ?? j['workspace_id'] ?? '0').toString()) ?? 0,
      createdAt: createdAt,
      updatedAtRaw: updatedAtRaw,
      originalFilename: (j['original_filename'] ?? '').toString(),
      pdfHash: (j['file_hash'] ?? '').toString(),
      status: (j['status'] ?? 'draft').toString(),
      fields: fieldsRaw.map((k, v) => MapEntry(k.toString(), (v ?? '').toString())),
      sections: sectionsRaw.map((e) => Section.fromJson(e as Map<String, dynamic>)).toList(),
      studentsCount: int.tryParse((j['students_count'] ?? 0).toString()) ?? 0,
      materials: matsRaw.map((e) => WorkspaceMaterial.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  bool get isReady => status == 'ready';
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
    // Check new DB schema first
    if (fields.containsKey('workspace_title') && fields['workspace_title']!.isNotEmpty) return fields['workspace_title']!;

    // Fallback to legacy schema
    for (final key in ['workspace_name', 'workspace_title', 'workspace', 'workspace Name', 'workspace Title']) {
      final v = (fields[key] ?? '').trim();
      if (v.isNotEmpty) return v;
    }
    return isReady ? 'Untitled workspace' : '';
  }

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

  // 👉 Equality operators required by DropdownButton in GenerateScreen
  @override
  bool operator ==(Object other) => identical(this, other) || other is Workspace && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// =============================================================================
// ── MATERIALS (Used by AI Generation) ────────────────────────────────────────
// =============================================================================

class WorkspaceMaterial {
  final int id;
  final int workspaceId;
  final String fileName;
  final String materialType;
  final String filePath;

  WorkspaceMaterial({
    required this.id, 
    required this.workspaceId, 
    required this.fileName, 
    required this.materialType, 
    required this.filePath
  });

  factory WorkspaceMaterial.fromJson(Map<String, dynamic> json) {
    return WorkspaceMaterial(
      // Safely parse ints just in case the backend sends them as strings
      id: int.tryParse(json['id'].toString()) ?? 0,
      workspaceId: int.tryParse((json['workspace_id'] ?? '0').toString()) ?? 0,
      fileName: json['file_name'] ?? '',
      materialType: json['material_type'] ?? '',
      filePath: json['file_path'] ?? '',
    );
  }
}


// =============================================================================
// ── SECTIONS & STUDENTS ──────────────────────────────────────────────────────
// =============================================================================

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
      endTime: (rawEnd == rawTz || rawEnd.toUpperCase() == 'UTC' && rawStart.isNotEmpty && rawEnd == rawTz) ? '' : rawEnd,
      timezone: rawTz,
      reminderMinutes: int.tryParse((j['reminder_minutes'] ?? 10).toString()) ?? 10,
    );
  }

  String get formattedTimeRange {
    final s = startTime.isNotEmpty ? ScheduleUtils.formatTime(startTime) : '';
    final e = endTime.isNotEmpty ? ScheduleUtils.formatTime(endTime) : '';
    if (s.isEmpty && e.isEmpty) return '—';
    if (e.isEmpty) return s;
    return '$s – $e';
  }

  String get formattedStartTime => startTime.isNotEmpty ? ScheduleUtils.formatTime(startTime) : '';
}

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