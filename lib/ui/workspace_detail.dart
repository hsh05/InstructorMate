// lib/ui/workspace_detail.dart
import 'package:flutter/material.dart';
import '../app/state/workspaces_vm.dart';
import '../app/workspace_models.dart';

// ─────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────
class _DS {
  static const bg = Color(0xFFF7F5FF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF0ECFF);
  static const primary = Color.fromARGB(255, 204, 148, 236);
  static const primarySoft = Color(0xFFEDE8FF);
  static const accent = Color(0xFF00C9A7);
  static const warn = Color(0xFFFF9900);
  static const warnSoft = Color(0xFFFFF4E0);
  static const ink = Color(0xFF1A1535);
  static const inkMid = Color(0xFF5A5470);
  static const inkLight = Color(0xFF9B96B0);
  static const border = Color(0xFFE5E0F8);
  static const red = Color(0xFFE53935);

  static const r8 = BorderRadius.all(Radius.circular(8));
  static const r12 = BorderRadius.all(Radius.circular(12));
  static const r16 = BorderRadius.all(Radius.circular(16));
  static const r20 = BorderRadius.all(Radius.circular(20));
  static const r24 = BorderRadius.all(Radius.circular(24));

  static final shadow = [
    BoxShadow(
      color: primary.withOpacity(0.08),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
  static final shadowSm = [
    BoxShadow(
      color: primary.withOpacity(0.05),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
}

const _fieldLabels = {
  'course_name': 'Course Name',
  'course_title': 'Course Title',
  'course_code': 'Course Code',
  'semester': 'Semester',
  'office_hours': 'Office Hours',
  'instructor_email': 'Instructor Email',
};

const _fieldIcons = {
  'course_name': Icons.book_rounded,
  'course_title': Icons.title_rounded,
  'course_code': Icons.tag_rounded,
  'semester': Icons.calendar_today_rounded,
  'office_hours': Icons.access_time_rounded,
  'instructor_email': Icons.email_outlined,
};

// ─────────────────────────────────────────────
// Main page
// ─────────────────────────────────────────────
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

  bool _isReady(Workspace ws) {
    for (final k in ['course_name', 'semester', 'office_hours']) {
      if ((ws.fields[k] ?? '').trim().isEmpty) return false;
    }
    return true;
  }

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
            backgroundColor: _DS.bg,
            body: Center(child: Text('No workspace selected.')),
          );
        }
        final ready = _isReady(ws);
        final missing = _missingFields(ws);

        return Scaffold(
          backgroundColor: _DS.bg,
          body: NestedScrollView(
            headerSliverBuilder: (_, __) => [_buildSliverHeader(ws, ready)],
            body: Column(
              children: [
                // Tab bar
                Container(
                  color: _DS.surface,
                  child: TabBar(
                    controller: _tabs,
                    labelColor: const Color.fromARGB(255, 211, 171, 235),
                    unselectedLabelColor: _DS.inkLight,
                    indicatorColor: _DS.primary,
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.info_outline_rounded, size: 18),
                        text: 'Info',
                      ),
                      Tab(
                        icon: Icon(Icons.groups_2_rounded, size: 18),
                        text: 'Sections',
                      ),
                      Tab(
                        icon: Icon(Icons.people_alt_rounded, size: 18),
                        text: 'Students',
                      ),
                      Tab(
                        icon: Icon(Icons.auto_awesome_rounded, size: 18),
                        text: 'Ask AI',
                      ),
                    ],
                  ),
                ),
                // Missing fields banner
                if (!ready && missing.isNotEmpty)
                  _MissingBanner(fields: missing),
                // Content
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

  Widget _buildSliverHeader(Workspace ws, bool ready) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: _DS.primary,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.fromARGB(255, 199, 189, 233),
                Color.fromARGB(255, 181, 165, 218),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ws.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            ws.fields['course_code'],
                            ws.fields['semester'],
                          ].where((v) => v != null && v.isNotEmpty).join(' · '),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (ready ? _DS.accent : _DS.warn).withOpacity(0.2),
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
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          ready ? 'Ready' : 'Draft',
                          style: TextStyle(
                            color: ready ? _DS.accent : _DS.warn,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        title: Text(
          ws.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        titlePadding: const EdgeInsets.only(left: 56, bottom: 14),
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
          text: answer ?? "Sorry, I couldn't get an answer.",
          isUser: false,
        ),
      );
      _asking = false;
    });
    _scrollChat();
  }

  void _scrollChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_askScroll.hasClients) {
        _askScroll.animateTo(
          _askScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _DS.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: _DS.r12),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Missing banner
// ─────────────────────────────────────────────
class _MissingBanner extends StatelessWidget {
  const _MissingBanner({required this.fields});
  final List<String> fields;

  @override
  Widget build(BuildContext context) {
    final labels = fields.map((k) => _fieldLabels[k] ?? k).join(', ');
    return Container(
      width: double.infinity,
      color: _DS.warnSoft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _DS.warn, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Complete missing fields: $labels',
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

// ─────────────────────────────────────────────
// TAB 1 — Info
// ─────────────────────────────────────────────
class _InfoTab extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              ...editableKeys.map((key) {
                final value = ws.fields[key] ?? '';
                final label = _fieldLabels[key] ?? key;
                final icon = _fieldIcons[key] ?? Icons.edit_rounded;
                final isEmpty = value.trim().isEmpty;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextField(
                    controller: ctrl(key, value),
                    style: const TextStyle(
                      color: _DS.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      labelText: label,
                      labelStyle: TextStyle(
                        color: isEmpty ? _DS.warn : _DS.inkMid,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      prefixIcon: Icon(icon, color: _DS.primary, size: 18),
                      suffixIcon: isEmpty
                          ? const Icon(
                              Icons.error_outline_rounded,
                              color: _DS.warn,
                              size: 18,
                            )
                          : null,
                      filled: true,
                      fillColor: isEmpty ? _DS.warnSoft : _DS.surfaceAlt,
                      border: OutlineInputBorder(
                        borderRadius: _DS.r12,
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: _DS.r12,
                        borderSide: BorderSide(
                          color: isEmpty
                              ? _DS.warn.withOpacity(0.4)
                              : _DS.border,
                        ),
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
                        vertical: 14,
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _DS.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(borderRadius: _DS.r12),
                  ),
                  onPressed: onSave,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text(
                    'Save Changes',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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

// ─────────────────────────────────────────────
// TAB 2 — Sections
// ─────────────────────────────────────────────
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
  final _draft = SectionDraft();
  final _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _instructorCtrl = TextEditingController();
  final _startCtrl = TextEditingController(text: '09:00');
  final _endCtrl = TextEditingController(text: '10:15');
  bool _saving = false;

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
                  label: 'Add Section',
                  icon: Icons.add_rounded,
                  onTap: () => setState(() => _showForm = true),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (_showForm) ...[_buildForm(), const SizedBox(height: 16)],
        if (ws.sections.isEmpty && !_showForm)
          _EmptyState(
            icon: Icons.groups_2_rounded,
            title: 'No sections yet',
            subtitle: 'Tap "Add Section" to create your first class section.',
          )
        else
          ...ws.sections.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SectionCard(section: s),
            ),
          ),
      ],
    );
  }

  Widget _buildForm() {
    return Container(
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: _DS.r16,
        border: Border.all(color: _DS.primary.withOpacity(0.3)),
        boxShadow: _DS.shadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'New Section',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: _DS.ink,
            ),
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
            label: 'Instructor Name',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 10),
          _FormField(
            ctrl: _locationCtrl,
            label: 'Location / Room',
            icon: Icons.location_on_rounded,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _FormField(
                  ctrl: _startCtrl,
                  label: 'Start Time',
                  icon: Icons.schedule_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FormField(
                  ctrl: _endCtrl,
                  label: 'End Time',
                  icon: Icons.schedule_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Days',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _DS.inkMid,
            ),
          ),
          const SizedBox(height: 8),
          StatefulBuilder(
            builder: (_, setInner) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _days.map((d) {
                final sel = _draft.days.contains(d);
                return GestureDetector(
                  onTap: () {
                    setInner(() {
                      final list = List<String>.from(_draft.days);
                      sel ? list.remove(d) : list.add(d);
                      _draft.days = list;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
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
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _DS.inkMid,
                    side: const BorderSide(color: _DS.border),
                    shape: const RoundedRectangleBorder(borderRadius: _DS.r12),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => setState(() => _showForm = false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _DS.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(borderRadius: _DS.r12),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : _saveSection,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Create',
                          style: TextStyle(fontWeight: FontWeight.w700),
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
    try {
      final updated = await widget.vm.api.createSection(widget.ws.id, _draft);
      widget.vm.current = updated;
      widget.vm.notifyListeners();
      setState(() {
        _showForm = false;
        _saving = false;
      });
    } catch (e) {
      setState(() => _saving = false);
      widget.onError(e.toString());
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});
  final Section section;

  @override
  Widget build(BuildContext context) {
    final sch = section.schedule;
    final days = sch.days.isEmpty ? '—' : sch.days.join(', ');
    final time = (sch.startTime.isNotEmpty && sch.endTime.isNotEmpty)
        ? '${sch.startTime} – ${sch.endTime}'
        : '—';
    return Container(
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: _DS.r16,
        boxShadow: _DS.shadowSm,
        border: Border.all(color: _DS.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: _DS.primarySoft,
              borderRadius: _DS.r12,
            ),
            child: const Icon(
              Icons.groups_2_rounded,
              color: _DS.primary,
              size: 22,
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
                    fontSize: 14,
                    color: _DS.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 12,
                      color: _DS.inkLight,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      days,
                      style: const TextStyle(fontSize: 12, color: _DS.inkMid),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.schedule_rounded,
                      size: 12,
                      color: _DS.inkLight,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      time,
                      style: const TextStyle(fontSize: 12, color: _DS.inkMid),
                    ),
                  ],
                ),
                if (section.location.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 12,
                        color: _DS.inkLight,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        section.location,
                        style: const TextStyle(fontSize: 12, color: _DS.inkMid),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TAB 3 — Students
// ─────────────────────────────────────────────
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
        _SectionHeader(title: 'Students', icon: Icons.people_alt_rounded),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _DS.surface,
            borderRadius: _DS.r16,
            boxShadow: _DS.shadow,
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: '${ws.studentsCount}',
                  label: 'Total Students',
                  icon: Icons.people_alt_rounded,
                  color: _DS.primary,
                ),
              ),
              Container(width: 1, height: 50, color: _DS.border),
              Expanded(
                child: _StatTile(
                  value: '${ws.sections.length}',
                  label: 'Sections',
                  icon: Icons.groups_2_rounded,
                  color: _DS.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () async {
            await vm.importStudents();
            if (vm.error != null) onError(vm.error!);
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color.fromARGB(255, 191, 176, 231), Color(0xFF9B6EFF)],
              ),
              borderRadius: _DS.r16,
              boxShadow: _DS.shadow,
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: _DS.r12,
                  ),
                  child: const Icon(
                    Icons.upload_file_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Import Student List',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Supports .csv and .xlsx files',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white70,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        if (ws.studentsCount == 0) ...[
          const SizedBox(height: 24),
          _EmptyState(
            icon: Icons.people_alt_rounded,
            title: 'No students imported',
            subtitle:
                'Import a CSV or Excel file with name, email, and student number columns.',
          ),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: _DS.inkLight,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// TAB 4 — Ask AI
// ─────────────────────────────────────────────
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
    return Column(
      children: [
        Expanded(
          child: chat.isEmpty
              ? _AskEmptyState(ctrl: ctrl, onAsk: onAsk)
              : ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(16),
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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  style: const TextStyle(color: _DS.ink, fontSize: 14),
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
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: onAsk,
                  textInputAction: TextInputAction.send,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: asking ? null : () => onAsk(ctrl.text),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: asking ? _DS.inkLight : _DS.primary,
                    borderRadius: _DS.r20,
                  ),
                  child: asking
                      ? const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
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
  const _AskEmptyState({required this.ctrl, required this.onAsk});
  final TextEditingController ctrl;
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
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6C47D4), Color(0xFF9B6EFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: _DS.r20,
          ),
          child: Column(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(height: 10),
              const Text(
                'Ask Your Syllabus',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Get instant answers from your uploaded syllabus. Try one of these:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...suggestions.map(
          (q) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => onAsk(q),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _DS.surface,
                  borderRadius: _DS.r12,
                  border: Border.all(color: _DS.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: _DS.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        q,
                        style: const TextStyle(
                          color: _DS.inkMid,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: _DS.inkLight,
                    ),
                  ],
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
  Widget build(BuildContext context) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isUser ? _DS.primary : _DS.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
          ),
          boxShadow: _DS.shadowSm,
          border: msg.isUser ? null : Border.all(color: _DS.border),
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: msg.isUser ? Colors.white : _DS.ink,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _DS.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: _DS.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 14,
              color: _DS.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'Thinking…',
              style: TextStyle(
                color: _DS.inkLight,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────
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
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _DS.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _DS.ink,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: const BoxDecoration(
          color: _DS.primary,
          borderRadius: _DS.r20,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: _DS.ink, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _DS.inkMid, fontSize: 12),
        prefixIcon: Icon(icon, color: _DS.primary, size: 16),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Center(
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
}

class _ChatMsg {
  const _ChatMsg({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}
