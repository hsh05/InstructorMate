// lib/app/state/workspaces_vm.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../workspace_models.dart';

class WorkspacesViewModel extends ChangeNotifier {
  WorkspacesViewModel({required this.api});

  final ApiClient api;

  bool loading = false;
  bool importing = false;
  String? error;

  List<WorkspaceSummary> workspaces = [];
  Workspace? current;

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
  }


  Future<void> openWorkspace(String id) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      current = await api.getWorkspace(id);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> importSyllabus() async {
    if (importing) return;
    importing = true;
    error = null;
    notifyListeners();

    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ["pdf", "docx", "txt"],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;

      final f = res.files.first;
      final Uint8List? bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception("Selected file has no data.");
      }

      current = await api.importWorkspace(
        bytes: bytes,
        filename: f.name,
      );

      await load(); // refresh list
    } catch (e) {
      error = e.toString();
    } finally {
      importing = false;
      notifyListeners();
    }
  }

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

  Future<void> importStudents() async {
    final ws = current;
    if (ws == null) return;

    loading = true;
    error = null;
    notifyListeners();

    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ["csv"],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;

      final f = res.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception("Selected file has no data.");
      }

      current = await api.importStudents(
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

}
