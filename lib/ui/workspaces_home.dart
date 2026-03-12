// lib/ui/workspaces_home.dart
// UPDATED: Workspace cards now show sections count, student count, and
//          last-updated timestamp — all wired to real model data.
//          WorkspaceSummary extended with sectionsCount + studentsCount
//          from the backend JSON. Drop-zone redesigned to match screenshot.
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../app/state/workspaces_vm.dart';
import '../app/workspace_models.dart';
import '../config/app_colors.dart';
import 'widgets/notification_bell.dart';

class WorkspacesHome extends StatefulWidget {
  const WorkspacesHome({super.key, required this.vm});
  final WorkspacesViewModel vm;

  @override
  State<WorkspacesHome> createState() => _WorkspacesHomeState();
}

class _WorkspacesHomeState extends State<WorkspacesHome> {
  bool _dragOver = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (_, __) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppColors.primary,
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
              colors: [AppColors.bgTop, AppColors.bg],
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
    if (widget.vm.loading && widget.vm.workspaces.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
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
          importing: widget.vm.importing,
          onDragOver: (v) => setState(() => _dragOver = v),
          onPickFile: _pickFile,
          onDropBytes: _importBytes,
        ),
        if (widget.vm.workspaces.isNotEmpty)
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: widget.vm.workspaces.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _WorkspaceCard(
                workspace: widget.vm.workspaces[i],
                onTap: () async {
                  await widget.vm.openWorkspace(widget.vm.workspaces[i].id);
                  if (context.mounted && widget.vm.current != null) {
                    Navigator.of(context).pushNamed('/workspace');
                  }
                },
                onDelete: () =>
                    _confirmDelete(context, widget.vm.workspaces[i]),
              ),
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
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
            ),
          ),
      ],
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF8ED),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
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
                          child: const Icon(Icons.file_copy_rounded,
                              color: Color(0xFFE6920A), size: 24),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Duplicate Syllabus',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A2E),
                              letterSpacing: -0.3),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'This file was already imported',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF888888),
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
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
                              letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F0FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: AppColors.primary.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.school_rounded,
                                    color: AppColors.primary, size: 20),
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
                                          fontSize: 14),
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
                                side:
                                    const BorderSide(color: Color(0xFFE0E0E0)),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Dismiss',
                                style: TextStyle(
                                    color: Color(0xFF888888),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.arrow_forward_rounded,
                                size: 16),
                            label: const Text('Open Workspace',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
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

    if (widget.vm.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.vm.error!),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _confirmDelete(BuildContext context, WorkspaceSummary workspace) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Workspace',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        content: Text(
          'Delete "${workspace.title}"?\nThis permanently removes all sections, students, and files.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              final ok = await widget.vm.deleteWorkspace(workspace.id);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(widget.vm.error ?? 'Delete failed'),
                    backgroundColor: AppColors.red,
                  ),
                );
              }
            },
            child: const Text('Delete',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─── Workspace Card ───────────────────────────────────────────────────────────
class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.workspace,
    required this.onTap,
    required this.onDelete,
  });

  final WorkspaceSummary workspace;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final timeAgo = workspace.updatedAt != null
        ? _timeAgo(workspace.updatedAt!)
        : (workspace.createdAt.isNotEmpty
            ? _timeAgoFromString(workspace.createdAt)
            : null);

    final sectionCount = workspace.sectionsCount;
    final studentCount = workspace.studentsCount;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              // Title + metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppColors.ink,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    // Status badge + inline section · student count
                    Row(
                      children: [
                        _StatusBadge(status: workspace.status),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$sectionCount ${sectionCount == 1 ? "Section" : "Sections"} · $studentCount ${studentCount == 1 ? "Student" : "Students"}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.inkMid,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (timeAgo != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last updated $timeAgo',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // 3-dots menu
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppColors.inkMid,
                  size: 20,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 3,
                onSelected: (val) {
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: const [
                        Icon(Icons.delete_outline_rounded,
                            color: AppColors.red, size: 18),
                        SizedBox(width: 10),
                        Text(
                          'Delete',
                          style: TextStyle(
                              color: AppColors.red,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 5) return '${weeks}w ago';
    final months = (diff.inDays / 30).floor();
    return '${months}mo ago';
  }

  String? _timeAgoFromString(String raw) {
    if (raw.isEmpty) return null;
    try {
      final dt = DateTime.parse(raw);
      return _timeAgo(dt);
    } catch (_) {
      return null;
    }
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
    final bg = isReady ? AppColors.accentSoft : AppColors.warnSoft;
    final fg = isReady ? const Color(0xFF007A63) : const Color(0xFFB36200);
    final dot = isReady ? AppColors.accent : AppColors.warn;

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
    required this.importing,
    required this.onDragOver,
    required this.onPickFile,
    required this.onDropBytes,
  });
  final bool dragOver;
  final bool importing;
  final void Function(bool) onDragOver;
  final VoidCallback onPickFile;
  final Future<void> Function(Uint8List, String) onDropBytes;

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
          onTap: importing ? null : onPickFile,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: dragOver ? AppColors.bgTop : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dragOver ? AppColors.primary : AppColors.border,
                width: dragOver ? 2 : 1.5,
                style: BorderStyle.solid,
              ),
            ),
            child: importing
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Importing syllabus…',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        scale: dragOver ? 1.15 : 1.0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          dragOver
                              ? Icons.file_download_rounded
                              : Icons.upload_file_rounded,
                          color: AppColors.primary,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        dragOver ? 'Drop to upload' : 'Drag & drop a PDF here',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'or tap to browse — PDF, DOCX, TXT',
                        style: TextStyle(
                          color: AppColors.inkLight,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
