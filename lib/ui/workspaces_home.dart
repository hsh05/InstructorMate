// lib/ui/workspaces_home.dart — tap navigates instantly, no await on openWorkspace
import 'dart:async';
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
                          strokeWidth: 2, color: Colors.white),
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
          child: Text(widget.vm.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
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
              itemBuilder: (_, i) {
                final ws = widget.vm.workspaces[i];
                if (ws.isProcessing) {
                  return _PollingWorkspaceCard(
                    key: ValueKey(ws.id),
                    workspace: ws,
                    vm: widget.vm,
                    onReady: () => setState(() {}),
                    onDelete: () => _confirmDelete(context, ws),
                  );
                }
                return _WorkspaceCard(
                  workspace: ws,
                  onTap: () => _openWorkspace(context, ws.id),
                  onDelete: () => _confirmDelete(context, ws),
                );
              },
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

  // ── Instant open — no await ───────────────────────────────────────────────
  void _openWorkspace(BuildContext context, String id) {
    widget.vm.openWorkspace(id);
    Navigator.of(context).pushNamed('/workspace');
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

    // ── Duplicate ─────────────────────────────────────────────────────────
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
                                color: AppColors.primary.withOpacity(0.2)),
                          ),
                          child: Row(children: [
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
                                            ? const Color(0xFF22C55E)
                                            : const Color(0xFFAAAAAA),
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
                            backgroundColor: AppColors.primary,
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.vm.error!),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    // ── Success ───────────────────────────────────────────────────────────
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
        SizedBox(width: 8),
        Text('Syllabus imported — processing in background…'),
      ]),
      backgroundColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _confirmDelete(BuildContext context, WorkspaceSummary workspace) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Workspace',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        content: Text(
          'Delete "${workspace.title.isNotEmpty ? workspace.title : "this workspace"}"?\nThis permanently removes all sections, students, and files.',
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
              final title =
                  workspace.title.isNotEmpty ? workspace.title : 'Workspace';
              final ok = await widget.vm.deleteWorkspace(workspace.id);
              if (!context.mounted) return;
              if (ok) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Row(children: [
                    const Icon(Icons.delete_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '"$title" deleted successfully',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  backgroundColor: AppColors.inkMid,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(widget.vm.error ?? 'Delete failed'),
                  backgroundColor: AppColors.red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
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
  final VoidCallback onReady;
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
      final fresh = await widget.vm.api.getWorkspace(widget.workspace.id);
      if (!mounted) return;
      if (!fresh.isProcessing) {
        _timer?.cancel();
        widget.vm.updateWorkspaceSummary(fresh.toSummary());
        widget.onReady();
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
            Color.lerp(AppColors.border, AppColors.surfaceAlt, _shimmer.value)!;
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
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
                      color: AppColors.primary.withOpacity(0.4), size: 22),
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
                            color: AppColors.primarySoft,
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
                                  color: AppColors.primary
                                      .withOpacity(0.6 + _shimmer.value * 0.4),
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text('Processing…',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
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
                      color: AppColors.inkMid, size: 20),
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
                            color: AppColors.red, size: 18),
                        SizedBox(width: 10),
                        Text('Delete',
                            style: TextStyle(
                                color: AppColors.red,
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
    final timeAgo = workspace.updatedAtRaw?.isNotEmpty == true
        ? _timeAgo(workspace.updatedAt!)
        : null;

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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.school_rounded,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.title.isNotEmpty
                          ? workspace.title
                          : 'Untitled Course',
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
                    Row(children: [
                      _StatusBadge(status: workspace.status),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${workspace.sectionsCount} ${workspace.sectionsCount == 1 ? "Section" : "Sections"} · ${workspace.studentsCount} ${workspace.studentsCount == 1 ? "Student" : "Students"}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkMid,
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
                          color: AppColors.inkLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded,
                    color: AppColors.inkMid, size: 20),
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
                          color: AppColors.red, size: 18),
                      SizedBox(width: 10),
                      Text('Delete',
                          style: TextStyle(
                              color: AppColors.red,
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

  String? _timeAgoFromString(String raw) {
    if (raw.isEmpty) return null;
    try {
      return _timeAgo(DateTime.parse(raw));
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isReady ? AppColors.accentSoft : AppColors.warnSoft,
        borderRadius: BorderRadius.circular(20),
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
              color:
                  isReady ? const Color(0xFF007A63) : const Color(0xFFB36200),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Drop Zone ────────────────────────────────────────────────────────────────
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
                            strokeWidth: 2.5, color: AppColors.primary),
                      ),
                      SizedBox(height: 10),
                      Text('Importing syllabus…',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
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
                        dragOver
                            ? 'Drop to upload'
                            : 'Drag & drop a PDF/DOCX here',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      const Text('or tap to browse — PDF, DOCX',
                          style: TextStyle(
                              color: AppColors.inkLight, fontSize: 12)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
