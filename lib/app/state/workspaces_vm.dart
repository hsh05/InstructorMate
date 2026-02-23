// lib/app/state/workspaces_vm.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../../services/notification_scheduler.dart';
import '../../services/web_notification_service.dart';
import '../workspace_models.dart';

class WorkspacesViewModel extends ChangeNotifier {
  WorkspacesViewModel({required this.api});

  final ApiClient api;

  bool loading = false;
  bool importing = false;
  String? error;

  /// Set to true after [importSyllabusBytes] when the backend recognised the
  /// file as a duplicate (same PDF hash). The home screen reads this once and
  /// resets it so the message only appears once per upload attempt.
  bool lastImportWasDuplicate = false;

  List<WorkspaceSummary> workspaces = [];

  Workspace? _current;
  Workspace? get current => _current;
  set current(Workspace? ws) {
    _current = ws;
    // Callers call notifyListeners() themselves to avoid redundant rebuilds.
  }

  // Authoritative student counts keyed by sectionId.
  final Map<String, int> sectionStudentCounts = {};

  void recordImport(String sectionId, int count) {
    sectionStudentCounts[sectionId] = count;
    notifyListeners();
  }

  int get totalStudentsCount =>
      sectionStudentCounts.values.fold(0, (a, b) => a + b);

  int countForSection(String sectionId) => sectionStudentCounts[sectionId] ?? 0;

  // ── Load ────────────────────────────────────────────────────────────────────

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      workspaces = await api.listWorkspaces();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
    // Fire and forget — notifications init after UI unblocks.
    // ignore: unawaited_futures
    _initNotifications();
  }

  // ── Open workspace ───────────────────────────────────────────────────────────

  Future<void> openWorkspace(String id) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      _current = await api.getWorkspace(id);
      for (final s in _current?.sections ?? []) {
        try {
          final students = await api.listSectionStudents(id, s.id);
          if (students.isNotEmpty) {
            sectionStudentCounts[s.id] = students.length;
          } else if (!sectionStudentCounts.containsKey(s.id)) {
            sectionStudentCounts[s.id] = 0;
          }
        } catch (_) {
          if (!sectionStudentCounts.containsKey(s.id)) {
            sectionStudentCounts[s.id] = s.studentsCount;
          }
        }
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Import syllabus (bytes) ──────────────────────────────────────────────────

  Future<void> importSyllabusBytes({
    required Uint8List bytes,
    required String filename,
  }) async {
    if (importing) return;
    importing = true;
    error = null;
    lastImportWasDuplicate = false;
    notifyListeners();
    try {
      final result = await api.importWorkspace(
        bytes: bytes,
        filename: filename,
      );
      _current = result.workspace;
      lastImportWasDuplicate = result.alreadyUploaded;
      await load();
    } catch (e) {
      error = e.toString();
    } finally {
      importing = false;
      notifyListeners();
    }
  }

  // ── Import syllabus (file picker, no-bytes path) ─────────────────────────────

  Future<void> importSyllabus() async {
    if (importing) return;
    importing = true;
    error = null;
    lastImportWasDuplicate = false;
    notifyListeners();
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'docx', 'txt'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Selected file has no data.');
      }
      final result = await api.importWorkspace(bytes: bytes, filename: f.name);
      _current = result.workspace;
      lastImportWasDuplicate = result.alreadyUploaded;
      await load();
    } catch (e) {
      error = e.toString();
    } finally {
      importing = false;
      notifyListeners();
    }
  }

  // ── Update fields ────────────────────────────────────────────────────────────

  Future<void> updateFields(Map<String, String> fields) async {
    final ws = _current;
    if (ws == null) return;

    // office_hours_start / office_hours_end are UI-only.
    // Merge back into the single 'office_hours' key the backend expects.
    final payload = Map<String, String>.from(fields);
    final start = payload.remove('office_hours_start') ?? '';
    final end = payload.remove('office_hours_end') ?? '';
    if (start.isNotEmpty || end.isNotEmpty) {
      payload['office_hours'] = end.isNotEmpty ? '$start – $end' : start;
    }

    loading = true;
    error = null;
    notifyListeners();
    try {
      _current = await api.updateWorkspaceFields(ws.id, payload);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Import students ──────────────────────────────────────────────────────────

  Future<void> importStudents() async {
    final ws = _current;
    if (ws == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Selected file has no data.');
      }
      await api.importStudents(
        workspaceId: ws.id,
        bytes: bytes,
        filename: f.name,
      );
      _current = await api.getWorkspace(ws.id);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Delete workspace ─────────────────────────────────────────────────────────

  Future<bool> deleteWorkspace(String workspaceId) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await api.deleteWorkspace(workspaceId);
      workspaces.removeWhere((w) => w.id == workspaceId);
      if (_current?.id == workspaceId) _current = null;
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Delete section ───────────────────────────────────────────────────────────

  Future<void> deleteSection(String sectionId) async {
    final ws = _current;
    if (ws == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      _current = await api.deleteSection(ws.id, sectionId);
      sectionStudentCounts.remove(sectionId);
      await rescheduleNotificationsForCurrent();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Re-upload PDF ────────────────────────────────────────────────────────────

  Future<void> reuploadSyllabus() async {
    final ws = _current;
    if (ws == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'docx', 'txt'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('File has no data.');
      _current = await api.reuploadSyllabus(
        workspaceId: ws.id,
        bytes: bytes,
        filename: f.name,
      );
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Ask AI ───────────────────────────────────────────────────────────────────

  Future<String?> askInWorkspace(String question) async {
    final ws = _current;
    if (ws == null) return null;
    try {
      return await api.ask(ws.id, question);
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return null;
    }
  }

  // ── Notifications ────────────────────────────────────────────────────────────

  Future<void> _initNotifications() async {
    final full = <Workspace>[];
    for (final s in workspaces) {
      try {
        full.add(await api.getWorkspace(s.id));
      } catch (_) {}
    }
    if (full.isEmpty) return;
    if (kIsWeb) {
      WebNotificationService.instance.init(full);
    } else {
      await NotificationScheduler.rescheduleAll(full);
    }
  }

  Future<void> rescheduleNotificationsForCurrent() async {
    final ws = _current;
    if (ws == null) return;
    try {
      if (kIsWeb) {
        final full = await api.getWorkspace(ws.id);
        WebNotificationService.instance.updateWorkspaces([full]);
      } else {
        final allFull = <Workspace>[];
        for (final s in workspaces) {
          try {
            allFull.add(s.id == ws.id ? ws : await api.getWorkspace(s.id));
          } catch (_) {}
        }
        await NotificationScheduler.rescheduleAll(
          allFull.isEmpty ? [ws] : allFull,
        );
      }
    } catch (e) {
      debugPrint('[Notifications] reschedule failed: $e');
    }
  }
}
