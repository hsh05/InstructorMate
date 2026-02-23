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

  List<WorkspaceSummary> workspaces = [];
  Workspace? current;

  // Authoritative student counts per section — keyed by sectionId.
  // Updated immediately on import. Survives tab switches.
  // Backend count_by_section is unreliable so we own this in the VM.
  final Map<String, int> sectionStudentCounts = {};

  /// Record imported students for a section, accumulating on repeated imports.
  void recordImport(String sectionId, int count) {
    sectionStudentCounts[sectionId] =
        (sectionStudentCounts[sectionId] ?? 0) + count;
    notifyListeners();
  }

  /// Total students across all sections in the current workspace.
  int get totalStudentsCount =>
      sectionStudentCounts.values.fold(0, (a, b) => a + b);

  /// Student count for a specific section (VM-authoritative).
  int countForSection(String sectionId) => sectionStudentCounts[sectionId] ?? 0;

  // ── Load ─────────────────────────────────────────────────────────────
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
      notifyListeners(); // UI renders immediately — don't block on notifications
    }
    // Init notifications AFTER UI is unblocked — fire and forget
    // ignore: unawaited_futures
    _initNotifications();
  }

  // ── Open workspace ────────────────────────────────────────────────────
  Future<void> openWorkspace(String id) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      current = await api.getWorkspace(id);
      // Seed counts from backend (may be 0 if count_by_section is broken,
      // but keeps things consistent when backend works correctly)
      sectionStudentCounts.clear();
      for (final s in current?.sections ?? []) {
        if (s.studentsCount > 0) {
          sectionStudentCounts[s.id] = s.studentsCount;
        }
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Import syllabus (from bytes — called by drag-drop and file picker) ───────
  Future<void> importSyllabusBytes({
    required Uint8List bytes,
    required String filename,
  }) async {
    if (importing) return;
    importing = true;
    error = null;
    notifyListeners();
    try {
      current = await api.importWorkspace(bytes: bytes, filename: filename);
      await load();
    } catch (e) {
      error = e.toString();
    } finally {
      importing = false;
      notifyListeners();
    }
  }

  // ── Import syllabus ───────────────────────────────────────────────────
  Future<void> importSyllabus() async {
    if (importing) return;
    importing = true;
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
      if (bytes == null || bytes.isEmpty)
        throw Exception('Selected file has no data.');
      current = await api.importWorkspace(bytes: bytes, filename: f.name);
      await load();
    } catch (e) {
      error = e.toString();
    } finally {
      importing = false;
      notifyListeners();
    }
  }

  // ── Update fields ─────────────────────────────────────────────────────
  Future<void> updateFields(Map<String, String> fields) async {
    final ws = current;
    if (ws == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      current = await api.updateWorkspaceFields(ws.id, fields);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Import students ───────────────────────────────────────────────────
  Future<void> importStudents() async {
    final ws = current;
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
      if (bytes == null || bytes.isEmpty)
        throw Exception('Selected file has no data.');
      // importStudents now returns ImportResult (count only).
      // Per-section import is handled in workspace_detail.dart directly.
      await api.importStudents(
        workspaceId: ws.id,
        bytes: bytes,
        filename: f.name,
      );
      // Re-fetch to refresh workspace state
      current = await api.getWorkspace(ws.id);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Delete workspace ──────────────────────────────────────────────────
  Future<bool> deleteWorkspace(String workspaceId) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await api.deleteWorkspace(workspaceId);
      workspaces.removeWhere((w) => w.id == workspaceId);
      if (current?.id == workspaceId) current = null;
      return true;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Delete section ────────────────────────────────────────────────────
  Future<void> deleteSection(String sectionId) async {
    final ws = current;
    if (ws == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      current = await api.deleteSection(ws.id, sectionId);
      await rescheduleNotificationsForCurrent();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Re-upload PDF ─────────────────────────────────────────────────────
  Future<void> reuploadSyllabus() async {
    final ws = current;
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
      current = await api.reuploadSyllabus(
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

  // ── Ask AI ────────────────────────────────────────────────────────────
  Future<String?> askInWorkspace(String question) async {
    final ws = current;
    if (ws == null) return null;
    try {
      return await api.ask(ws.id, question);
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return null;
    }
  }

  // ── Notifications ─────────────────────────────────────────────────────
  Future<void> _initNotifications() async {
    // Fetch full workspaces (with sections) for scheduling
    // workspaces list only has WorkspaceSummary — need full objects for section data
    final fullWorkspaces = <Workspace>[];
    for (final summary in workspaces) {
      try {
        fullWorkspaces.add(await api.getWorkspace(summary.id));
      } catch (_) {}
    }
    if (fullWorkspaces.isEmpty) return;

    if (kIsWeb) {
      WebNotificationService.instance.init(
        fullWorkspaces,
      ); // not awaited — non-blocking
    } else {
      await NotificationScheduler.rescheduleAll(fullWorkspaces);
    }
  }

  /// Called after a new section is created so notifications update immediately
  Future<void> rescheduleNotificationsForCurrent() async {
    final ws = current;
    if (ws == null) return;
    try {
      if (kIsWeb) {
        // Refresh the web ticker with updated workspace data
        final full = await api.getWorkspace(ws.id);
        WebNotificationService.instance.updateWorkspaces([full]);
      } else {
        await NotificationScheduler.rescheduleAll([ws]);
      }
    } catch (e) {
      debugPrint('[Notifications] reschedule failed: $e');
    }
  }
}
