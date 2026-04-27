// lib/screens/workspace/workspace_home.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../state/workspaces_vm.dart';
import '../../models/workspace_model.dart';
import '../../app_styles.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/custom_app_bar.dart';

class WorkspacesHome extends StatefulWidget {
  const WorkspacesHome({super.key});

  @override
  State<WorkspacesHome> createState() => _WorkspacesHomeState();
}

class _WorkspacesHomeState extends State<WorkspacesHome> {

  @override
  void initState() {
    super.initState();
    // Fetch the VM once to load initial data without listening for changes here
    context.read<WorkspacesViewModel>().load(); 
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(message, overflow: TextOverflow.ellipsis)),
      ]),
      backgroundColor: AppStyles.accent, 
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
      backgroundColor: AppStyles.error, 
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
      backgroundColor: AppStyles.darkGray, 
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Watch the VM so the UI rebuilds whenever workspaces change
    final vm = context.watch<WorkspacesViewModel>();

    return Scaffold(
      backgroundColor: AppStyles.lightGray, 
      appBar: CustomAppBar(
        title: 'InstructorMate',
        showBackButton: false,
        actions: [
          const NotificationBell(),
          const SizedBox(width: 8), 
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () async {
                const storage = FlutterSecureStorage();
                final realUserId = await storage.read(key: 'user_id') ?? '';
                
                if (context.mounted) {
                  Navigator.pushNamed(context, '/profile', arguments: realUserId);
                }
              },
              child: const CircleAvatar(
                radius: 15,
                backgroundColor: AppStyles.primary, 
                child: Icon(Icons.person_rounded, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      
      floatingActionButton: FloatingActionButton.extended(
        onPressed: vm.importing ? null : _pickFile,
        icon: vm.importing
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add_rounded),
        label: Text(
          vm.importing ? 'Importing...' : 'Add Workspace',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppStyles.primary, 
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppStyles.mediumGray, AppStyles.lightGray], 
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _buildBody(context, vm),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WorkspacesViewModel vm) {
    if (vm.loading && vm.workspaces.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppStyles.primary)); 
    }
    if (vm.error != null && vm.workspaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(vm.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppStyles.error)), 
        ),
      );
    }

    if (vm.workspaces.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), 
        itemCount: vm.workspaces.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final ws = vm.workspaces[i];
          
          final isStillProcessing = ws.isProcessing || ws.title.toLowerCase().contains('untitled');

          if (isStillProcessing) {
            return _PollingWorkspaceCard(
              key: ValueKey(ws.id),
              workspace: ws,
              vm: vm,
              onReady: (title) => _showSuccess(
                '"$title" imported successfully ✓',
              ),
              onDelete: () => _confirmDelete(context, ws, vm),
            );
          }
          return _WorkspaceCard(
            workspace: ws,
            onTap: () => _openWorkspace(context, ws.id.toString(), vm),
            onDelete: () => _confirmDelete(context, ws, vm),
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
            style: TextStyle(color: AppStyles.darkGray, fontSize: 14), 
          ),
        ),
      );
    }
  }

  // ── Instant open — no await ───────────────────────────────────────────────
  void _openWorkspace(BuildContext context, String id, WorkspacesViewModel vm) {
    vm.openWorkspace(int.parse(id));
    Navigator.of(context).pushNamed('/workspace');
  }

  Future<void> _pickFile() async {
    final vm = context.read<WorkspacesViewModel>();
    if (vm.importing) return;

    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'txt'],
      withData: true,
    );
    
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null) return;

    final DateTimeRange? pickedDates = await showDateRangePicker(
      context: context,
      helpText: 'SELECT SEMESTER DATES (REQUIRED)',
      saveText: 'UPLOAD & CREATE', 
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      firstDate: DateTime.now().subtract(const Duration(days: 365)), 
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),   
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppStyles.primary, 
              onPrimary: Colors.white,
              surface: AppStyles.white, 
              onSurface: AppStyles.textPrimary, 
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDates == null) {
      _showError("Semester dates are required to create a workspace.");
      return;
    }
    
    await _importBytes(f.bytes!, f.name, pickedDates);
  }

  Future<void> _importBytes(Uint8List bytes, String filename, DateTimeRange dates) async {
    final vm = context.read<WorkspacesViewModel>();
    final startStr = dates.start.toIso8601String().split('T').first;
    final endStr = dates.end.toIso8601String().split('T').first;

    await vm.importSyllabusBytes(
      bytes: bytes, 
      filename: filename,
      startDate: startStr,
      endDate: endStr,
    );

    if (!mounted) return;

    if (vm.current != null) {
      await vm.updateFields({
        'start_date': startStr,
        'end_date': endStr,
      });
    }

    // ── Duplicate ─────────────────────────────────────────────────────────
    if (vm.lastImportWasDuplicate) {
      vm.lastImportWasDuplicate = false;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.6),
        builder: (ctx) {
          final ws = vm.current;
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
                                color: AppStyles.primary.withOpacity(0.2)), 
                          ),
                          child: Row(children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppStyles.primary.withOpacity(0.12), 
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.school_rounded,
                                  color: AppStyles.primary, size: 20), 
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
                                            ? AppStyles.success 
                                            : AppStyles.darkGray, 
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
                            backgroundColor: AppStyles.primary, 
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
    if (vm.error != null) {
      _showError(vm.error!);
      return;
    }

    // ── Success — workspace queued for processing ─────────────────────────
    _showInfo('Syllabus imported — processing in background…');
  }

  // ── Delete confirmation ───────────────────────────────────────────────────
  void _confirmDelete(BuildContext context, WorkspaceSummary workspace, WorkspacesViewModel vm) {
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
                  color: AppStyles.error.withOpacity(0.06), 
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
                        color: AppStyles.error.withOpacity(0.12), 
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: AppStyles.error, size: 22), 
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
                              color: AppStyles.darkGray, 
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
                        color: AppStyles.darkGray, 
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
                        foregroundColor: AppStyles.darkGray, 
                        side: const BorderSide(color: AppStyles.borderLight), 
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
                        backgroundColor: AppStyles.error, 
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
                            await vm.deleteWorkspace(workspace.id);
                        if (!mounted) return;
                        if (ok) {
                          _showInfo(
                              '"${workspace.title.isNotEmpty ? workspace.title : "Workspace"}" deleted');
                        } else {
                          _showError(
                              vm.error ?? 'Failed to delete workspace');
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
            color: AppStyles.error.withOpacity(0.08), 
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppStyles.error, size: 14), 
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppStyles.textPrimary, 
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
            Color.lerp(AppStyles.borderLight, AppStyles.lightGray, _shimmer.value)!; 
        return Material(
          color: AppStyles.white, 
          borderRadius: BorderRadius.circular(16),
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppStyles.borderLight), 
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
                      color: AppStyles.primary.withOpacity(0.4), size: 22), 
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
                            color: AppStyles.mediumGray, 
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
                                  color: AppStyles.primary 
                                      .withOpacity(0.6 + _shimmer.value * 0.4),
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text('Processing…',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppStyles.primary, 
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
                      color: AppStyles.darkGray, size: 20), 
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
                            color: AppStyles.error, size: 18), 
                        SizedBox(width: 10),
                        Text('Delete',
                            style: TextStyle(
                                color: AppStyles.error, 
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
      color: AppStyles.white, 
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppStyles.borderLight), 
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppStyles.mediumGray, 
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.school_rounded,
                    color: AppStyles.primary, size: 24), 
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
                        color: AppStyles.textPrimary, 
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
                            color: AppStyles.darkGray, 
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
                          color: AppStyles.darkGray, 
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded,
                    color: AppStyles.darkGray, size: 20), 
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
                          color: AppStyles.error, size: 18), 
                      SizedBox(width: 10),
                      Text('Delete',
                          style: TextStyle(
                              color: AppStyles.error, 
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
        color: isReady ? AppStyles.readyBg : AppStyles.draftBg, 
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isReady ? AppStyles.readyDot : AppStyles.draftDot, 
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isReady ? 'Ready' : 'Draft',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isReady ? AppStyles.readyFg : AppStyles.draftFg, 
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
