// lib/app/state/workspaces_vm.dart

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../../services/log_buffer.dart';
import '../../services/notification_scheduler.dart';
import '../../services/web_notification_service.dart';
import '../workspace_models.dart';

class WorkspacesViewModel extends ChangeNotifier {
  WorkspacesViewModel({required this.api});

  final ApiClient api;

  bool loading = false;
  bool importing = false;
  String? error;

  bool lastImportWasDuplicate = false;

  List<WorkspaceSummary> workspaces = [];

  Workspace? _current;
  Workspace? get current => _current;
  set current(Workspace? ws) {
    _current = ws;
  }

  final Map<String, int> sectionStudentCounts = {};

  void recordImport(String sectionId, int count) {
    sectionStudentCounts[sectionId] = count;
    notifyListeners();
  }

  int get totalStudentsCount =>
      sectionStudentCounts.values.fold(0, (a, b) => a + b);

  int countForSection(String sectionId) => sectionStudentCounts[sectionId] ?? 0;

  // ── File picker helper ────────────────────────────────────────────────────

  Future<({Uint8List bytes, String name})?> _pickFileBytes({
    required List<String> extensions,
  }) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    if (f.bytes == null || f.bytes!.isEmpty) {
      throw Exception('Selected file has no data.');
    }
    return (bytes: f.bytes!, name: f.name);
  }

  // ── Load ──────────────────────────────────────────────────────────────────

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
    await _initNotifications();
  }

  // ── Open workspace ────────────────────────────────────────────────────────

  Future<void> openWorkspace(String id) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      _current = await api.getWorkspace(id);
      for (final s in _current?.sections ?? []) {
        try {
          final students = await api.listSectionStudents(id, s.id);
          sectionStudentCounts[s.id] = students.isNotEmpty
              ? students.length
              : 0;
        } catch (_) {
          sectionStudentCounts.putIfAbsent(s.id, () => s.studentsCount);
        }
      }
      await rescheduleNotificationsForCurrent();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Import syllabus (bytes) ───────────────────────────────────────────────

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

  // ── Import syllabus (file picker) ─────────────────────────────────────────

  Future<void> importSyllabus() async {
    if (importing) return;
    importing = true;
    error = null;
    lastImportWasDuplicate = false;
    notifyListeners();
    try {
      final picked = await _pickFileBytes(extensions: ['pdf', 'docx', 'txt']);
      if (picked == null) return;
      final result = await api.importWorkspace(
        bytes: picked.bytes,
        filename: picked.name,
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

  // ── Update fields ─────────────────────────────────────────────────────────

  Future<void> updateFields(Map<String, String> fields) async {
    final ws = _current;
    if (ws == null) return;

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

  // ── Create section ────────────────────────────────────────────────────────

  Future<void> createSection(SectionDraft draft) async {
    final ws = _current;
    if (ws == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      // FIX: api.createSection now returns the full updated Workspace directly
      // from the create response (backend now returns workspace in body).
      // No separate GET needed.
      _current = await api.createSection(ws.id, draft);
      await rescheduleNotificationsForCurrent();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Import students ───────────────────────────────────────────────────────

  Future<void> importStudents({String sectionId = ''}) async {
    final ws = _current;
    if (ws == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final picked = await _pickFileBytes(extensions: ['csv', 'xlsx']);
      if (picked == null) return;
      final result = await api.importStudents(
        workspaceId: ws.id,
        bytes: picked.bytes,
        filename: picked.name,
        sectionId: sectionId,
      );
      recordImport(
        result.sectionId.isNotEmpty ? result.sectionId : sectionId,
        result.imported,
      );
      _current = await api.getWorkspace(ws.id);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Delete workspace ──────────────────────────────────────────────────────

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

  // ── Delete section ────────────────────────────────────────────────────────

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

  // ── Re-upload PDF ─────────────────────────────────────────────────────────

  Future<void> reuploadSyllabus() async {
    final ws = _current;
    if (ws == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final picked = await _pickFileBytes(extensions: ['pdf', 'docx', 'txt']);
      if (picked == null) return;
      _current = await api.reuploadSyllabus(
        workspaceId: ws.id,
        bytes: picked.bytes,
        filename: picked.name,
      );
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Ask AI ────────────────────────────────────────────────────────────────

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

  // ── Notifications ─────────────────────────────────────────────────────────

  Future<void> _initNotifications() async {
    if (workspaces.isEmpty) return;

    final full = <Workspace>[];
    for (final summary in workspaces) {
      try {
        if (_current != null && _current!.id == summary.id) {
          full.add(_current!);
        } else {
          full.add(await api.getWorkspace(summary.id));
        }
      } catch (_) {}
    }

    if (full.isEmpty) return;
    try {
      if (kIsWeb) {
        WebNotificationService.instance.init(full);
      } else {
        await NotificationScheduler.rescheduleAll(full);
      }
    } catch (e) {
      AppLog.e('[VM] _initNotifications error: $e');
    }
  }

  Future<void> rescheduleNotificationsForCurrent() async {
    final ws = _current;
    if (ws == null) return;

    try {
      final fresh = await api.getWorkspace(ws.id);
      _current = fresh;

      if (kIsWeb) {
        // FIX: rebuild the FULL workspace list for the web ticker.
        // Previously this passed only [fresh] (one workspace) to updateWorkspaces(),
        // which meant the ticker stopped watching all other workspaces' sections —
        // their notifications would silently stop firing after any section edit.
        final all = <Workspace>[];
        for (final summary in workspaces) {
          try {
            if (summary.id == fresh.id) {
              all.add(fresh); // use the already-fetched fresh copy
            } else {
              all.add(await api.getWorkspace(summary.id));
            }
          } catch (_) {}
        }
        WebNotificationService.instance.updateWorkspaces(all);
      } else {
        // For mobile: reschedule ALL workspaces so no alarms are lost
        final all = <Workspace>[];
        for (final summary in workspaces) {
          try {
            all.add(
              summary.id == fresh.id
                  ? fresh
                  : await api.getWorkspace(summary.id),
            );
          } catch (_) {}
        }
        await NotificationScheduler.rescheduleAll(all);
      }
    } catch (e) {
      AppLog.e('[VM] reschedule failed: $e');
    }
  }
}
