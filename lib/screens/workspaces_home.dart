// lib/screens/workspaces_home.dart — tap navigates instantly, no await on openWorkspace
import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../app/state/workspaces_vm.dart';
import '../models/workspace_model.dart';
import '../app_styles.dart';
import 'widgets/notification_bell.dart';

class WorkspacesHome extends StatefulWidget {
  const WorkspacesHome({super.key, required this.vm});
  final WorkspacesViewModel vm;

  @override
  State<WorkspacesHome> createState() => _WorkspacesHomeState();
}

class _WorkspacesHomeState extends State<WorkspacesHome> {
  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(message, overflow: TextOverflow.ellipsis)),
      ]),
      backgroundColor: AppStyles.accent, // Keeps teal accent
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(message, overflow: TextOverflow.ellipsis)),
      ]),
      backgroundColor: AppStyles.error, // Mapped from red
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.info_outline_rounded, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(message, overflow: TextOverflow.ellipsis)),
      ]),
      backgroundColor: AppStyles.darkGray, // Mapped from inkMid
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (_, __) => Scaffold(
        backgroundColor: AppStyles.lightGray, // Mapped from bg
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppStyles.primaryPurple, // Mapped from primary
          title: const Text(
            'InstructorMate',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
          actions: const [
            NotificationBell(),
            SizedBox(width: 8), // Small padding so the bell isn't pushed to the edge
          ],
        ),
        
        // 👉 ADDED: Floating Action Button in the bottom right corner
        floatingActionButton: FloatingActionButton.extended(
          onPressed: widget.vm.importing ? null : _pickFile,
          icon: widget.vm.importing
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.add_rounded),
          label: Text(
            widget.vm.importing ? 'Importing...' : 'Add Workspace',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: AppStyles.primaryPurple, // Mapped from primary
          foregroundColor: Colors.white,
          elevation: 4,
        ),

        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppStyles.mediumGray, AppStyles.lightGray], // Mapped from bgTop, bg
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
          child: CircularProgressIndicator(color: AppStyles.primaryPurple)); // Mapped
    }
    if (widget.vm.error != null && widget.vm.workspaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(widget.vm.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppStyles.error)), // Mapped
        ),
      );
    }

    if (widget.vm.workspaces.isNotEmpty) {
      return ListView.separated(
        // 👉 Added 80px of bottom padding so the FAB doesn't cover the last card
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), 
        itemCount: widget.vm.workspaces.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final ws = widget.vm.workspaces[i];
          
          final isStillProcessing = ws.isProcessing || ws.title.toLowerCase().contains('untitled');

          if (isStillProcessing) {
            return _PollingWorkspaceCard(
              key: ValueKey(ws.id),
              workspace: ws,
              vm: widget.vm,
              onReady: (title) => _showSuccess(
                '"$title" imported successfully ✓',
              ),
              onDelete: () => _confirmDelete(context, ws),
            );
          }
          return _WorkspaceCard(
            workspace: ws,
            onTap: () => _openWorkspace(context, ws.id.toString()),
            onDelete: () => _confirmDelete(context, ws),
          );
        },
      );
    } else {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Tap "+ Add Workspace" below to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppStyles.darkGray, fontSize: 14), // Mapped from inkLight
          ),
        ),
      );
    }
  }

  // ── Instant open — no await ───────────────────────────────────────────────
  void _openWorkspace(BuildContext context, String id) {
    widget.vm.openWorkspace(int.parse(id));
    Navigator.of(context).pushNamed('/workspace');
  }

  Future<void> _pickFile() async {
    if (widget.vm.importing) return;

    // 👉 1. Let the user pick the syllabus file FIRST
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'txt'],
      withData: true,
    );
    
    // If they cancel the file picker, just stop here
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null) return;

    // 👉 2. Pop up the Date Range Picker AFTER the file is selected
    final DateTimeRange? pickedDates = await showDateRangePicker(
      context: context,
      helpText: 'SELECT SEMESTER DATES (REQUIRED)',
      saveText: 'UPLOAD & CREATE', // Changed the button text to make the action clear
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      firstDate: DateTime.now().subtract(const Duration(days: 365)), 
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),   
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppStyles.primaryPurple, // Mapped
              onPrimary: Colors.white,
              surface: AppStyles.white, // Mapped
              onSurface: AppStyles.textPrimary, // Mapped
            ),
          ),
          child: child!,
        );
      },
    );

    // 👉 3. If they cancel the dates, we safely abort the upload BEFORE hitting the database
    if (pickedDates == null) {
      _showError("Semester dates are required to create a workspace.");
      return;
    }
    
    // 👉 4. Both file and dates are secure, send them to the server!
    await _importBytes(f.bytes!, f.name, pickedDates);
  }

  // 👉 Notice we added the `dates` parameter here
  Future<void> _importBytes(Uint8List bytes, String filename, DateTimeRange dates) async {
    final startStr = dates.start.toIso8601String().split('T').first;
    final endStr = dates.end.toIso8601String().split('T').first;

    await widget.vm.importSyllabusBytes(
      bytes: bytes, 
      filename: filename,
      startDate: startStr,
      endDate: endStr,
    );

    if (!mounted) return;

    if (widget.vm.current != null) {
      await widget.vm.updateFields({
        'start_date': startStr,
        'end_date': endStr,
      });
    }

    // ── Duplicate ─────────────────────────────────────────────────────────
    if (widget.vm.lastImportWasDuplicate) {
      widget.vm.lastImportWasDuplicate = false;
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
                      offset: const Offset(0, 16)),
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
                    child: Column(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEDC2),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFFFFD080), width: 1.5),
                        ),
                        child: const Icon(Icons.file_copy_rounded,
                            color: Color(0xFFE6920A), size: 24),
                      ),
                      const SizedBox(height: 12),
                      const Text('Duplicate Syllabus',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A2E),
                              letterSpacing: -0.3)),
                      const SizedBox(height: 4),
                      const Text('This file was already imported',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF888888),
                              fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Found existing workspace:',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFAAAAAA),
                                letterSpacing: 0.5)),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F0FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: AppStyles.primaryPurple.withOpacity(0.2)), // Mapped
                          ),
                          child: Row(children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppStyles.primaryPurple.withOpacity(0.12), // Mapped
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.school_rounded,
                                  color: AppStyles.primaryPurple, size: 20), // Mapped
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ws?.title.isNotEmpty == true
                                        ? ws!.title
                                        : filename,
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
                                            ? AppStyles.success // Mapped to success
                                            : AppStyles.darkGray, // Mapped to darkGray
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Row(children: [
                      Expanded(
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0xFFE0E0E0)),
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
                            backgroundColor: AppStyles.primaryPurple, // Mapped
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon:
                              const Icon(Icons.arrow_forward_rounded, size: 16),
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
                    ]),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    // ── Error ─────────────────────────────────────────────────────────────
    if (widget.vm.error != null) {
      _showError(widget.vm.error!);
      return;
    }

    // 👉 4. THE FIX: Immediately save the required dates to the new workspace!
    // As soon as the workspace is created on the server, we silently patch it with the dates
    if (widget.vm.current != null) {
      await widget.vm.updateFields({
        'start_date': dates.start.toIso8601String().split('T').first,
        'end_date': dates.end.toIso8601String().split('T').first,
      });
    }

    // ── Success — workspace queued for processing ─────────────────────────
    _showInfo('Syllabus imported — processing in background…');
  }

  // ── Delete confirmation ───────────────────────────────────────────────────
  void _confirmDelete(BuildContext context, WorkspaceSummary workspace) {
    final title =
        workspace.title.isNotEmpty ? workspace.title : 'this workspace';
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ───────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: BoxDecoration(
                  color: AppStyles.error.withOpacity(0.06), // Mapped
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppStyles.error.withOpacity(0.12), // Mapped
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: AppStyles.error, size: 22), // Mapped
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Delete Workspace',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A2E),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '"$title"',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppStyles.darkGray, // Mapped
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── Body ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This action is permanent and cannot be undone. The following will be removed:',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppStyles.darkGray, // Mapped
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _DeleteBullet(
                        icon: Icons.groups_2_outlined,
                        label:
                            '${workspace.sectionsCount} section${workspace.sectionsCount == 1 ? "" : "s"}'),
                    const SizedBox(height: 6),
                    _DeleteBullet(
                        icon: Icons.people_outline_rounded,
                        label:
                            '${workspace.studentsCount} student${workspace.studentsCount == 1 ? "" : "s"}'),
                  ],
                ),
              ),
              // ── Actions ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppStyles.darkGray, // Mapped
                        side: const BorderSide(color: AppStyles.borderLight), // Mapped
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppStyles.error, // Mapped
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.delete_rounded, size: 16),
                      label: const Text('Delete Permanently',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      onPressed: () async {
                        Navigator.pop(context);
                        final ok =
                            await widget.vm.deleteWorkspace(workspace.id);
                        if (!mounted) return;
                        if (ok) {
                          _showInfo(
                              '"${workspace.title.isNotEmpty ? workspace.title : "Workspace"}" deleted');
                        } else {
                          _showError(
                              widget.vm.error ?? 'Failed to delete workspace');
                        }
                      },
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Delete bullet item ───────────────────────────────────────────────────────
class _DeleteBullet extends StatelessWidget {
  const _DeleteBullet({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppStyles.error.withOpacity(0.08), // Mapped
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppStyles.error, size: 14), // Mapped
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppStyles.textPrimary, // Mapped
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ]);
}

// ─── Polling wrapper for processing cards ─────────────────────────────────────
class _PollingWorkspaceCard extends StatefulWidget {
  const _PollingWorkspaceCard({
    super.key,
    required this.workspace,
    required this.vm,
    required this.onReady,
    required this.onDelete,
  });
  final WorkspaceSummary workspace;
  final WorkspacesViewModel vm;
  final void Function(String title) onReady;
  final VoidCallback onDelete;

  @override
  State<_PollingWorkspaceCard> createState() => _PollingWorkspaceCardState();
}

class _PollingWorkspaceCardState extends State<_PollingWorkspaceCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final fresh = await widget.vm.api.getWorkspace(widget.workspace.id.toString());
      if (!mounted) return;
      
      final stillProcessing = fresh.isProcessing || fresh.title.toLowerCase().contains('untitled');

      if (!stillProcessing) {
        _timer?.cancel();
        widget.vm.updateWorkspaceSummary(fresh.toSummary());
        // Pass the resolved title so the snackbar can show the workspace name
        widget.onReady(
          fresh.title.isNotEmpty ? fresh.title : 'workspace',
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) =>
      _ProcessingCard(onDelete: widget.onDelete);
}

// ─── Processing card ──────────────────────────────────────────────────────────
class _ProcessingCard extends StatefulWidget {
  const _ProcessingCard({required this.onDelete});
  final VoidCallback onDelete;

  @override
  State<_ProcessingCard> createState() => _ProcessingCardState();
}

class _ProcessingCardState extends State<_ProcessingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) {
        final shimmerColor =
            Color.lerp(AppStyles.borderLight, AppStyles.lightGray, _shimmer.value)!; // Mapped
        return Material(
          color: AppStyles.white, // Mapped
          borderRadius: BorderRadius.circular(16),
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppStyles.borderLight), // Mapped
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: shimmerColor,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.hourglass_top_rounded,
                      color: AppStyles.primaryPurple.withOpacity(0.4), size: 22), // Mapped
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 160,
                        decoration: BoxDecoration(
                          color: shimmerColor,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppStyles.mediumGray, // Mapped
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 8,
                                height: 8,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: AppStyles.primaryPurple // Mapped
                                      .withOpacity(0.6 + _shimmer.value * 0.4),
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text('Processing…',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppStyles.primaryPurple, // Mapped
                                      letterSpacing: 0.2)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          height: 10,
                          width: 80,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded,
                      color: AppStyles.darkGray, size: 20), // Mapped
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 3,
                  onSelected: (val) {
                    if (val == 'delete') widget.onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: const [
                        Icon(Icons.delete_outline_rounded,
                            color: AppStyles.error, size: 18), // Mapped
                        SizedBox(width: 10),
                        Text('Delete',
                            style: TextStyle(
                                color: AppStyles.error, // Mapped
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Regular Workspace Card ───────────────────────────────────────────────────
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
    final updatedAt = workspace.updatedAt;
    final createdAt = workspace.createdAt.isNotEmpty
        ? DateTime.tryParse(workspace.createdAt)
        : null;
    final timeAgo = (updatedAt != null &&
            (createdAt == null ||
                updatedAt.difference(createdAt).inSeconds >= 5))
        ? _timeAgo(updatedAt)
        : null;

    return Material(
      color: AppStyles.white, // Mapped
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppStyles.borderLight), // Mapped
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppStyles.mediumGray, // Mapped
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.school_rounded,
                    color: AppStyles.primaryPurple, size: 24), // Mapped
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.title.isNotEmpty
                          ? workspace.title
                          : 'Untitled workspace',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppStyles.textPrimary, // Mapped
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(children: [
                      _StatusBadge(status: workspace.status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${workspace.sectionsCount} ${workspace.sectionsCount == 1 ? "Section" : "Sections"} · ${workspace.studentsCount} ${workspace.studentsCount == 1 ? "Student" : "Students"}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppStyles.darkGray, // Mapped
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                    if (timeAgo != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last Updated: $timeAgo',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppStyles.darkGray, // Mapped
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded,
                    color: AppStyles.darkGray, size: 20), // Mapped
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 3,
                onSelected: (val) {
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: const [
                      Icon(Icons.delete_outline_rounded,
                          color: AppStyles.error, size: 18), // Mapped
                      SizedBox(width: 10),
                      Text('Delete',
                          style: TextStyle(
                              color: AppStyles.error, // Mapped
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ]),
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
    return '${(diff.inDays / 30).floor()}mo ago';
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
        color: isReady ? AppStyles.readyBg : AppStyles.draftBg, // Mapped to team design badge colors
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isReady ? AppStyles.readyDot : AppStyles.draftDot, // Mapped
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isReady ? 'Ready' : 'Draft',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isReady ? AppStyles.readyFg : AppStyles.draftFg, // Mapped
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}