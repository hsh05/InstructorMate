// lib/ui/workspaces_home.dart
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../app/state/workspaces_vm.dart';
import 'widgets/notification_bell.dart';

class WorkspacesHome extends StatefulWidget {
  const WorkspacesHome({super.key, required this.vm});
  final WorkspacesViewModel vm;

  @override
  State<WorkspacesHome> createState() => _WorkspacesHomeState();
}

class _WorkspacesHomeState extends State<WorkspacesHome> {
  static const _bg = Color(0xFFF5F2FF);
  static const _bgTop = Color(0xFFEDE8FF);
  static const _cardSoft = Color(0xFFFFFFFF);
  static const _primary = Color(0xFF7C5CBF);
  static const _accent = Color(0xFF00B896);
  static const _textPrimary = Color(0xFF2D2640);
  static const _textSecondary = Color(0xFF7B748F);
  static const _red = Color(0xFFD93025);
  static const _warn = Color(0xFFE8900A);

  bool _dragOver = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (_, __) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: _primary,
          title: const Text(
            'InstructorMate',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          actions: [
            const NotificationBell(),
            IconButton(
              tooltip: 'Import syllabus',
              icon: widget.vm.importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_file_rounded, color: Colors.white),
              onPressed: widget.vm.importing ? null : _pickFile,
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_bgTop, _bg],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.vm.loading) {
      return const Center(child: CircularProgressIndicator(color: _primary));
    }

    if (widget.vm.error != null && widget.vm.workspaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            widget.vm.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return Column(
      children: [
        _DropZone(
          dragOver: _dragOver,
          onDragOver: (v) => setState(() => _dragOver = v),
          onPickFile: _pickFile,
          onDropBytes: _importBytes,
        ),
        if (widget.vm.workspaces.isNotEmpty)
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: widget.vm.workspaces.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) =>
                  _workspaceCard(context, widget.vm.workspaces[i]),
            ),
          )
        else
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Drop a PDF above or tap the upload button to get started.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textSecondary, fontSize: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _workspaceCard(BuildContext context, dynamic workspace) {
    return Material(
      color: _cardSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await widget.vm.openWorkspace(workspace.id);
          if (context.mounted && widget.vm.current != null) {
            Navigator.of(context).pushNamed('/workspace');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE8E3F8)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE8FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: _primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _StatusBadge(status: workspace.status),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete workspace',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: _red,
                  size: 20,
                ),
                onPressed: () => _confirmDelete(context, workspace),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: _textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    if (widget.vm.importing) return;
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'txt'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null) return;
    await _importBytes(f.bytes!, f.name);
  }

  Future<void> _importBytes(Uint8List bytes, String filename) async {
    await widget.vm.importSyllabusBytes(bytes: bytes, filename: filename);
    if (!mounted) return;

    // ── Duplicate upload detection ──────────────────────────────────────────
    // Show a friendly info banner instead of silently opening the same
    // workspace again with no feedback.
    if (widget.vm.lastImportWasDuplicate) {
      // Reset the flag so subsequent uploads start clean.
      widget.vm.lastImportWasDuplicate = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '⚠️ Already Imported — this syllabus was uploaded before. Opening the existing workspace.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: _warn,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return; // Don't also show the error snackbar below.
    }

    // ── Generic error ───────────────────────────────────────────────────────
    if (widget.vm.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.vm.error!),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _confirmDelete(BuildContext context, dynamic workspace) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Delete Workspace',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        content: Text(
          'Delete "${workspace.title}"?\nThis permanently removes all sections, students, and files.',
          style: const TextStyle(fontSize: 13, color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              final ok = await widget.vm.deleteWorkspace(workspace.id);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(widget.vm.error ?? 'Delete failed'),
                    backgroundColor: _red,
                  ),
                );
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status Badge ─────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final isReady = status == 'ready';
    final label = isReady ? 'Ready' : 'Draft';
    final bg = isReady ? const Color(0xFFE0FAF5) : const Color(0xFFFFF4E0);
    final fg = isReady ? const Color(0xFF007A63) : const Color(0xFFB36200);
    final dot = isReady ? const Color(0xFF00B896) : const Color(0xFFE8900A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Drag and Drop Zone ───────────────────────────────────────────────────────
class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.dragOver,
    required this.onDragOver,
    required this.onPickFile,
    required this.onDropBytes,
  });
  final bool dragOver;
  final void Function(bool) onDragOver;
  final VoidCallback onPickFile;
  final Future<void> Function(Uint8List, String) onDropBytes;

  static const _primary = Color(0xFF7C5CBF);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: DragTarget<Object>(
        onWillAcceptWithDetails: (_) {
          onDragOver(true);
          return true;
        },
        onLeave: (_) => onDragOver(false),
        onAcceptWithDetails: (_) async {
          onDragOver(false);
          onPickFile();
        },
        builder: (_, __, ___) => GestureDetector(
          onTap: onPickFile,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: dragOver
                  ? const Color(0xFFEDE8FF)
                  : const Color(0xFFF3F0FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dragOver ? _primary : const Color(0xFFBFB0E8),
                width: dragOver ? 2 : 1.5,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: dragOver ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    dragOver
                        ? Icons.file_download_rounded
                        : Icons.upload_file_rounded,
                    color: _primary,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  dragOver ? 'Drop to upload' : 'Drag & drop a PDF here',
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'or tap to browse — PDF, DOCX, TXT',
                  style: TextStyle(color: Color(0xFF9B96B0), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
