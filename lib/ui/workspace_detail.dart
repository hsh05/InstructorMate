// lib/ui/workspace_detail.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../app/state/workspaces_vm.dart';
import '../app/workspace_models.dart';
import '../config/app_colors.dart';
import 'widgets/notification_bell.dart';

const _fieldLabels = {
  'course_name': 'Course Name',
  'course_code': 'Course Code',
  'semester': 'Semester',
};
const _fieldIcons = {
  'course_name': Icons.book_rounded,
  'course_code': Icons.tag_rounded,
  'semester': Icons.calendar_today_rounded,
};

// ─── Main page ────────────────────────────────────────────────────────────────
class WorkspaceDetailPage extends StatefulWidget {
  const WorkspaceDetailPage({super.key, required this.vm});
  final WorkspacesViewModel vm;

  @override
  State<WorkspaceDetailPage> createState() => _WorkspaceDetailPageState();
}

class _WorkspaceDetailPageState extends State<WorkspaceDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final Map<String, TextEditingController> _fieldCtrl = {};

  final _askCtrl = TextEditingController();
  final _askScroll = ScrollController();
  final List<_ChatMsg> _chat = [];
  bool _asking = false;

  static const _editableKeys = [
    'course_name',
    'course_code',
    'semester',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _syncControllersFromWorkspace();
  }

  @override
  void didUpdateWidget(WorkspaceDetailPage old) {
    super.didUpdateWidget(old);
    if (old.vm.current != widget.vm.current) {
      _syncControllersFromWorkspace();
    }
  }

  void _syncControllersFromWorkspace() {
    final ws = widget.vm.current;
    if (ws == null) return;

    for (final key in _editableKeys) {
      String value = ws.fields[key] ?? '';
      if (key == 'course_name' && value.isEmpty) {
        value = ws.fields['course_title'] ?? '';
      }
      final existing = _fieldCtrl[key];
      if (existing == null) {
        _fieldCtrl[key] = TextEditingController(text: value);
      } else if (existing.text != value) {
        existing.text = value;
      }
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _askCtrl.dispose();
    _askScroll.dispose();
    for (final c in _fieldCtrl.values) c.dispose();
    super.dispose();
  }

  TextEditingController _ctrl(String key, String value) {
    final existing = _fieldCtrl[key];
    if (existing == null) {
      final c = TextEditingController(text: value);
      _fieldCtrl[key] = c;
      return c;
    }
    return existing;
  }

  bool _isReady(Workspace ws) => ws.isReady;

  List<String> _missingFields(Workspace ws) =>
      _editableKeys.where((k) => (ws.fields[k] ?? '').trim().isEmpty).toList();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (_, __) {
        final ws = widget.vm.current;
        if (ws == null) {
          return const Scaffold(
            backgroundColor: AppColors.bg,
            body: Center(child: Text('No workspace selected.')),
          );
        }

        if (!widget.vm.loadingDetail) {
          _syncControllersFromWorkspace();
        }

        final ready = _isReady(ws);
        final missing =
            widget.vm.loadingDetail ? <String>[] : _missingFields(ws);

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: NestedScrollView(
              headerSliverBuilder: (_, __) => [_buildHeader(ws, ready)],
              body: Column(
                children: [
                  // ── Tab bar ────────────────────────────────────────────
                  Container(
                    color: AppColors.surface,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: AppColors.r20,
                      ),
                      padding: const EdgeInsets.all(3),
                      child: TabBar(
                        controller: _tabs,
                        indicator: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: AppColors.r16,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: AppColors.inkMid,
                        labelStyle: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 11),
                        unselectedLabelStyle: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 11),
                        tabs: const [
                          Tab(
                              icon: Icon(Icons.info_outline_rounded, size: 16),
                              text: 'Info'),
                          Tab(
                              icon: Icon(Icons.groups_2_rounded, size: 16),
                              text: 'Sections'),
                          Tab(
                              icon: Icon(Icons.people_alt_rounded, size: 16),
                              text: 'Students'),
                          Tab(
                              icon: Icon(Icons.auto_awesome_rounded, size: 16),
                              text: 'Ask AI'),
                        ],
                      ),
                    ),
                  ),
                  if (!ready && missing.isNotEmpty && !widget.vm.loadingDetail)
                    _MissingBanner(fields: missing),
                  // ── Tab content ────────────────────────────────────────
                  Expanded(
                    child: widget.vm.loadingDetail
                        ? const _DetailSkeleton()
                        : widget.vm.loading
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.primary),
                              )
                            : TabBarView(
                                controller: _tabs,
                                children: [
                                  _InfoTab(
                                    ws: ws,
                                    editableKeys: _editableKeys,
                                    ctrl: _ctrl,
                                    onSave: _onSave,
                                  ),
                                  _SectionsTab(
                                    ws: ws,
                                    vm: widget.vm,
                                    onError: _showError,
                                    onNavigateToStudents: () =>
                                        _tabs.animateTo(2),
                                  ),
                                  _StudentsTab(
                                    ws: ws,
                                    vm: widget.vm,
                                    onError: _showError,
                                  ),
                                  _AskTab(
                                    chat: _chat,
                                    ctrl: _askCtrl,
                                    scrollCtrl: _askScroll,
                                    asking: _asking,
                                    onAsk: _onAsk,
                                  ),
                                ],
                              ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(Workspace ws, bool ready) {
    final totalStudents = widget.vm.totalStudentsCount;
    final sectionCount = ws.sections.length;
    final code = ws.fields['course_code'] ?? '';
    final semester = ws.fields['semester'] ?? '';

    return SliverAppBar(
      expandedHeight: 165,
      pinned: true,
      backgroundColor: AppColors.primaryDark,
      foregroundColor: Colors.white,
      actions: const [NotificationBell(), SizedBox(width: 4)],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryDark, Color(0xFF9B78E0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 44, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ws.title.isEmpty
                            ? _ShimmerBar(
                                width: 200,
                                height: 20,
                                light: Colors.white.withOpacity(0.15),
                                lighter: Colors.white.withOpacity(0.28),
                              )
                            : Text(
                                ws.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (ready ? AppColors.accent : AppColors.warn)
                              .withOpacity(0.2),
                          borderRadius: AppColors.r20,
                          border: Border.all(
                            color: ready ? AppColors.accent : AppColors.warn,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              ready
                                  ? Icons.check_circle_rounded
                                  : Icons.pending_rounded,
                              color: ready ? AppColors.accent : AppColors.warn,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ready ? 'Ready' : 'Draft',
                              style: TextStyle(
                                color:
                                    ready ? AppColors.accent : AppColors.warn,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (code.isNotEmpty) ...[
                          _StatPill(icon: Icons.tag_rounded, label: code),
                          const SizedBox(width: 8),
                        ],
                        if (semester.isNotEmpty) ...[
                          _StatPill(
                              icon: Icons.calendar_today_rounded,
                              label: semester),
                          const SizedBox(width: 8),
                        ],
                        _StatPill(
                          icon: Icons.groups_2_rounded,
                          label:
                              '$sectionCount section${sectionCount == 1 ? "" : "s"}',
                        ),
                        const SizedBox(width: 8),
                        _StatPill(
                          icon: Icons.people_alt_rounded,
                          label:
                              '$totalStudents student${totalStudents == 1 ? "" : "s"}',
                          highlight: totalStudents > 0,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    final updated = {
      for (final k in _editableKeys) k: (_fieldCtrl[k]?.text.trim() ?? ''),
    };
    await widget.vm.updateFields(updated);
    if (!mounted) return;
    if (widget.vm.error != null) {
      _showError(widget.vm.error!);
    } else {
      _syncControllersFromWorkspace();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Changes saved ✓'),
        backgroundColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppColors.r12),
      ));
    }
  }

  Future<void> _onAsk(String q) async {
    if (q.trim().isEmpty) return;
    setState(() {
      _chat.add(_ChatMsg(text: q, isUser: true));
      _asking = true;
    });
    _askCtrl.clear();
    _scrollChat();
    final answer = await widget.vm.askInWorkspace(q);
    setState(() {
      _chat.add(_ChatMsg(
        text: (widget.vm.error != null && widget.vm.error!.contains('chunks'))
            ? '⚠️ Syllabus not processed yet. Tap "Re-upload PDF" above.'
            : (answer ?? "Sorry, I couldn't get an answer."),
        isUser: false,
      ));
      _asking = false;
    });
    _scrollChat();
  }

  void _scrollChat() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_askScroll.hasClients) {
          _askScroll.animateTo(
            _askScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppColors.r12),
        ),
      );
}

// ─── Detail Skeleton ──────────────────────────────────────────────────────────
class _DetailSkeleton extends StatefulWidget {
  const _DetailSkeleton();

  @override
  State<_DetailSkeleton> createState() => _DetailSkeletonState();
}

class _DetailSkeletonState extends State<_DetailSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        final dim =
            Color.lerp(const Color(0xFFE8E8EE), const Color(0xFFF2F2F6), t)!;
        final bright =
            Color.lerp(const Color(0xFFDDDDE6), const Color(0xFFECECF2), t)!;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            Row(children: [
              _pill(bright, w: 16, h: 16, r: 8),
              const SizedBox(width: 8),
              _pill(bright, w: 110, h: 13),
            ]),
            const SizedBox(height: 6),
            _pill(bright, w: 200, h: 10),
            const SizedBox(height: 14),
            _skeletonCard(dim, bright, children: [
              _fieldRow(dim, bright),
              _divider(dim),
              _fieldRow(dim, bright),
              _divider(dim),
              _fieldRow(dim, bright),
            ]),
            const SizedBox(height: 22),
            Row(children: [
              _pill(bright, w: 16, h: 16, r: 8),
              const SizedBox(width: 8),
              _pill(bright, w: 90, h: 13),
              const Spacer(),
              _pill(bright, w: 80, h: 28, r: 14),
            ]),
            const SizedBox(height: 14),
            _skeletonCard(dim, bright, children: [_sectionRow(dim, bright)]),
            const SizedBox(height: 10),
            _skeletonCard(dim, bright,
                children: [_sectionRow(dim, bright, narrowName: true)]),
            const SizedBox(height: 28),
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: AppColors.primary.withOpacity(0.3 + t * 0.2),
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  'Fetching workspace…',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.inkLight.withOpacity(0.55 + t * 0.2),
                  ),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }

  Widget _pill(Color color, {required double w, double h = 12, double r = 6}) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(r),
        ),
      );

  Widget _divider(Color color) => Container(height: 1, color: color);

  Widget _skeletonCard(Color bg, Color hi, {required List<Widget> children}) =>
      Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppColors.r16,
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(children: children),
      );

  Widget _fieldRow(Color bg, Color hi) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: hi, borderRadius: AppColors.r10),
          ),
          const SizedBox(width: 13),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _pill(hi, w: 56, h: 10),
            const SizedBox(height: 6),
            _pill(hi, w: 148, h: 13),
          ]),
          const Spacer(),
          _pill(hi, w: 14, h: 14, r: 7),
        ]),
      );

  Widget _sectionRow(Color bg, Color hi, {bool narrowName = false}) => Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: hi, borderRadius: AppColors.r12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _pill(hi, w: narrowName ? 90.0 : 130.0, h: 13),
              const SizedBox(height: 7),
              Row(children: [
                _pill(hi, w: 20, h: 20, r: 10),
                const SizedBox(width: 5),
                _pill(hi, w: 60, h: 10),
              ]),
            ]),
          ),
          _pill(hi, w: 24, h: 24, r: 12),
        ]),
      );
}

// ─── Shimmer bar ──────────────────────────────────────────────────────────────
class _ShimmerBar extends StatefulWidget {
  const _ShimmerBar(
      {required this.width,
      required this.height,
      required this.light,
      required this.lighter});
  final double width, height;
  final Color light, lighter;

  @override
  State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(widget.light, widget.lighter, _c.value),
            borderRadius: BorderRadius.circular(widget.height / 2),
          ),
        ),
      );
}

// ── Stat pill ──────────────────────────────────────────────────────────────────
class _StatPill extends StatelessWidget {
  const _StatPill(
      {required this.icon, required this.label, this.highlight = false});
  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: highlight
              ? AppColors.accent.withOpacity(0.2)
              : Colors.white.withOpacity(0.15),
          borderRadius: AppColors.r20,
          border: Border.all(
            color: highlight
                ? AppColors.accent.withOpacity(0.5)
                : Colors.white.withOpacity(0.25),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              color: highlight ? AppColors.accent : Colors.white, size: 11),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: highlight ? AppColors.accent : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
      );
}

// ─── Missing banner ───────────────────────────────────────────────────────────
class _MissingBanner extends StatelessWidget {
  const _MissingBanner({required this.fields});
  final List<String> fields;

  @override
  Widget build(BuildContext context) {
    final labels = fields.map((k) => _fieldLabels[k] ?? k).join(', ');
    return Container(
      width: double.infinity,
      color: AppColors.warnSoft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded,
            color: AppColors.warn, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Complete: $labels',
            style: const TextStyle(
                color: AppColors.warn,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

// ─── TAB 1 — Info ─────────────────────────────────────────────────────────────
class _InfoTab extends StatefulWidget {
  const _InfoTab({
    required this.ws,
    required this.editableKeys,
    required this.ctrl,
    required this.onSave,
  });
  final Workspace ws;
  final List<String> editableKeys;
  final TextEditingController Function(String, String) ctrl;
  final Future<void> Function() onSave;

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

String? _validateField(String key, String value) {
  final v = value.trim();
  if (v.isEmpty) return '${_fieldLabels[key] ?? key} is required';
  return null;
}

const _numericKeys = {'allow_validation', 'capacity', 'max_students'};

class _InfoTabState extends State<_InfoTab>
    with AutomaticKeepAliveClientMixin<_InfoTab> {
  @override
  bool get wantKeepAlive => true;

  final Set<String> _editing = {};
  final Map<String, String?> _errors = {};
  bool _saving = false;
  bool _triedSave = false;
  bool _dirty = false;

  bool _validateAll() {
    _errors.clear();
    for (final key in widget.editableKeys) {
      final val = widget.ctrl(key, widget.ws.fields[key] ?? '').text;
      final err = _validateField(key, val);
      if (err != null) _errors[key] = err;
    }
    return _errors.isEmpty;
  }

  Future<void> _save() async {
    setState(() => _triedSave = true);
    if (!_validateAll()) {
      setState(() {});
      return;
    }
    setState(() {
      _saving = true;
      _editing.clear();
    });
    await widget.onSave();
    if (mounted) {
      setState(() {
        _saving = false;
        _triedSave = false;
        _dirty = false;
      });
    }
  }

  TextInputType _keyboardType(String key) {
    if (_numericKeys.contains(key)) return TextInputType.number;
    return TextInputType.text;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasEdits = _editing.isNotEmpty;
    final List<_FieldGroup> groups = [];
    for (final key in widget.editableKeys) {
      groups.add(_FieldGroup.single(key));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(
            title: 'Course Details', icon: Icons.info_outline_rounded),
        const SizedBox(height: 4),
        const Text('Tap any field to edit. All fields are required.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMid)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppColors.r16,
            boxShadow: AppColors.shadow,
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              ...groups.asMap().entries.map((entry) {
                final idx = entry.key;
                final group = entry.value;
                final isLast = idx == groups.length - 1;
                return Column(children: [
                  _InfoFieldRow(
                    fieldKey: group.key,
                    value: widget.ws.fields[group.key] ?? '',
                    ctrl: widget.ctrl,
                    isEditing: _editing.contains(group.key),
                    error: _errors[group.key],
                    keyboardType: _keyboardType(group.key),
                    onTap: () => setState(() {
                      _editing.add(group.key);
                      _dirty = true;
                    }),
                    onDone: () => setState(() {
                      _editing.remove(group.key);
                      if (_triedSave) {
                        _errors[group.key] = _validateField(
                            group.key, widget.ctrl(group.key, '').text);
                      }
                    }),
                  ),
                  if (!isLast)
                    const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: AppColors.border),
                ]);
              }),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: (hasEdits || _dirty || _saving || _triedSave)
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: const RoundedRectangleBorder(
                                  borderRadius: AppColors.r12),
                            ),
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.save_rounded, size: 17),
                            label: Text(_saving ? 'Saving…' : 'Save Changes',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        if (_triedSave && _errors.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warnSoft,
              borderRadius: AppColors.r12,
              border: Border.all(color: AppColors.warn.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: const [
                  Icon(Icons.warning_amber_rounded,
                      color: AppColors.warn, size: 15),
                  SizedBox(width: 6),
                  Text('Please fix the following:',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppColors.warn)),
                ]),
                const SizedBox(height: 6),
                ..._errors.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('• ${e.value}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.warn)),
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FieldGroup {
  final String key;
  final String? secondKey;
  bool get isPair => false;
  const _FieldGroup.single(this.key) : secondKey = null;
}

class _InfoFieldRow extends StatelessWidget {
  const _InfoFieldRow({
    required this.fieldKey,
    required this.value,
    required this.ctrl,
    required this.isEditing,
    required this.error,
    required this.keyboardType,
    required this.onTap,
    required this.onDone,
  });
  final String fieldKey;
  final String value;
  final TextEditingController Function(String, String) ctrl;
  final bool isEditing;
  final String? error;
  final TextInputType keyboardType;
  final VoidCallback onTap;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final label = _fieldLabels[fieldKey] ?? fieldKey;
    final icon = _fieldIcons[fieldKey] ?? Icons.edit_rounded;
    final liveValue = ctrl(fieldKey, value).text;
    final isEmpty = liveValue.trim().isEmpty;
    final hasError = error != null;

    if (isEditing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: hasError ? AppColors.warn : AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl(fieldKey, value),
              autofocus: true,
              keyboardType: keyboardType,
              style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                prefixIcon: Icon(icon,
                    color: hasError ? AppColors.warn : AppColors.primary,
                    size: 17),
                suffixIcon: IconButton(
                  icon: Icon(Icons.check_circle_rounded,
                      color: hasError ? AppColors.warn : AppColors.accent),
                  onPressed: onDone,
                ),
                hintText: _hintFor(fieldKey),
                hintStyle:
                    const TextStyle(color: AppColors.inkLight, fontSize: 13),
                filled: true,
                fillColor:
                    hasError ? AppColors.warnSoft : AppColors.primarySoft,
                border: OutlineInputBorder(
                    borderRadius: AppColors.r12, borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppColors.r12,
                  borderSide: BorderSide(
                      color: hasError ? AppColors.warn : AppColors.primary,
                      width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                errorText: error,
                errorStyle: const TextStyle(fontSize: 11),
              ),
              onSubmitted: (_) => onDone(),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.primarySoft.withOpacity(0.5),
        splashColor: AppColors.primary.withOpacity(0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: hasError
                    ? AppColors.warnSoft
                    : (isEmpty ? AppColors.warnSoft : AppColors.primarySoft),
                borderRadius: AppColors.r10,
              ),
              child: Icon(icon,
                  color: hasError
                      ? AppColors.warn
                      : (isEmpty ? AppColors.warn : AppColors.primary),
                  size: 17),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppColors.inkLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    liveValue.isEmpty ? 'Tap to add…' : liveValue,
                    style: TextStyle(
                      color: liveValue.isEmpty
                          ? AppColors.inkLight
                          : AppColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontStyle: liveValue.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                  if (hasError) ...[
                    const SizedBox(height: 3),
                    Text(error!,
                        style: const TextStyle(
                            color: AppColors.warn,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            Icon(
              isEmpty || hasError
                  ? Icons.error_outline_rounded
                  : Icons.edit_outlined,
              size: 15,
              color: hasError
                  ? AppColors.warn
                  : (isEmpty ? AppColors.warn : AppColors.inkLight),
            ),
          ]),
        ),
      ),
    );
  }
}

String _hintFor(String key) {
  switch (key) {
    case 'course_name':
      return 'e.g. Introduction to Computer Science';
    case 'course_code':
      return 'e.g. CS101';
    case 'semester':
      return 'e.g. Fall 2025';
    default:
      return '';
  }
}

// ─── TAB 2 — Sections ─────────────────────────────────────────────────────────
class _SectionsTab extends StatefulWidget {
  const _SectionsTab({
    required this.ws,
    required this.vm,
    required this.onError,
    required this.onNavigateToStudents,
  });
  final Workspace ws;
  final WorkspacesViewModel vm;
  final void Function(String) onError;
  final VoidCallback onNavigateToStudents;

  @override
  State<_SectionsTab> createState() => _SectionsTabState();
}

class _SectionsTabState extends State<_SectionsTab>
    with AutomaticKeepAliveClientMixin<_SectionsTab> {
  @override
  bool get wantKeepAlive => true;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static final List<String> _minLabels = [
    '00',
    '05',
    '10',
    '15',
    '20',
    '25',
    '30',
    '35',
    '40',
    '45',
    '50',
    '55',
  ];

  ({int hour, int minIdx, bool isPM}) _parseTime(String val) {
    if (val.isEmpty) return (hour: 8, minIdx: 0, isPM: false);
    final upper = val.toUpperCase();
    final isPM = upper.contains('PM');
    final clean = val.replaceAll(RegExp(r'[AaPp][Mm]'), '').trim();
    final parts = clean.split(':');
    int h = int.tryParse(parts[0].trim()) ?? 8;
    int m = int.tryParse(parts.length > 1 ? parts[1].trim() : '0') ?? 0;
    if (h == 0)
      h = 12;
    else if (h > 12) h -= 12;
    int minIdx = 0, minDist = 999;
    for (int j = 0; j < _minLabels.length; j++) {
      final d = (int.parse(_minLabels[j]) - m).abs();
      if (d < minDist) {
        minDist = d;
        minIdx = j;
      }
    }
    return (hour: h.clamp(1, 12), minIdx: minIdx, isPM: isPM);
  }

  String _formatTime(int hour12, int minIdx, bool isPM) =>
      '$hour12:${_minLabels[minIdx]} ${isPM ? "PM" : "AM"}';

  int? _timeToMins(String val) {
    if (val.isEmpty) return null;
    final upper = val.toUpperCase();
    final isPM = upper.contains('PM');
    final isAM = upper.contains('AM');
    final clean = val.replaceAll(RegExp(r'[AaPp][Mm]'), '').trim();
    final parts = clean.split(':');
    if (parts.length < 2) return null;
    int? h = int.tryParse(parts[0].trim());
    int? m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return null;
    if (isPM && h != 12) h += 12;
    if (isAM && h == 12) h = 0;
    return h * 60 + m;
  }

  void _showSectionSheet(BuildContext ctx, {Section? editing}) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _SectionSheetContent(
        editing: editing,
        vm: widget.vm,
        onSuccess: (msg) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(msg),
              backgroundColor: AppColors.accent,
              behavior: SnackBarBehavior.floating,
              shape: const RoundedRectangleBorder(borderRadius: AppColors.r12),
            ));
          }
        },
        onError: (e) {
          if (mounted) widget.onError(e);
        },
        parseTime: _parseTime,
        formatTime: _formatTime,
        timeToMins: _timeToMins,
        minLabels: _minLabels,
        days: _days,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ws = widget.ws;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(
          title: 'Sections (${ws.sections.length})',
          icon: Icons.groups_2_rounded,
          trailing: _PillButton(
              label: '+ Add Section', onTap: () => _showSectionSheet(context)),
        ),
        const SizedBox(height: 12),
        if (ws.sections.isEmpty)
          const _EmptyState(
            icon: Icons.groups_2_rounded,
            title: 'No sections yet',
            subtitle:
                'Tap \"+ Add Section\" to create your first class section.',
          )
        else
          ...ws.sections.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SectionCard(
                  section: s,
                  onDelete: () => _confirmDelete(s),
                  onEdit: () => _showSectionSheet(context, editing: s),
                  onViewStudents: widget.onNavigateToStudents,
                ),
              )),
      ],
    );
  }

  Future<void> _confirmDelete(Section s) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Text('Delete Section',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            content: Text(
                'Delete "${s.name.isNotEmpty ? s.name : "this section"}"?',
                style: const TextStyle(fontSize: 13, color: AppColors.inkMid)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.inkLight)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ) ??
        false;
    if (ok) {
      await widget.vm.deleteSection(s.id);
      if (widget.vm.error != null) widget.onError(widget.vm.error!);
    }
  }
}

// ─── Section sheet content ────────────────────────────────────────────────────
class _SectionSheetContent extends StatefulWidget {
  const _SectionSheetContent({
    required this.editing,
    required this.vm,
    required this.onSuccess,
    required this.onError,
    required this.parseTime,
    required this.formatTime,
    required this.timeToMins,
    required this.minLabels,
    required this.days,
  });
  final Section? editing;
  final WorkspacesViewModel vm;
  final void Function(String) onSuccess;
  final void Function(String) onError;
  final ({int hour, int minIdx, bool isPM}) Function(String) parseTime;
  final String Function(int, int, bool) formatTime;
  final int? Function(String) timeToMins;
  final List<String> minLabels;
  final List<String> days;

  @override
  State<_SectionSheetContent> createState() => _SectionSheetContentState();
}

class _SectionSheetContentState extends State<_SectionSheetContent> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _locationCtrl;
  late List<String> _selDays;
  late int _selReminderMins;
  late int _startH, _startMIdx;
  late bool _startPM;
  late int _endH, _endMIdx;
  late bool _endPM;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');
    _selDays = List.from(e?.schedule.days ?? []);
    _selReminderMins = e?.schedule.reminderMinutes ?? 10;
    final sp = widget.parseTime(e?.schedule.startTime ?? '');
    final ep = widget.parseTime(e?.schedule.endTime ?? '');
    _startH = sp.hour;
    _startMIdx = sp.minIdx;
    _startPM = sp.isPM;
    _endH = ep.hour;
    _endMIdx = ep.minIdx;
    _endPM = ep.isPM;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.inkLight,
                letterSpacing: 1.2)),
      );

  Widget _hourRow(int selHour, void Function(int) onSel) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(12, (idx) {
            final h = idx + 1;
            final sel = selHour == h;
            return GestureDetector(
              onTap: () => setState(() => onSel(h)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                margin: const EdgeInsets.only(right: 6),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary : AppColors.surfaceAlt,
                  borderRadius: AppColors.r10,
                  border: Border.all(
                      color: sel ? AppColors.primary : AppColors.border),
                ),
                alignment: Alignment.center,
                child: Text('$h',
                    style: TextStyle(
                        color: sel ? Colors.white : AppColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            );
          }),
        ),
      );

  Widget _minRow(int selMin, void Function(int) onSel) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(widget.minLabels.length, (idx) {
            final sel = selMin == idx;
            return GestureDetector(
              onTap: () => setState(() => onSel(idx)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                margin: const EdgeInsets.only(right: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary : AppColors.surfaceAlt,
                  borderRadius: AppColors.r10,
                  border: Border.all(
                      color: sel ? AppColors.primary : AppColors.border),
                ),
                child: Text(':${widget.minLabels[idx]}',
                    style: TextStyle(
                        color: sel ? Colors.white : AppColors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            );
          }),
        ),
      );

  Widget _ampmRow(bool isPM, void Function(bool) onSel) => Container(
        decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: AppColors.r10,
            border: Border.all(color: AppColors.border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final pm in [false, true])
              GestureDetector(
                onTap: () => setState(() => onSel(pm)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
                  decoration: BoxDecoration(
                    color: isPM == pm ? AppColors.primary : Colors.transparent,
                    borderRadius: AppColors.r10,
                  ),
                  child: Text(pm ? 'PM' : 'AM',
                      style: TextStyle(
                          color: isPM == pm ? Colors.white : AppColors.inkMid,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ),
              ),
          ],
        ),
      );

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Section name is required.');
      return;
    }
    if (_selDays.isEmpty) {
      setState(() => _error = 'Please select at least one day.');
      return;
    }
    final startStr = widget.formatTime(_startH, _startMIdx, _startPM);
    final endStr = widget.formatTime(_endH, _endMIdx, _endPM);
    final startMins = widget.timeToMins(startStr);
    final endMins = widget.timeToMins(endStr);
    if (startMins != null && endMins != null && endMins <= startMins) {
      setState(() =>
          _error = 'End time must be after start time ($startStr → $endStr).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = SectionDraft()
        ..name = name
        ..location = _locationCtrl.text.trim()
        ..days = _selDays
        ..startTime = startStr
        ..endTime = endStr
        ..reminderMinutes = _selReminderMins;
      if (widget.editing != null) {
        await widget.vm.updateSection(widget.editing!.id, draft);
      } else {
        await widget.vm.createSection(draft);
      }
      if (mounted) Navigator.pop(context);
      widget.onSuccess(
          widget.editing != null ? 'Section updated ✓' : 'Section created ✓');
    } catch (e) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.94,
      minChildSize: 0.6,
      maxChildSize: 0.97,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.editing != null ? 'Edit Section' : 'New Section',
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.ink),
          ),
          _label('SECTION NAME'),
          TextField(
            controller: _nameCtrl,
            onChanged: (_) => setState(() => _error = null),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'e.g. Section A',
              hintStyle:
                  const TextStyle(color: AppColors.inkLight, fontSize: 13),
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(
                  borderRadius: AppColors.r10,
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: AppColors.r10,
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: AppColors.r10,
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          _label('LOCATION / ROOM'),
          TextField(
            controller: _locationCtrl,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'e.g. Room 204',
              hintStyle:
                  const TextStyle(color: AppColors.inkLight, fontSize: 13),
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(
                  borderRadius: AppColors.r10,
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: AppColors.r10,
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: AppColors.r10,
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          _label('DAYS'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.days.map((d) {
              final sel = _selDays.contains(d);
              return GestureDetector(
                onTap: () => setState(() {
                  sel ? _selDays.remove(d) : _selDays.add(d);
                  _error = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary : AppColors.surfaceAlt,
                    borderRadius: AppColors.r10,
                    border: Border.all(
                        color: sel ? AppColors.primary : AppColors.border),
                  ),
                  child: Text(d,
                      style: TextStyle(
                          color: sel ? Colors.white : AppColors.inkMid,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              );
            }).toList(),
          ),
          _label('START — HOUR'),
          _hourRow(_startH, (h) => _startH = h),
          _label('START — MINUTES'),
          _minRow(_startMIdx, (m) => _startMIdx = m),
          _label('START — PERIOD'),
          _ampmRow(_startPM, (pm) => _startPM = pm),
          _label('END — HOUR'),
          _hourRow(_endH, (h) => _endH = h),
          _label('END — MINUTES'),
          _minRow(_endMIdx, (m) => _endMIdx = m),
          _label('END — PERIOD'),
          _ampmRow(_endPM, (pm) => _endPM = pm),
          _label('REMINDER BEFORE CLASS'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [5, 10, 15, 20, 30].map((mins) {
                final sel = _selReminderMins == mins;
                return GestureDetector(
                  onTap: () => setState(() => _selReminderMins = mins),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 110),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : AppColors.surfaceAlt,
                      borderRadius: AppColors.r10,
                      border: Border.all(
                          color: sel ? AppColors.primary : AppColors.border),
                    ),
                    child: Text('${mins}min',
                        style: TextStyle(
                            color: sel ? Colors.white : AppColors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: AppColors.r20,
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Text(
                '${_selDays.isEmpty ? "No days" : _selDays.join(", ")}  ·  '
                '${widget.formatTime(_startH, _startMIdx, _startPM)} → '
                '${widget.formatTime(_endH, _endMIdx, _endPM)}',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warnSoft,
                borderRadius: AppColors.r10,
                border: Border.all(color: AppColors.warn.withOpacity(0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 15, color: AppColors.warn),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(_error!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.warn,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape:
                    const RoundedRectangleBorder(borderRadius: AppColors.r12),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      widget.editing != null
                          ? 'Save Changes'
                          : 'Create Section',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section card ─────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.onDelete,
    required this.onEdit,
    required this.onViewStudents,
  });
  final Section section;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onViewStudents;

  static const _allDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final sch = section.schedule;
    final activeDays = sch.days.toSet();
    final rawEnd = sch.endTime.trim();
    final endDisplay = (rawEnd.isEmpty ||
            rawEnd == sch.timezone ||
            rawEnd.toUpperCase() == 'UTC')
        ? ''
        : rawEnd;
    final hasTime = sch.startTime.isNotEmpty;
    final timeString = hasTime
        ? (endDisplay.isNotEmpty
            ? '${sch.startTime} – $endDisplay'
            : sch.startTime)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppColors.r16,
        boxShadow: AppColors.shadow,
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFF9B78E0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: AppColors.r12,
                ),
                child: const Icon(Icons.groups_2_rounded,
                    color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.name.isEmpty ? 'Unnamed Section' : section.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          color: AppColors.ink,
                          letterSpacing: -0.3,
                          height: 1.2),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(children: [
                      _Badge(
                          label: 'Section',
                          color: AppColors.primary,
                          bgColor: AppColors.primarySoft),
                      if (section.location.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _Badge(
                            icon: Icons.location_on_rounded,
                            label: section.location,
                            color: AppColors.accent,
                            bgColor: AppColors.accentSoft),
                      ],
                    ]),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppColors.inkLight, size: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(children: const [
                      Icon(Icons.edit_rounded,
                          color: AppColors.primary, size: 17),
                      SizedBox(width: 10),
                      Text('Edit Section',
                          style: TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ]),
                  ),
                  const PopupMenuDivider(height: 1),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: const [
                      Icon(Icons.delete_outline_rounded,
                          color: AppColors.red, size: 17),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: AppColors.r12,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _allDays.map((d) {
                    final active = activeDays.contains(d);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 32,
                      height: 28,
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : AppColors.surface,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: active ? AppColors.primary : AppColors.border,
                          width: active ? 0 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(d.substring(0, 1),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: active ? Colors.white : AppColors.inkLight,
                              letterSpacing: 0.2)),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 36, color: AppColors.border),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.schedule_rounded,
                        size: 11,
                        color:
                            hasTime ? AppColors.primary : AppColors.inkLight),
                    const SizedBox(width: 4),
                    Text('TIME',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: hasTime
                                ? AppColors.primary
                                : AppColors.inkLight,
                            letterSpacing: 0.9)),
                  ]),
                  const SizedBox(height: 5),
                  Text(timeString ?? '—',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: hasTime ? AppColors.ink : AppColors.inkLight,
                          height: 1.2),
                      textAlign: TextAlign.right),
                ],
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─── Badge chip ────────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  const _Badge(
      {required this.label,
      required this.color,
      required this.bgColor,
      this.icon});
  final String label;
  final Color color;
  final Color bgColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bgColor, borderRadius: AppColors.r8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.2)),
          ),
        ]),
      );
}

// ─── TAB 3 — Students ─────────────────────────────────────────────────────────
class _StudentsTab extends StatelessWidget {
  const _StudentsTab(
      {required this.ws, required this.vm, required this.onError});
  final Workspace ws;
  final WorkspacesViewModel vm;
  final void Function(String) onError;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(
            title: 'Students by Section', icon: Icons.people_alt_rounded),
        const SizedBox(height: 6),
        const Text('Tap a section to view or import students.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMid)),
        const SizedBox(height: 14),
        if (ws.sections.isEmpty)
          const _EmptyState(
            icon: Icons.people_alt_rounded,
            title: 'No sections yet',
            subtitle:
                'Create sections first, then import students for each one.',
          )
        else
          ...ws.sections.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SectionRosterCard(
                    section: s, ws: ws, vm: vm, onError: onError),
              )),
      ],
    );
  }
}

class _SectionRosterCard extends StatefulWidget {
  const _SectionRosterCard(
      {required this.section,
      required this.ws,
      required this.vm,
      required this.onError});
  final Section section;
  final Workspace ws;
  final WorkspacesViewModel vm;
  final void Function(String) onError;

  @override
  State<_SectionRosterCard> createState() => _SectionRosterCardState();
}

class _SectionRosterCardState extends State<_SectionRosterCard> {
  bool _expanded = false;
  bool _importing = false;
  bool _clearing = false;
  bool _loadingRoster = false;
  List<Student> _students = [];
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRoster();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRoster() async {
    setState(() => _loadingRoster = true);
    try {
      final list = await widget.vm.api
          .listSectionStudents(widget.ws.id, widget.section.id);
      if (mounted)
        setState(() {
          _students = list;
          _loadingRoster = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loadingRoster = false);
      widget.onError(e.toString());
    }
  }

  Future<bool?> _confirmDeleteStudent(Student s) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Remove Student',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        content: Text(
          'Remove "${s.name.isNotEmpty ? s.name : s.email}" from this section?',
          style: const TextStyle(fontSize: 13, color: AppColors.inkMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.inkLight)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _deleteStudent(Student s) {
    setState(() => _students.removeWhere((st) => st.studentId == s.studentId));
    widget.vm.api
        .deleteStudent(widget.ws.id, widget.section.id, s.studentId)
        .then((_) {
      widget.vm.recordImport(widget.section.id, _students.length);
    }).catchError((e) {
      if (mounted) {
        setState(() => _students.add(s));
        widget.onError('Failed to remove student: $e');
      }
    });
  }

  // ─── Compact professional clear-all dialog ────────────────────────────────
  Future<void> _confirmClearAll() async {
    final count = _students.length;
    final sectionName =
        widget.section.name.isNotEmpty ? widget.section.name : 'this section';

    final confirmed = await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withOpacity(0.32),
          builder: (_) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 32),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clear all students from $sectionName?',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$count student${count == 1 ? "" : "s"} will be '
                    'permanently removed. This cannot be undone.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMid,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.inkMid,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: const RoundedRectangleBorder(
                              borderRadius: AppColors.r10),
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.red,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: const RoundedRectangleBorder(
                              borderRadius: AppColors.r10),
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Clear all',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;
    setState(() => _clearing = true);
    try {
      await widget.vm.api.clearSectionStudents(widget.ws.id, widget.section.id);
      if (!mounted) return;
      setState(() {
        _students = [];
        _clearing = false;
      });
      widget.vm.recordImport(widget.section.id, 0);
    } catch (e) {
      if (mounted) {
        setState(() => _clearing = false);
        widget.onError('Failed to clear students: $e');
      }
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) _loadRoster();
  }

  Future<void> _import(BuildContext ctx) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      widget.onError('File has no data.');
      return;
    }
    final newHash = sha256.convert(bytes).toString();
    final liveSection = widget.vm.current?.sections.firstWhere(
        (s) => s.id == widget.section.id,
        orElse: () => widget.section);
    final storedHash = liveSection?.lastImportHash ?? '';
    final isSameFile = storedHash.isNotEmpty && newHash == storedHash;
    final existingCount = _students.isNotEmpty
        ? _students.length
        : widget.vm.countForSection(widget.section.id);
    final hasExisting = existingCount > 0;

    if (hasExisting && ctx.mounted) {
      final confirmed = await showDialog<bool>(
            context: ctx,
            barrierColor: Colors.black.withOpacity(0.55),
            builder: (_) => _ReplaceRosterDialog(
                filename: f.name,
                existingCount: existingCount,
                isSameFile: isSameFile),
          ) ??
          false;
      if (!confirmed) return;
    }

    setState(() => _importing = true);
    try {
      final result = await widget.vm.api.importStudents(
        workspaceId: widget.ws.id,
        sectionId: widget.section.id,
        bytes: bytes,
        filename: f.name,
      );
      widget.vm.recordImport(widget.section.id, result.imported);
      await _loadRoster();
      widget.vm.api.getWorkspace(widget.ws.id).then((fresh) {
        widget.vm.current = fresh;
      }).catchError((_) {});
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(result.imported > 0
              ? '✓ ${result.imported} student${result.imported == 1 ? "" : "s"} imported successfully'
              : 'No students found — check your file has name/email columns'),
          backgroundColor:
              result.imported > 0 ? AppColors.accent : AppColors.warn,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: AppColors.r12),
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _importing = false);
      widget.onError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.vm.countForSection(widget.section.id);
    final hasStudents = count > 0;
    final sch = widget.section.schedule;
    final days = sch.days.isEmpty ? '' : sch.days.join(', ');
    final rawEnd = sch.endTime.trim();
    final endDisplay = (rawEnd.isEmpty ||
            rawEnd == sch.timezone ||
            rawEnd.toUpperCase() == 'UTC')
        ? ''
        : rawEnd;
    final time = sch.startTime.isNotEmpty
        ? (endDisplay.isNotEmpty
            ? '${sch.startTime} – $endDisplay'
            : sch.startTime)
        : '';
    final filtered = _search.isEmpty
        ? _students
        : _students
            .where((s) =>
                s.name.toLowerCase().contains(_search.toLowerCase()) ||
                s.email.toLowerCase().contains(_search.toLowerCase()) ||
                s.studentNo.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppColors.r16,
        boxShadow: AppColors.shadowSm,
        border: Border.all(
          color:
              _expanded ? AppColors.primary.withOpacity(0.4) : AppColors.border,
          width: _expanded ? 1.5 : 1,
        ),
      ),
      child: Column(children: [
        ClipRRect(
          borderRadius: _expanded
              ? const BorderRadius.vertical(top: Radius.circular(16))
              : AppColors.r16,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: hasStudents
                            ? AppColors.accentSoft
                            : AppColors.primarySoft,
                        borderRadius: AppColors.r10,
                        border: Border.all(
                          color: (hasStudents
                                  ? AppColors.accent
                                  : AppColors.primary)
                              .withOpacity(0.18),
                        ),
                      ),
                      child: Icon(Icons.groups_2_rounded,
                          color: hasStudents
                              ? AppColors.accent
                              : AppColors.primary,
                          size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.section.name.isEmpty
                                ? 'Unnamed Section'
                                : widget.section.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink,
                                letterSpacing: -0.2),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (days.isNotEmpty || time.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(children: [
                              if (days.isNotEmpty) ...[
                                const Icon(Icons.calendar_today_rounded,
                                    size: 10, color: AppColors.inkLight),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(days,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.inkMid,
                                          fontWeight: FontWeight.w500)),
                                ),
                              ],
                              if (days.isNotEmpty && time.isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 5),
                                  child: Text('·',
                                      style: TextStyle(
                                          color: AppColors.inkLight,
                                          fontSize: 11)),
                                ),
                              if (time.isNotEmpty) ...[
                                const Icon(Icons.schedule_rounded,
                                    size: 10, color: AppColors.inkLight),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(time,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.inkMid,
                                          fontWeight: FontWeight.w500)),
                                ),
                              ],
                            ]),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: hasStudents
                            ? AppColors.accentSoft
                            : AppColors.surfaceAlt,
                        borderRadius: AppColors.r20,
                        border: Border.all(
                          color: hasStudents
                              ? AppColors.accent.withOpacity(0.3)
                              : AppColors.border,
                        ),
                      ),
                      child: _importing
                          ? const SizedBox(
                              width: 36,
                              height: 11,
                              child: LinearProgressIndicator(
                                  color: AppColors.accent,
                                  backgroundColor: AppColors.accentSoft),
                            )
                          : Text(
                              '$count student${count == 1 ? "" : "s"}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: hasStudents
                                      ? AppColors.accent
                                      : AppColors.inkLight),
                            ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _expanded
                              ? AppColors.primarySoft
                              : AppColors.surfaceAlt,
                          borderRadius: AppColors.r8,
                        ),
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            color: _expanded
                                ? AppColors.primary
                                : AppColors.inkMid,
                            size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: _expanded
              ? Column(children: [
                  const Divider(height: 1, color: AppColors.border),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      // ── Import + Clear row ──────────────────────────
                      Row(children: [
                        Expanded(
                          child: Material(
                            color: _importing
                                ? AppColors.surfaceAlt
                                : AppColors.primarySoft,
                            borderRadius: AppColors.r10,
                            child: InkWell(
                              onTap: _importing ? null : () => _import(context),
                              borderRadius: AppColors.r10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  borderRadius: AppColors.r10,
                                  border: Border.all(
                                    color: _importing
                                        ? AppColors.border
                                        : AppColors.primary.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _importing
                                        ? const SizedBox(
                                            width: 13,
                                            height: 13,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.primary),
                                          )
                                        : const Icon(Icons.upload_file_rounded,
                                            size: 14, color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      _importing
                                          ? 'Importing…'
                                          : 'Import student list',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _importing
                                            ? AppColors.inkMid
                                            : AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_students.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Material(
                            color: Colors.transparent,
                            borderRadius: AppColors.r10,
                            child: InkWell(
                              onTap: _clearing ? null : _confirmClearAll,
                              borderRadius: AppColors.r10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  borderRadius: AppColors.r10,
                                  border: Border.all(
                                    color: _clearing
                                        ? AppColors.border
                                        : AppColors.red.withOpacity(0.4),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _clearing
                                        ? const SizedBox(
                                            width: 13,
                                            height: 13,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.red),
                                          )
                                        : const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 14,
                                            color: AppColors.red,
                                          ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _clearing ? 'Clearing…' : 'Clear all',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _clearing
                                            ? AppColors.red.withOpacity(0.4)
                                            : AppColors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ]),
                      // ── Student list ────────────────────────────────
                      if (_loadingRoster)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary, strokeWidth: 2)),
                        )
                      else if (_students.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Column(children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                  color: AppColors.surfaceAlt,
                                  borderRadius: AppColors.r12),
                              child: const Icon(Icons.people_outline_rounded,
                                  color: AppColors.inkLight, size: 24),
                            ),
                            const SizedBox(height: 10),
                            const Text('No students imported yet',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: AppColors.inkMid)),
                            const SizedBox(height: 4),
                            const Text(
                                'Upload a CSV/XLSX with name, email, student_no columns.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.inkLight,
                                    height: 1.4)),
                          ]),
                        )
                      else ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _search = v),
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.ink),
                          decoration: InputDecoration(
                            hintText: 'Search students…',
                            hintStyle: const TextStyle(
                                color: AppColors.inkLight, fontSize: 12),
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: AppColors.inkLight, size: 18),
                            suffixIcon: _search.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded,
                                        color: AppColors.inkLight, size: 16),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _search = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AppColors.surfaceAlt,
                            border: OutlineInputBorder(
                                borderRadius: AppColors.r12,
                                borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            return Dismissible(
                              key: ValueKey(s.studentId),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                color: AppColors.red.withOpacity(0.12),
                                child: const Icon(Icons.delete_outline_rounded,
                                    color: AppColors.red, size: 18),
                              ),
                              confirmDismiss: (_) => _confirmDeleteStudent(s),
                              onDismissed: (_) => _deleteStudent(s),
                              child: Container(
                                color: i.isEven
                                    ? Colors.transparent
                                    : AppColors.surfaceAlt.withOpacity(0.45),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 9),
                                child: Row(children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text('${i + 1}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.inkLight,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(s.name.isEmpty ? '—' : s.name,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.ink,
                                            fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(s.email.isEmpty ? '—' : s.email,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.inkMid),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                        s.studentNo.isEmpty ? '—' : s.studentNo,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.inkLight),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  GestureDetector(
                                    onTap: () async {
                                      final ok = await _confirmDeleteStudent(s);
                                      if (ok == true) _deleteStudent(s);
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.only(left: 6),
                                      child: Icon(Icons.delete_outline_rounded,
                                          size: 15, color: AppColors.red),
                                    ),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            _search.isNotEmpty
                                ? '${filtered.length} of ${_students.length} shown'
                                : '${_students.length} student${_students.length == 1 ? "" : "s"} total',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.inkLight),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ])
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }
}

// ─── TAB 4 — Ask AI ───────────────────────────────────────────────────────────
class _AskTab extends StatelessWidget {
  const _AskTab({
    required this.chat,
    required this.ctrl,
    required this.scrollCtrl,
    required this.asking,
    required this.onAsk,
  });
  final List<_ChatMsg> chat;
  final TextEditingController ctrl;
  final ScrollController scrollCtrl;
  final bool asking;
  final Future<void> Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: chat.isEmpty
            ? _AskEmptyState(onAsk: onAsk)
            : ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(14),
                itemCount: chat.length + (asking ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == chat.length) return const _TypingIndicator();
                  return _ChatBubble(msg: chat[i]);
                },
              ),
      ),
      Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(color: AppColors.ink, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ask about the syllabus…',
                hintStyle: const TextStyle(color: AppColors.inkLight),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                border: OutlineInputBorder(
                    borderRadius: AppColors.r20, borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              ),
              onSubmitted: onAsk,
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: asking ? null : () => onAsk(ctrl.text),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: asking ? AppColors.inkLight : AppColors.primary,
                borderRadius: AppColors.r20,
              ),
              child: asking
                  ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _AskEmptyState extends StatelessWidget {
  const _AskEmptyState({required this.onAsk});
  final Future<void> Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    final suggestions = [
      'What is the grading breakdown?',
      'What are the attendance rules?',
      'What textbooks are required?',
      'When is the midterm?',
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6747B0), Color(0xFF9B78E0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: AppColors.r20,
          ),
          child: Column(children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: AppColors.r16,
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 26),
            ),
            const SizedBox(height: 12),
            const Text('Ask Your Syllabus',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text('Get instant answers from your course syllabus.',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 12),
                textAlign: TextAlign.center),
          ]),
        ),
        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text('Try asking…',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkMid)),
        ),
        ...suggestions.map((q) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.surface,
                borderRadius: AppColors.r12,
                child: InkWell(
                  onTap: () => onAsk(q),
                  borderRadius: AppColors.r12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                        borderRadius: AppColors.r12,
                        border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: AppColors.r8),
                        child: const Icon(Icons.lightbulb_outline_rounded,
                            color: AppColors.primary, size: 15),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(q,
                              style: const TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500))),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 11, color: AppColors.inkLight),
                    ]),
                  ),
                ),
              ),
            )),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.msg});
  final _ChatMsg msg;

  @override
  Widget build(BuildContext context) => Align(
        alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.76),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: msg.isUser ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(msg.isUser ? 14 : 3),
              bottomRight: Radius.circular(msg.isUser ? 3 : 14),
            ),
            boxShadow: AppColors.shadowSm,
            border: msg.isUser ? null : Border.all(color: AppColors.border),
          ),
          child: Text(msg.text,
              style: TextStyle(
                  color: msg.isUser ? Colors.white : AppColors.ink,
                  fontSize: 13,
                  height: 1.5)),
        ),
      );
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomRight: Radius.circular(14),
              bottomLeft: Radius.circular(3),
            ),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.auto_awesome_rounded,
                size: 13, color: AppColors.primary),
            SizedBox(width: 5),
            Text('Thinking…',
                style: TextStyle(
                    color: AppColors.inkLight,
                    fontSize: 12,
                    fontStyle: FontStyle.italic)),
          ]),
        ),
      );
}

// ─── Shared widgets ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.title, required this.icon, this.trailing});
  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: AppColors.primary, size: 17),
        const SizedBox(width: 7),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
        const Spacer(),
        if (trailing != null) trailing!,
      ]);
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.primary,
        borderRadius: AppColors.r20,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppColors.r20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  color: AppColors.primarySoft, borderRadius: AppColors.r20),
              child: Icon(icon, color: AppColors.primary, size: 34),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.ink)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.inkLight, fontSize: 13, height: 1.5)),
          ]),
        ),
      );
}

class _ChatMsg {
  const _ChatMsg({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}

// ─── Replace Roster Dialog ────────────────────────────────────────────────────
class _ReplaceRosterDialog extends StatelessWidget {
  const _ReplaceRosterDialog({
    required this.filename,
    required this.existingCount,
    required this.isSameFile,
  });
  final String filename;
  final int existingCount;
  final bool isSameFile;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 40,
                offset: const Offset(0, 16)),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: isSameFile
                  ? const Color(0xFFFFF8ED)
                  : const Color(0xFFFFF0F0),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSameFile
                      ? const Color(0xFFFFEDC2)
                      : const Color(0xFFFFDDDD),
                  border: Border.all(
                    color: isSameFile
                        ? const Color(0xFFFFD080)
                        : const Color(0xFFFFAAAA),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  isSameFile
                      ? Icons.file_copy_rounded
                      : Icons.swap_horiz_rounded,
                  color: isSameFile
                      ? const Color(0xFFE6920A)
                      : const Color(0xFFD93025),
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isSameFile ? 'Same File Detected' : 'Replace Student List?',
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: -0.3),
              ),
              const SizedBox(height: 4),
              Text(
                isSameFile
                    ? 'This file was already imported'
                    : 'A different roster will replace the current one',
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF888888),
                    fontWeight: FontWeight.w500),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F5FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0D9FF)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.insert_drive_file_rounded,
                        color: Color(0xFF7C5CBF), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(filename,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2D2640)),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Text(
                  isSameFile
                      ? 'This appears to be the same file you imported before. Re-importing will refresh the list with $existingCount student${existingCount == 1 ? "" : "s"}.'
                      : 'This section currently has $existingCount student${existingCount == 1 ? "" : "s"}. Uploading a new file will permanently replace the existing roster. This cannot be undone.',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF6B6480), height: 1.55),
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
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel',
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
                    backgroundColor: isSameFile
                        ? const Color(0xFFE6920A)
                        : const Color(0xFFD93025),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Icon(
                    isSameFile
                        ? Icons.refresh_rounded
                        : Icons.swap_horiz_rounded,
                    size: 16,
                  ),
                  label: Text(
                    isSameFile ? 'Re-import Anyway' : 'Yes, Replace',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
