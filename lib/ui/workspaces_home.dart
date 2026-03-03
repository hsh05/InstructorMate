// lib/ui/workspaces_home.dart
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../app/state/workspaces_vm.dart';
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
    if (widget.vm.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (widget.vm.error != null && widget.vm.workspaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            widget.vm.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.red),
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
                  style: TextStyle(color: AppColors.inkLight, fontSize: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _workspaceCard(BuildContext context, dynamic workspace) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppColors.r16,
      child: InkWell(
        borderRadius: AppColors.r16,
        onTap: () async {
          await widget.vm.openWorkspace(workspace.id);
          if (context.mounted && widget.vm.current != null) {
            Navigator.of(context).pushNamed('/workspace');
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: AppColors.r16,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: AppColors.r12,
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: AppColors.primary,
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
                        color: AppColors.ink,
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
                  color: AppColors.red,
                  size: 20,
                ),
                onPressed: () => _confirmDelete(context, workspace),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.inkLight,
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

    if (widget.vm.lastImportWasDuplicate) {
      widget.vm.lastImportWasDuplicate = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '⚠️ Already Imported — this syllabus was uploaded before.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.warn,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(borderRadius: AppColors.r12),
        ),
      );
      return;
    }

    if (widget.vm.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.vm.error!),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppColors.r12),
        ),
      );
    }
  }

  void _confirmDelete(BuildContext context, dynamic workspace) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppColors.r14),
        title: const Text(
          'Delete Workspace',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        content: Text(
          'Delete "${workspace.title}"?\nThis permanently removes all sections, students, and files.',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: AppColors.r10),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isReady ? AppColors.accentSoft : AppColors.warnSoft,
        borderRadius: AppColors.r20,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isReady ? AppColors.accent : AppColors.warn,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isReady ? 'Ready' : 'Draft',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isReady ? const Color(0xFF007A63) : AppColors.warn,
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
              color: dragOver ? AppColors.primarySoft : AppColors.surfaceAlt,
              borderRadius: AppColors.r16,
              border: Border.all(
                color: dragOver ? AppColors.primary : AppColors.border,
                width: dragOver ? 2 : 1.5,
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
                  style: TextStyle(color: AppColors.inkLight, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
