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
  // Lighter palette
  static const bg = Color(0xFFF5F2FF);
  static const bgTop = Color(0xFFEDE8FF);
  static const cardSoft = Color(0xFFFFFFFF);
  static const primary = Color(0xFF7C5CBF);
  static const textPrimary = Color(0xFF2D2640);
  static const textSecondary = Color(0xFF7B748F);
  static const red = Color(0xFFD93025);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (_, __) => Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: bgTop,
          title: const Text(
            'Workspaces',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: textPrimary,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          actions: [const NotificationBell()],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [bgTop, bg],
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
    if (widget.vm.loading)
      return const Center(child: CircularProgressIndicator(color: primary));

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
        // Upload info banner
        _UploadBanner(onTap: _pickFile, importing: widget.vm.importing),
        // List
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
                  'Tap "Upload Syllabus" above to import your first course.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSecondary, fontSize: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _workspaceCard(BuildContext context, dynamic workspace) {
    return Material(
      color: cardSoft,
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
                  color: primary,
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
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Imported: ${workspace.createdAt}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Delete
              IconButton(
                tooltip: 'Delete workspace',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: red,
                  size: 20,
                ),
                onPressed: () => _confirmDelete(context, workspace),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: textSecondary,
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
    if (widget.vm.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.vm.error!),
          backgroundColor: red,
          behavior: SnackBarBehavior.floating,
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
          style: const TextStyle(fontSize: 13, color: textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: red,
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
                    backgroundColor: red,
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

// ─── Upload Banner ────────────────────────────────────────────────────────────
class _UploadBanner extends StatelessWidget {
  const _UploadBanner({required this.onTap, required this.importing});
  final VoidCallback onTap;
  final bool importing;

  static const primary = Color(0xFF7C5CBF);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F0FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFBFB0E8), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDD8F5)),
              ),
              child: const Icon(
                Icons.upload_file_rounded,
                color: primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Import a syllabus',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Supported formats: PDF, DOCX, TXT',
                    style: TextStyle(color: Color(0xFF9B96B0), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: importing ? null : onTap,
              child: importing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Upload',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
