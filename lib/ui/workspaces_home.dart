// lib/ui/workspaces_home.dart
// CHANGES: Removed debug bug-icon button and LogViewerScreen import.
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
    if (widget.vm.lastImportWasDuplicate) {
      widget.vm.lastImportWasDuplicate = false;
      final ws = widget.vm.current;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.6),
        builder: (ctx) {
          final ws = widget.vm.current;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Amber warning header ──────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF8ED),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEDC2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFFFD080),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.file_copy_rounded,
                            color: Color(0xFFE6920A),
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Duplicate Syllabus',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A1A2E),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'This file was already imported',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF888888),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Body ─────────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Found existing workspace:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFAAAAAA),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F0FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _primary.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: _primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.school_rounded,
                                  color: _primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ws?.title ?? filename,
                                      style: const TextStyle(
                                        color: Color(0xFF1A1A2E),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (ws?.status != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        ws!.status == 'ready'
                                            ? '● Ready'
                                            : '○ Draft',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: ws.status == 'ready'
                                              ? const Color(0xFF22C55E)
                                              : const Color(0xFFAAAAAA),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Actions ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: Color(0xFFE0E0E0),
                                ),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text(
                              'Dismiss',
                              style: TextStyle(
                                color: Color(0xFF888888),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              'Open Workspace',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              if (ws != null && mounted) {
                                Navigator.of(context).pushNamed('/workspace');
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
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
