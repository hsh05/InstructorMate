// lib/ui/workspace_detail.dart
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../app/api_client.dart';
import '../app/state/workspaces_vm.dart';
import '../app/workspace_models.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
class _DS {
  static const bg = Color(0xFFF8F6FF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF3F0FF);
  static const primary = Color(0xFF7C5CBF);
  static const primarySoft = Color(0xFFEDE8FF);
  static const accent = Color(0xFF00B896);
  static const accentSoft = Color(0xFFE0FAF5);
  static const warn = Color(0xFFE8900A);
  static const warnSoft = Color(0xFFFFF4E0);
  static const ink = Color(0xFF2D2640);
  static const inkMid = Color(0xFF6B6480);
  static const inkLight = Color(0xFFABA6C0);
  static const border = Color(0xFFE8E3F8);
  static const red = Color(0xFFD93025);

  static const r8 = BorderRadius.all(Radius.circular(8));
  static const r10 = BorderRadius.all(Radius.circular(10));
  static const r12 = BorderRadius.all(Radius.circular(12));
  static const r16 = BorderRadius.all(Radius.circular(16));
  static const r20 = BorderRadius.all(Radius.circular(20));

  static final shadow = [
    BoxShadow(
      color: const Color(0xFF7C5CBF).withOpacity(0.07),
      blurRadius: 14,
      offset: const Offset(0, 4),
    ),
  ];
  static final shadowSm = [
    BoxShadow(
      color: const Color(0xFF7C5CBF).withOpacity(0.04),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];
}

const _fieldLabels = {
  'course_name': 'Course Name',
  'course_code': 'Course Code',
  'semester': 'Semester',
  'office_hours': 'Office Hours',
  'instructor_email': 'Instructor Email',
};
const _fieldIcons = {
  'course_name': Icons.book_rounded,
  'course_code': Icons.tag_rounded,
  'semester': Icons.calendar_today_rounded,
  'office_hours': Icons.access_time_rounded,
  'instructor_email': Icons.email_outlined,
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
    'office_hours',
    'instructor_email',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _askCtrl.dispose();
    _askScroll.dispose();
    for (final c in _fieldCtrl.values) c.dispose();
    super.dispose();
  }

  TextEditingController _ctrl(String key, String value) =>
      _fieldCtrl.putIfAbsent(key, () => TextEditingController(text: value));

  bool _isReady(Workspace ws) => [
    'course_name',
    'semester',
    'office_hours',
  ].every((k) => (ws.fields[k] ?? '').trim().isNotEmpty);

  List<String> _missingFields(Workspace ws) =>
      _editableKeys.where((k) => (ws.fields[k] ?? '').trim().isEmpty).toList();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (_, __) {
        final ws = widget.vm.current;
        if (ws == null)
          return const Scaffold(
            backgroundColor: _DS.bg,
            body: Center(child: Text('No workspace selected.')),
          );
        final ready = _isReady(ws);
        final missing = _missingFields(ws);

        return Scaffold(
          backgroundColor: _DS.bg,
          body: NestedScrollView(
            headerSliverBuilder: (_, __) => [_buildHeader(ws, ready)],
            body: Column(
              children: [
                // ── Pill tab bar ────────────────────────────────────────
                Container(
                  color: _DS.surface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _DS.surfaceAlt,
                      borderRadius: _DS.r20,
                    ),
                    padding: const EdgeInsets.all(3),
                    child: TabBar(
                      controller: _tabs,
                      indicator: BoxDecoration(
                        color: _DS.primary,
                        borderRadius: _DS.r16,
                        boxShadow: [
                          BoxShadow(
                            color: _DS.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: _DS.inkMid,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.info_outline_rounded, size: 16),
                          text: 'Info',
                        ),
                        Tab(
                          icon: Icon(Icons.groups_2_rounded, size: 16),
                          text: 'Sections',
                        ),
                        Tab(
                          icon: Icon(Icons.people_alt_rounded, size: 16),
                          text: 'Students',
                        ),
                        Tab(
                          icon: Icon(Icons.auto_awesome_rounded, size: 16),
                          text: 'Ask AI',
                        ),
                      ],
                    ),
                  ),
                ),
                if (!ready && missing.isNotEmpty)
                  _MissingBanner(fields: missing),
                Expanded(
                  child: widget.vm.loading
                      ? const Center(
                          child: CircularProgressIndicator(color: _DS.primary),
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
                              onReupload: () async {
                                await widget.vm.reuploadSyllabus();
                                if (widget.vm.error != null)
                                  _showError(widget.vm.error!);
                              },
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
  }

  // ── Header: title + stat pills ────────────────────────────────────────────
  Widget _buildHeader(Workspace ws, bool ready) {
    final totalStudents = widget.vm.totalStudentsCount;
    final sectionCount = ws.sections.length;
    final code = ws.fields['course_code'] ?? '';
    final semester = ws.fields['semester'] ?? '';

    return SliverAppBar(
      expandedHeight: 165,
      pinned: true,
      backgroundColor: const Color(0xFF5A3DA0),
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5A3DA0), Color(0xFF9B78E0)],
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
                        child: Text(
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
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (ready ? _DS.accent : _DS.warn).withOpacity(
                            0.2,
                          ),
                          borderRadius: _DS.r20,
                          border: Border.all(
                            color: ready ? _DS.accent : _DS.warn,
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
                              color: ready ? _DS.accent : _DS.warn,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ready ? 'Ready' : 'Draft',
                              style: TextStyle(
                                color: ready ? _DS.accent : _DS.warn,
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
                  // Stat pills
                  Row(
                    children: [
                      if (code.isNotEmpty) ...[
                        _StatPill(icon: Icons.tag_rounded, label: code),
                        const SizedBox(width: 8),
                      ],
                      if (semester.isNotEmpty) ...[
                        _StatPill(
                          icon: Icons.calendar_today_rounded,
                          label: semester,
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Spacer(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Changes saved ✓'),
          backgroundColor: _DS.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: _DS.r12),
        ),
      );
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
      _chat.add(
        _ChatMsg(
          text: (widget.vm.error != null && widget.vm.error!.contains('chunks'))
              ? '⚠️ Syllabus not processed yet. Tap "Re-upload PDF" above.'
              : (answer ?? "Sorry, I couldn't get an answer."),
          isUser: false,
        ),
      );
      _asking = false;
    });
    _scrollChat();
  }

  void _scrollChat() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_askScroll.hasClients)
      _askScroll.animateTo(
        _askScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
  });

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: _DS.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: _DS.r12),
    ),
  );
}

// ── Stat pill ─────────────────────────────────────────────────────────────────
class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.label,
    this.highlight = false,
  });
  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: highlight
          ? _DS.accent.withOpacity(0.2)
          : Colors.white.withOpacity(0.15),
      borderRadius: _DS.r20,
      border: Border.all(
        color: highlight
            ? _DS.accent.withOpacity(0.5)
            : Colors.white.withOpacity(0.25),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: highlight ? _DS.accent : Colors.white, size: 11),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: highlight ? _DS.accent : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
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
      color: _DS.warnSoft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _DS.warn, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Complete: $labels',
              style: const TextStyle(
                color: _DS.warn,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── TAB 1 — Info (tap-to-edit, no form mode) ────────────────────────────────
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

class _InfoTabState extends State<_InfoTab> {
  final Set<String> _editing = {};
  bool _saving = false;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _editing.clear();
    });
    await widget.onSave();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasEdits = _editing.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(
          title: 'Course Details',
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _DS.surface,
            borderRadius: _DS.r16,
            boxShadow: _DS.shadow,
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              ...widget.editableKeys.asMap().entries.map((entry) {
                final idx = entry.key;
                final key = entry.value;
                final value = widget.ws.fields[key] ?? '';
                final label = _fieldLabels[key] ?? key;
                final icon = _fieldIcons[key] ?? Icons.edit_rounded;
                final isEditing = _editing.contains(key);
                final isEmpty = value.trim().isEmpty;
                final isLast = idx == widget.editableKeys.length - 1;

                return Column(
                  children: [
                    isEditing
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: const TextStyle(
                                    color: _DS.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: widget.ctrl(key, value),
                                  autofocus: true,
                                  style: const TextStyle(
                                    color: _DS.ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    prefixIcon: Icon(
                                      icon,
                                      color: _DS.primary,
                                      size: 17,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: const Icon(
                                        Icons.check_circle_rounded,
                                        color: _DS.accent,
                                        size: 22,
                                      ),
                                      onPressed: () =>
                                          setState(() => _editing.remove(key)),
                                    ),
                                    filled: true,
                                    fillColor: _DS.primarySoft,
                                    border: OutlineInputBorder(
                                      borderRadius: _DS.r12,
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: _DS.r12,
                                      borderSide: const BorderSide(
                                        color: _DS.primary,
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 13,
                                    ),
                                  ),
                                  onSubmitted: (_) =>
                                      setState(() => _editing.remove(key)),
                                ),
                              ],
                            ),
                          )
                        : Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => setState(() => _editing.add(key)),
                              hoverColor: _DS.primarySoft.withOpacity(0.5),
                              splashColor: _DS.primary.withOpacity(0.06),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 15,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isEmpty
                                            ? _DS.warnSoft
                                            : _DS.primarySoft,
                                        borderRadius: _DS.r10,
                                      ),
                                      child: Icon(
                                        icon,
                                        color: isEmpty ? _DS.warn : _DS.primary,
                                        size: 17,
                                      ),
                                    ),
                                    const SizedBox(width: 13),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            label,
                                            style: const TextStyle(
                                              color: _DS.inkLight,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            value.isEmpty
                                                ? 'Tap to add…'
                                                : value,
                                            style: TextStyle(
                                              color: value.isEmpty
                                                  ? _DS.inkLight
                                                  : _DS.ink,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              fontStyle: value.isEmpty
                                                  ? FontStyle.italic
                                                  : FontStyle.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 15,
                                      color: isEmpty ? _DS.warn : _DS.inkLight,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                    if (!isLast)
                      const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: _DS.border,
                      ),
                  ],
                );
              }),
              // Save button slides in when editing
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: (hasEdits || _saving)
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _DS.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: const RoundedRectangleBorder(
                                borderRadius: _DS.r12,
                              ),
                            ),
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded, size: 17),
                            label: Text(
                              _saving ? 'Saving…' : 'Save Changes',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── TAB 2 — Sections ────────────────────────────────────────────────────────
class _SectionsTab extends StatefulWidget {
  const _SectionsTab({
    required this.ws,
    required this.vm,
    required this.onError,
  });
  final Workspace ws;
  final WorkspacesViewModel vm;
  final void Function(String) onError;

  @override
  State<_SectionsTab> createState() => _SectionsTabState();
}

class _SectionsTabState extends State<_SectionsTab> {
  bool _showForm = false;
  Section? _editingSection;
  final _draft = SectionDraft();
  final _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _instructorCtrl = TextEditingController();
  final _startCtrl = TextEditingController(text: '09:00');
  final _endCtrl = TextEditingController(text: '10:15');
  bool _saving = false;

  void _startEdit(Section s) {
    _editingSection = s;
    _nameCtrl.text = s.name;
    _locationCtrl.text = s.location;
    _instructorCtrl.text = s.instructorName;
    _startCtrl.text = s.schedule.startTime;
    _endCtrl.text = s.schedule.endTime;
    _draft.days = List<String>.from(s.schedule.days);
    _draft.timezone = s.schedule.timezone;
    _draft.reminderMinutes = s.schedule.reminderMinutes;
    setState(() => _showForm = true);
  }

  void _cancelForm() {
    _editingSection = null;
    _nameCtrl.text = '';
    _locationCtrl.text = '';
    _instructorCtrl.text = '';
    _startCtrl.text = '09:00';
    _endCtrl.text = '10:15';
    _draft.days = const [];
    setState(() => _showForm = false);
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _locationCtrl,
      _instructorCtrl,
      _startCtrl,
      _endCtrl,
    ])
      c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ws = widget.ws;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(
          title: 'Sections (${ws.sections.length})',
          icon: Icons.groups_2_rounded,
          trailing: !_showForm
              ? _PillButton(
                  label: '+ Add Section',
                  onTap: () => setState(() => _showForm = true),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (_showForm) ...[_buildForm(), const SizedBox(height: 14)],
        if (ws.sections.isEmpty && !_showForm)
          _EmptyState(
            icon: Icons.groups_2_rounded,
            title: 'No sections yet',
            subtitle: 'Tap "+ Add Section" to create your first class section.',
          )
        else
          ...ws.sections.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SectionCard(
                section: s,
                onDelete: () => _confirmDelete(s),
                onEdit: () => _startEdit(s),
                vm: widget.vm,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(Section s) async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: const Text(
              'Delete Section',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            content: Text(
              'Delete "${s.name.isNotEmpty ? s.name : 'this section'}"?',
              style: const TextStyle(fontSize: 13, color: _DS.inkMid),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: _DS.inkLight),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _DS.red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
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

  Widget _buildForm() {
    return Container(
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: _DS.r16,
        boxShadow: _DS.shadow,
        border: Border.all(color: _DS.primary.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _editingSection != null
                    ? Icons.edit_rounded
                    : Icons.add_circle_rounded,
                color: _DS.primary,
                size: 16,
              ),
              const SizedBox(width: 7),
              Text(
                _editingSection != null ? 'Edit Section' : 'New Section',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: _DS.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _FormField(
            ctrl: _nameCtrl,
            label: 'Section Name',
            icon: Icons.label_rounded,
          ),
          const SizedBox(height: 10),
          _FormField(
            ctrl: _instructorCtrl,
            label: 'Instructor',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 10),
          _FormField(
            ctrl: _locationCtrl,
            label: 'Location / Room',
            icon: Icons.location_on_rounded,
          ),
          const SizedBox(height: 12),
          const Text(
            'Schedule',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _DS.inkMid,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _FormField(
                  ctrl: _startCtrl,
                  label: 'Start',
                  icon: Icons.schedule_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FormField(
                  ctrl: _endCtrl,
                  label: 'End',
                  icon: Icons.schedule_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: _days.map((d) {
              final sel = _draft.days.contains(d);
              return GestureDetector(
                onTap: () => setState(() {
                  sel
                      ? _draft.days = _draft.days.where((x) => x != d).toList()
                      : _draft.days = [..._draft.days, d];
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: sel ? _DS.primary : _DS.surfaceAlt,
                    borderRadius: _DS.r8,
                    border: Border.all(color: sel ? _DS.primary : _DS.border),
                  ),
                  child: Text(
                    d,
                    style: TextStyle(
                      color: sel ? Colors.white : _DS.inkMid,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _DS.inkMid,
                    side: const BorderSide(color: _DS.border),
                    shape: const RoundedRectangleBorder(borderRadius: _DS.r12),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _cancelForm,
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _DS.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(borderRadius: _DS.r12),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: _saving ? null : _saveSection,
                  child: _saving
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _editingSection != null ? 'Save Changes' : 'Create',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveSection() async {
    _draft
      ..name = _nameCtrl.text.trim()
      ..location = _locationCtrl.text.trim()
      ..instructorName = _instructorCtrl.text.trim()
      ..startTime = _startCtrl.text.trim()
      ..endTime = _endCtrl.text.trim();
    if (_draft.name.isEmpty) {
      widget.onError('Section name is required.');
      return;
    }
    if (_draft.days.isEmpty) {
      widget.onError('Select at least one day.');
      return;
    }

    setState(() => _saving = true);
    final isEditing = _editingSection != null;
    try {
      Workspace updated;
      if (isEditing) {
        await widget.vm.api.deleteSection(widget.ws.id, _editingSection!.id);
        updated = await widget.vm.api.createSection(widget.ws.id, _draft);
      } else {
        updated = await widget.vm.api.createSection(widget.ws.id, _draft);
      }
      widget.vm.current = updated;
      widget.vm.notifyListeners();
      await widget.vm.rescheduleNotificationsForCurrent();
      _cancelForm();
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing ? 'Section updated ✓' : 'Section created ✓',
            ),
            backgroundColor: _DS.accent,
            behavior: SnackBarBehavior.floating,
            shape: const RoundedRectangleBorder(borderRadius: _DS.r12),
          ),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      widget.onError(e.toString());
    }
  }
}

// ─── Section card ─────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.onDelete,
    required this.onEdit,
    required this.vm,
  });
  final Section section;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final WorkspacesViewModel vm;

  @override
  Widget build(BuildContext context) {
    final sch = section.schedule;
    final days = sch.days.isEmpty ? '—' : sch.days.join(', ');
    final time = (sch.startTime.isNotEmpty && sch.endTime.isNotEmpty)
        ? '${sch.startTime} – ${sch.endTime}'
        : '—';
    final count = vm.countForSection(section.id);

    return Material(
      color: _DS.surface,
      borderRadius: _DS.r16,
      child: InkWell(
        borderRadius: _DS.r16,
        hoverColor: _DS.primarySoft.withOpacity(0.5),
        splashColor: _DS.primary.withOpacity(0.08),
        highlightColor: Colors.transparent,
        onTap: onEdit,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: _DS.r16,
            boxShadow: _DS.shadowSm,
            border: Border.all(color: _DS.border),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: _DS.primarySoft,
                  borderRadius: _DS.r12,
                ),
                child: const Icon(
                  Icons.groups_2_rounded,
                  color: _DS.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.name.isEmpty ? 'Unnamed Section' : section.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _DS.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 11,
                          color: _DS.inkLight,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          days,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _DS.inkMid,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.schedule_rounded,
                          size: 11,
                          color: _DS.inkLight,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          time,
                          style: const TextStyle(
                            fontSize: 11,
                            color: _DS.inkMid,
                          ),
                        ),
                      ],
                    ),
                    if (section.location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 11,
                            color: _DS.inkLight,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            section.location,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _DS.inkMid,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.people_alt_rounded,
                          size: 11,
                          color: _DS.inkLight,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$count student${count == 1 ? "" : "s"}',
                          style: TextStyle(
                            fontSize: 11,
                            color: count > 0 ? _DS.accent : _DS.inkMid,
                            fontWeight: count > 0
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit section',
                icon: const Icon(
                  Icons.edit_outlined,
                  color: _DS.primary,
                  size: 20,
                ),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'Delete section',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: _DS.red,
                  size: 20,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── TAB 3 — Students: expandable roster per section ─────────────────────────
class _StudentsTab extends StatelessWidget {
  const _StudentsTab({
    required this.ws,
    required this.vm,
    required this.onError,
  });
  final Workspace ws;
  final WorkspacesViewModel vm;
  final void Function(String) onError;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(
          title: 'Students by Section',
          icon: Icons.people_alt_rounded,
        ),
        const SizedBox(height: 6),
        const Text(
          'Tap a section to view or import students.',
          style: TextStyle(fontSize: 12, color: _DS.inkMid),
        ),
        const SizedBox(height: 14),
        if (ws.sections.isEmpty)
          _EmptyState(
            icon: Icons.people_alt_rounded,
            title: 'No sections yet',
            subtitle:
                'Create sections first, then import students for each one.',
          )
        else
          ...ws.sections.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SectionRosterCard(
                section: s,
                ws: ws,
                vm: vm,
                onError: onError,
              ),
            ),
          ),
      ],
    );
  }
}

// Expandable card — import + live searchable roster
class _SectionRosterCard extends StatefulWidget {
  const _SectionRosterCard({
    required this.section,
    required this.ws,
    required this.vm,
    required this.onError,
  });
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
  bool _loadingRoster = false;
  List<Student> _students = [];
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRoster() async {
    setState(() => _loadingRoster = true);
    try {
      final list = await widget.vm.api.listSectionStudents(
        widget.ws.id,
        widget.section.id,
      );
      if (mounted)
        setState(() {
          _students = list;
          _loadingRoster = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingRoster = false);
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _students.isEmpty) _loadRoster();
  }

  Future<void> _import(BuildContext ctx) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      widget.onError('File has no data.');
      return;
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
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              result.imported > 0
                  ? 'Saved ✓ — ${result.imported} student${result.imported == 1 ? "" : "s"} imported'
                  : 'No students found — check your CSV has name/email columns',
            ),
            backgroundColor: result.imported > 0 ? _DS.accent : _DS.warn,
            behavior: SnackBarBehavior.floating,
            shape: const RoundedRectangleBorder(borderRadius: _DS.r12),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _importing = false);
      widget.onError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.vm.countForSection(widget.section.id);
    final sch = widget.section.schedule;
    final timeStr = '${sch.days.join(", ")} · ${sch.startTime}';

    final filtered = _search.isEmpty
        ? _students
        : _students
              .where(
                (s) =>
                    s.name.toLowerCase().contains(_search.toLowerCase()) ||
                    s.email.toLowerCase().contains(_search.toLowerCase()) ||
                    s.studentNo.toLowerCase().contains(_search.toLowerCase()),
              )
              .toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: _DS.r16,
        boxShadow: _DS.shadowSm,
        border: Border.all(
          color: _expanded ? _DS.primary.withOpacity(0.4) : _DS.border,
          width: _expanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // ── Header: always visible, tap to expand ──────────────────
          Material(
            color: Colors.transparent,
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : _DS.r16,
            child: InkWell(
              onTap: _toggle,
              borderRadius: _expanded
                  ? const BorderRadius.vertical(top: Radius.circular(16))
                  : _DS.r16,
              hoverColor: _DS.primarySoft.withOpacity(0.4),
              splashColor: _DS.primary.withOpacity(0.07),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: count > 0 ? _DS.accentSoft : _DS.primarySoft,
                        borderRadius: _DS.r12,
                      ),
                      child: Icon(
                        Icons.groups_2_rounded,
                        color: count > 0 ? _DS.accent : _DS.primary,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.section.name.isEmpty
                                ? 'Unnamed Section'
                                : widget.section.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _DS.ink,
                            ),
                          ),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _DS.inkMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Count badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: count > 0 ? _DS.accentSoft : _DS.surfaceAlt,
                        borderRadius: _DS.r20,
                      ),
                      child: _importing
                          ? const SizedBox(
                              width: 36,
                              height: 12,
                              child: LinearProgressIndicator(
                                color: _DS.accent,
                                backgroundColor: _DS.accentSoft,
                              ),
                            )
                          : Text(
                              '$count student${count == 1 ? "" : "s"}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: count > 0 ? _DS.accent : _DS.inkLight,
                              ),
                            ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _DS.inkLight,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Expandable body ───────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: _expanded
                ? Column(
                    children: [
                      const Divider(height: 1, color: _DS.border),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            // Import button
                            Material(
                              color: _importing
                                  ? _DS.surfaceAlt
                                  : _DS.primarySoft,
                              borderRadius: _DS.r12,
                              child: InkWell(
                                onTap: _importing
                                    ? null
                                    : () => _import(context),
                                borderRadius: _DS.r12,
                                hoverColor: _DS.primary.withOpacity(0.12),
                                splashColor: _DS.primary.withOpacity(0.18),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: _DS.r12,
                                    border: Border.all(
                                      color: _importing
                                          ? _DS.border
                                          : _DS.primary.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.upload_file_rounded,
                                        color: _importing
                                            ? _DS.inkLight
                                            : _DS.primary,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _importing
                                              ? 'Importing…'
                                              : 'Import student list (.csv)',
                                          style: TextStyle(
                                            color: _importing
                                                ? _DS.inkLight
                                                : _DS.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (_importing)
                                        const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _DS.primary,
                                          ),
                                        )
                                      else
                                        const Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          color: _DS.primary,
                                          size: 12,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // ── Student roster ──────────────────────────
                            if (_loadingRoster)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: _DS.primary,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else if (_students.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: const BoxDecoration(
                                        color: _DS.surfaceAlt,
                                        borderRadius: _DS.r12,
                                      ),
                                      child: const Icon(
                                        Icons.people_outline_rounded,
                                        color: _DS.inkLight,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'No students imported yet',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: _DS.inkMid,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Upload a CSV with name, email, student_no columns.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _DS.inkLight,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              const SizedBox(height: 10),
                              // Search bar
                              TextField(
                                controller: _searchCtrl,
                                onChanged: (v) => setState(() => _search = v),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _DS.ink,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search students…',
                                  hintStyle: const TextStyle(
                                    color: _DS.inkLight,
                                    fontSize: 12,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    color: _DS.inkLight,
                                    size: 18,
                                  ),
                                  suffixIcon: _search.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.clear_rounded,
                                            color: _DS.inkLight,
                                            size: 16,
                                          ),
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            setState(() => _search = '');
                                          },
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: _DS.surfaceAlt,
                                  border: OutlineInputBorder(
                                    borderRadius: _DS.r12,
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Table header
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 6,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: _DS.border),
                                  ),
                                ),
                                child: Row(
                                  children: const [
                                    SizedBox(
                                      width: 28,
                                      child: Text(
                                        '#',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _DS.inkLight,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'Name',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _DS.inkLight,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'Email',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _DS.inkLight,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 56,
                                      child: Text(
                                        'Student ID',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _DS.inkLight,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Rows
                              ...filtered.asMap().entries.map((e) {
                                final i = e.key;
                                final s = e.value;
                                return Container(
                                  color: i.isEven
                                      ? Colors.transparent
                                      : _DS.surfaceAlt.withOpacity(0.45),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 28,
                                        child: Text(
                                          '${i + 1}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: _DS.inkLight,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          s.name.isEmpty ? '—' : s.name,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: _DS.ink,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          s.email.isEmpty ? '—' : s.email,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: _DS.inkMid,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 56,
                                        child: Text(
                                          s.studentNo.isEmpty
                                              ? '—'
                                              : s.studentNo,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: _DS.inkLight,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              if (filtered.isEmpty && _search.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  child: Text(
                                    'No students match "$_search"',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _DS.inkLight,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 6),
                              // Footer
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _search.isNotEmpty
                                      ? '${filtered.length} of ${_students.length} shown'
                                      : '${_students.length} student${_students.length == 1 ? "" : "s"} total',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _DS.inkLight,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─── TAB 4 — Ask AI ──────────────────────────────────────────────────────────
class _AskTab extends StatelessWidget {
  const _AskTab({
    required this.chat,
    required this.ctrl,
    required this.scrollCtrl,
    required this.asking,
    required this.onAsk,
    required this.onReupload,
  });
  final List<_ChatMsg> chat;
  final TextEditingController ctrl;
  final ScrollController scrollCtrl;
  final bool asking;
  final Future<void> Function(String) onAsk;
  final VoidCallback onReupload;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: _DS.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              const Icon(
                Icons.picture_as_pdf_rounded,
                color: _DS.primary,
                size: 15,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "If AI isn't answering, re-upload the PDF.",
                  style: TextStyle(fontSize: 11, color: _DS.inkMid),
                ),
              ),
              Material(
                color: _DS.primary,
                borderRadius: _DS.r8,
                child: InkWell(
                  onTap: onReupload,
                  borderRadius: _DS.r8,
                  hoverColor: Colors.white.withOpacity(0.15),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Text(
                      'Re-upload',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
          decoration: BoxDecoration(
            color: _DS.surface,
            border: Border(top: BorderSide(color: _DS.border)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  style: const TextStyle(color: _DS.ink, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Ask about the syllabus…',
                    hintStyle: const TextStyle(color: _DS.inkLight),
                    filled: true,
                    fillColor: _DS.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: _DS.r20,
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
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
                    color: asking ? _DS.inkLight : _DS.primary,
                    borderRadius: _DS.r20,
                  ),
                  child: asking
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AskEmptyState extends StatelessWidget {
  const _AskEmptyState({required this.onAsk});
  final Future<void> Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    final suggestions = [
      'What is the grading policy?',
      'When are office hours?',
      'What are the attendance rules?',
      'What textbooks are required?',
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
            borderRadius: _DS.r20,
          ),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: _DS.r16,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ask Your Syllabus',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Get instant answers from your course syllabus.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'Try asking…',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _DS.inkMid,
            ),
          ),
        ),
        ...suggestions.map(
          (q) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: _DS.surface,
              borderRadius: _DS.r12,
              child: InkWell(
                onTap: () => onAsk(q),
                borderRadius: _DS.r12,
                hoverColor: _DS.primarySoft,
                splashColor: _DS.primary.withOpacity(0.1),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: _DS.r12,
                    border: Border.all(color: _DS.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: _DS.primarySoft,
                          borderRadius: _DS.r8,
                        ),
                        child: const Icon(
                          Icons.lightbulb_outline_rounded,
                          color: _DS.primary,
                          size: 15,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          q,
                          style: const TextStyle(
                            color: _DS.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 11,
                        color: _DS.inkLight,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
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
        maxWidth: MediaQuery.of(context).size.width * 0.76,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: msg.isUser ? _DS.primary : _DS.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(msg.isUser ? 14 : 3),
          bottomRight: Radius.circular(msg.isUser ? 3 : 14),
        ),
        boxShadow: _DS.shadowSm,
        border: msg.isUser ? null : Border.all(color: _DS.border),
      ),
      child: Text(
        msg.text,
        style: TextStyle(
          color: msg.isUser ? Colors.white : _DS.ink,
          fontSize: 13,
          height: 1.5,
        ),
      ),
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
        color: _DS.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomRight: Radius.circular(14),
          bottomLeft: Radius.circular(3),
        ),
        border: Border.all(color: _DS.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 13, color: _DS.primary),
          const SizedBox(width: 5),
          const Text(
            'Thinking…',
            style: TextStyle(
              color: _DS.inkLight,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Shared widgets ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: _DS.primary, size: 17),
      const SizedBox(width: 7),
      Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: _DS.ink,
        ),
      ),
      const Spacer(),
      if (trailing != null) trailing!,
    ],
  );
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: _DS.primary,
    borderRadius: _DS.r20,
    child: InkWell(
      onTap: onTap,
      borderRadius: _DS.r20,
      hoverColor: Colors.white.withOpacity(0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    ),
  );
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.ctrl,
    required this.label,
    required this.icon,
  });
  final TextEditingController ctrl;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    style: const TextStyle(color: _DS.ink, fontSize: 13),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _DS.inkMid, fontSize: 12),
      prefixIcon: Icon(icon, color: _DS.primary, size: 15),
      filled: true,
      fillColor: _DS.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: _DS.r12,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: _DS.r12,
        borderSide: const BorderSide(color: _DS.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: _DS.r12,
        borderSide: const BorderSide(color: _DS.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: _DS.primarySoft,
              borderRadius: _DS.r20,
            ),
            child: Icon(icon, color: _DS.primary, size: 34),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: _DS.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _DS.inkLight,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChatMsg {
  const _ChatMsg({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}
