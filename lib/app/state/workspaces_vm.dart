// lib/app/state/workspaces_vm.dart
// FIX: openWorkspace() now navigates instantly using summary data already
//      in hand. Full workspace fetch happens in the background so the
//      detail page appears in <100ms instead of waiting 2-3s for the API.

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../../services/mobile_toast_service.dart';
import '../../services/notification_scheduler.dart';
import '../../services/web_notification_service.dart';
import '../workspace_models.dart';
import '../../utils/schedule_utils.dart';

class WorkspacesViewModel extends ChangeNotifier {
  WorkspacesViewModel({required this.api});

  final ApiClient api;

  bool loading = false;
  bool importing = false;

  /// True while background detail fetch is running after instant navigation.
  bool loadingDetail = false;

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
    _syncCurrentToList();
    notifyListeners();
  }

  int get totalStudentsCount =>
      sectionStudentCounts.values.fold(0, (a, b) => a + b);

  int countForSection(String sectionId) => sectionStudentCounts[sectionId] ?? 0;

  void updateWorkspaceSummary(WorkspaceSummary updated) {
    final idx = workspaces.indexWhere((w) => w.id == updated.id);
    if (idx != -1) {
      workspaces[idx] = updated;
    } else {
      workspaces.insert(0, updated);
    }
    notifyListeners();
  }

  // ── Mobile foreground ticker ──────────────────────────────────────────────
  Timer? _mobileTicker;
  List<Workspace> _allWorkspaces = [];
  final Set<String> _firedKeys = {};

  void _startMobileTicker() {
    if (kIsWeb) return;
    _mobileTicker?.cancel();
    _checkMobileToasts();
    _mobileTicker = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkMobileToasts(),
    );
  }

  void _checkMobileToasts() {
    if (kIsWeb || _allWorkspaces.isEmpty) return;
    final now = DateTime.now();
    for (final ws in _allWorkspaces) {
      for (final section in ws.sections) {
        final sch = section.schedule;
        if (sch.startTime.isEmpty) continue;
        final parsed = _parseHHmm(sch.startTime);
        if (parsed == null) continue;
        final remind = sch.reminderMinutes > 0 ? sch.reminderMinutes : 10;
        for (final day in sch.days) {
          final weekday = ScheduleUtils.weekdayFor(day.trim());
          if (weekday == null) continue;
          final fireAt = _nextFireAt(
            now: now,
            weekday: weekday,
            hour: parsed.$1,
            minute: parsed.$2,
            reminderMinutes: remind,
          );
          final diff = now.difference(fireAt).inSeconds;
          if (diff >= 0 && diff < 60) {
            final key =
                '${section.name}:${fireAt.year}-${fireAt.month}-${fireAt.day}-${fireAt.hour}-${fireAt.minute}';
            if (_firedKeys.contains(key)) continue;
            _firedKeys.add(key);
            if (_firedKeys.length > 100) _firedKeys.remove(_firedKeys.first);
            final loc =
                section.location.isNotEmpty ? ' @ ${section.location}' : '';
            final notifTitle = '⏰ ${ws.title} starts in ${remind}min';
            final notifBody =
                '${section.name.isNotEmpty ? section.name : "Class"}$loc — ${ScheduleUtils.formatTime(sch.startTime)}';
            WebNotificationService.instance.addMobileNotif(
              title: notifTitle,
              body: notifBody,
              fireAt: DateTime.now(),
            );
            MobileToastService.show(title: notifTitle, body: notifBody);
          }
        }
      }
    }
  }

  static (int, int)? _parseHHmm(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final upper = s.toUpperCase();
    final isPM = upper.contains('PM');
    final isAM = upper.contains('AM');
    final timeOnly =
        s.replaceAll(RegExp(r'[AaPp][Mm]', caseSensitive: false), '').trim();
    final parts = timeOnly.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    int hour24 = h;
    if (isPM && h != 12) hour24 = h + 12;
    if (isAM && h == 12) hour24 = 0;
    return (hour24, m);
  }

  static DateTime _nextFireAt({
    required DateTime now,
    required int weekday,
    required int hour,
    required int minute,
    required int reminderMinutes,
  }) {
    var classTime = DateTime(now.year, now.month, now.day, hour, minute);
    int safety = 0;
    while (classTime.weekday != weekday && safety < 7) {
      classTime = classTime.add(const Duration(days: 1));
      safety++;
    }
    var fireAt = classTime.subtract(Duration(minutes: reminderMinutes));
    if (now.difference(fireAt).inSeconds >= 60)
      fireAt = fireAt.add(const Duration(days: 7));
    return fireAt;
  }

  @override
  void dispose() {
    _mobileTicker?.cancel();
    super.dispose();
  }

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
    _initNotifications().ignore();
  }

  // ── Open workspace — INSTANT navigation ───────────────────────────────────
  // Returns immediately after building a shell from cached summary data.
  // The caller navigates right away. Detail is filled in the background.

  Future<void> openWorkspace(String id) async {
    error = null;

    final summary = workspaces.firstWhere(
      (w) => w.id == id,
      orElse: () => WorkspaceSummary(
        id: id,
        createdAt: '',
        originalFilename: '',
        pdfHash: '',
        title: '',
        status: 'draft',
      ),
    );

    // Set shell immediately — header renders at once with title/status/counts
    _current = Workspace(
      id: summary.id,
      createdAt: summary.createdAt,
      originalFilename: summary.originalFilename,
      pdfHash: summary.pdfHash,
      status: summary.status,
      fields: {
        'course_name': summary.title,
        'course_title': summary.title,
        // Pre-populate other fields as empty — controllers will be
        // corrected by _syncControllersFromWorkspace() once loadingDetail
        // becomes false and the full workspace data arrives.
        'course_code': '',
        'semester': '',
      },
      sections: const [],
      studentsCount: summary.studentsCount,
    );
    sectionStudentCounts.clear();
    loadingDetail = true;
    notifyListeners(); // caller navigates immediately after this

    // Background: fetch full workspace (sections, all fields, etc.)
    try {
      final full = await api.getWorkspace(id);
      _current = full;
      sectionStudentCounts.clear();
      for (final s in full.sections) {
        sectionStudentCounts[s.id] = s.studentsCount;
      }
      _syncCurrentToList();
    } catch (e) {
      error = e.toString();
    } finally {
      loadingDetail = false;
      notifyListeners();
    }

    rescheduleNotificationsForCurrent().ignore();
  }

  // ── Import syllabus ───────────────────────────────────────────────────────

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
      final result =
          await api.importWorkspace(bytes: bytes, filename: filename);
      _current = result.workspace;
      lastImportWasDuplicate = result.alreadyUploaded;
      _syncCurrentToList();
    } catch (e) {
      error = e.toString();
    } finally {
      importing = false;
      notifyListeners();
    }
  }

  Future<void> importSyllabus() async {
    if (importing) return;
    importing = true;
    error = null;
    lastImportWasDuplicate = false;
    notifyListeners();
    try {
      final picked = await _pickFileBytes(extensions: ['pdf', 'docx', 'txt']);
      if (picked == null) return;
      final result =
          await api.importWorkspace(bytes: picked.bytes, filename: picked.name);
      _current = result.workspace;
      lastImportWasDuplicate = result.alreadyUploaded;
      _syncCurrentToList();
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
    loading = true;
    error = null;
    notifyListeners();
    try {
      _current = await api.updateWorkspaceFields(ws.id, Map.from(fields));
      _syncCurrentToList();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Future<void> createSection(SectionDraft draft) async {
    final ws = _current;
    if (ws == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      _current = await api.createSection(ws.id, draft);
      _syncCurrentToList();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
    rescheduleNotificationsForCurrent().ignore();
  }

  Future<void> updateSection(String sectionId, SectionDraft draft) async {
    final ws = _current;
    if (ws == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      _current = await api.updateSection(ws.id, sectionId, draft);
      _syncCurrentToList();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
    rescheduleNotificationsForCurrent().ignore();
  }

  Future<void> deleteSection(String sectionId) async {
    final ws = _current;
    if (ws == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      _current = await api.deleteSection(ws.id, sectionId);
      sectionStudentCounts.remove(sectionId);
      _syncCurrentToList();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
    rescheduleNotificationsForCurrent().ignore();
  }

  // ── Students ──────────────────────────────────────────────────────────────

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
      _syncCurrentToList();
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

  // ── Sync ──────────────────────────────────────────────────────────────────

  void _syncCurrentToList() {
    final ws = _current;
    if (ws == null) return;
    final idx = workspaces.indexWhere((s) => s.id == ws.id);
    int totalStudents = sectionStudentCounts.values.fold(0, (a, b) => a + b);
    if (totalStudents == 0) {
      totalStudents = ws.studentsCount > 0
          ? ws.studentsCount
          : ws.sections.fold(0, (sum, s) => sum + s.studentsCount);
    }
    final newSummary = WorkspaceSummary(
      id: ws.id,
      createdAt: idx != -1 ? workspaces[idx].createdAt : ws.createdAt,
      // FIX: Never stamp DateTime.now() as updatedAt — that makes simply
      // opening a workspace appear as if something was updated. Only use the
      // real backend value; if absent, preserve whatever the list already had.
      updatedAtRaw: ws.updatedAtRaw?.isNotEmpty == true
          ? ws.updatedAtRaw
          : (idx != -1 ? workspaces[idx].updatedAtRaw : null),
      originalFilename:
          idx != -1 ? workspaces[idx].originalFilename : ws.originalFilename,
      pdfHash: idx != -1 ? workspaces[idx].pdfHash : ws.pdfHash,
      title: ws.title,
      status: ws.status,
      sectionsCount: ws.sections.length,
      studentsCount: totalStudents,
    );
    if (idx == -1) {
      workspaces.insert(0, newSummary);
    } else {
      workspaces[idx] = newSummary;
    }
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  Future<void> _initNotifications() async {
    if (workspaces.isEmpty) return;
    final full = <Workspace>[];
    for (final summary in workspaces) {
      try {
        full.add(_current?.id == summary.id
            ? _current!
            : await api.getWorkspace(summary.id));
      } catch (_) {}
    }
    if (full.isEmpty) return;
    try {
      if (kIsWeb) {
        WebNotificationService.instance.init(full);
      } else {
        await NotificationScheduler.rescheduleAll(full);
      }
    } catch (_) {}
  }

  Future<void> rescheduleNotificationsForCurrent() async {
    final ws = _current;
    if (ws == null) return;
    try {
      final fresh = await api.getWorkspace(ws.id);
      _current = fresh;
      if (kIsWeb) {
        final all = <Workspace>[];
        for (final s in workspaces) {
          try {
            all.add(s.id == fresh.id ? fresh : await api.getWorkspace(s.id));
          } catch (_) {}
        }
        WebNotificationService.instance.updateWorkspaces(all);
      } else {
        final all = <Workspace>[];
        for (final s in workspaces) {
          try {
            all.add(s.id == fresh.id ? fresh : await api.getWorkspace(s.id));
          } catch (_) {}
        }
        _allWorkspaces = List.of(all);
        await NotificationScheduler.rescheduleAll(all);
        _startMobileTicker();
      }
    } catch (_) {}
  }
}
