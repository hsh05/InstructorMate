// lib/ui/workspaces_home.dart
import 'package:flutter/material.dart';
import '../app/state/workspaces_vm.dart';

class WorkspacesHome extends StatelessWidget {
  const WorkspacesHome({super.key, required this.vm});
  final WorkspacesViewModel vm;

  // ===== Color System (kept from your design language) =====
  static const Color bgTop = Color(0xFFF4EDFF);
  static const Color bgBottom = Color(0xFFE9DFFF);
  static const Color cardSoft = Color(0xFFF6F0FF);

  static const Color primary = Color(0xFF8E6BD8);
  static const Color primaryDark = Color(0xFF7A57C8);

  static const Color textPrimary = Color(0xFF2E2E3A);
  static const Color textSecondary = Color(0xFF7C7C93);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: vm,
      builder: (_, __) {
        return Scaffold(
          backgroundColor: bgBottom,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: bgTop,
            title: const Text(
              "InstructorMate",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: "Import syllabus",
                icon: vm.importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded),
                onPressed: vm.importing
                    ? null
                    : () async {
                        await vm.importSyllabus();
                        if (vm.error != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(vm.error!)),
                          );
                        }
                      },
              ),
            ],
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [bgTop, bgBottom],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: _buildBody(context),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    if (vm.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (vm.error != null && vm.workspaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            vm.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    if (vm.workspaces.isEmpty) {
      return _emptyState(context);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: vm.workspaces.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final workspace = vm.workspaces[index];
        return _workspaceCard(context, workspace);
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_rounded,
                size: 52, color: primary),
            const SizedBox(height: 14),
            const Text(
              "No Course Workspaces Yet",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Import a syllabus (PDF, DOCX, or TXT).\nA workspace will be created and saved.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: vm.importing
                  ? null
                  : () async {
                      await vm.importSyllabus();
                      if (vm.error != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(vm.error!)),
                        );
                      }
                    },
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text(
                "Import Syllabus",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspaceCard(BuildContext context, dynamic workspace) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        await vm.openWorkspace(workspace.id);
        if (context.mounted && vm.current != null) {
          Navigator.of(context).pushNamed("/workspace");
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardSoft,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: primary.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.school_rounded, color: primary, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workspace.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Imported: ${workspace.createdAt}",
                    style: const TextStyle(
                      fontSize: 12,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: textSecondary),
          ],
        ),
      ),
    );
  }
}
