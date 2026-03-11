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
  'instructor_email': 'Instructor Email',
};
const _fieldIcons = {
  'course_name': Icons.book_rounded,
  'course_code': Icons.tag_rounded,
  'semester': Icons.calendar_today_rounded,
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
    'instructor_email',
  ];

  // Office hours slots: each slot = {days: List<String>, start: String, end: String}
  List<Map<String, dynamic>> _ohSlots = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _syncControllersFromWorkspace();
    _loadOhSlots();
  }

  void _loadOhSlots() {
    final ws = widget.vm.current;
    if (ws == null) return;
    const validDays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'};
    final raw = ws.fields['office_hours'] ?? '';
    if (raw.contains('|')) {
      try {
        final parsed = raw
            .split(';')
            .map((slot) {
              final parts = slot.split('|');
              final cleanDays =
                  (parts.isNotEmpty ? parts[0].split(',') : <String>[])
                      .map((d) => d.trim())
                      .where((d) => validDays.contains(d))
                      .toList();
              return <String, dynamic>{
                'days': cleanDays,
                'start': parts.length > 1 ? parts[1].trim() : '',
                'end': parts.length > 2 ? parts[2].trim() : '',
              };
            })
            .where((s) => (s['start'] as String).isNotEmpty)
            .toList();
        if (parsed.isNotEmpty) {
          _ohSlots = parsed;
          return;
        }
      } catch (_) {}
    }
    // Legacy fallback: "09:00" or "09:00 – 11:00"
    final parts = raw.split(' – ');
    _ohSlots = [
      {
        'days': <String>[],
        'start': parts[0].trim(),
        'end': parts.length > 1 ? parts[1].trim() : '',
      },
    ];
  }

  String _encodeOhSlots() {
    return _ohSlots.map((s) {
      final days = (s['days'] as List).join(',');
      final start = s['start'] as String? ?? '';
      final end = s['end'] as String? ?? '';
      return '$days|$start|$end';
    }).join(';');
  }

  /// Validate all OH slots — returns error string or null
  String? _validateOhSlots() {
    if (_ohSlots.isEmpty) return null; // optional field
    for (int i = 0; i < _ohSlots.length; i++) {
      final slot = _ohSlots[i];
      final days = slot['days'] as List;
      final start = (slot['start'] as String? ?? '').trim();
      final end = (slot['end'] as String? ?? '').trim();

      if (days.isEmpty) return 'Slot ${i + 1}: please select at least one day.';
      if (start.isEmpty) return 'Slot ${i + 1}: start time is required.';
      if (end.isEmpty) return 'Slot ${i + 1}: end time is required.';

      final startMins = _parseTimeToMins(start);
      final endMins = _parseTimeToMins(end);
      if (startMins == null)
        return 'Slot ${i + 1}: invalid start time "$start".';
      if (endMins == null) return 'Slot ${i + 1}: invalid end time "$end".';
      if (endMins <= startMins) {
        return 'Slot ${i + 1}: end time must be after start time ($start → $end).';
      }
    }
    return null;
  }

  /// Parse "9:30 AM" or "09:30" → total minutes from midnight
  int? _parseTimeToMins(String val) {
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

  @override
  void didUpdateWidget(WorkspaceDetailPage old) {
    super.didUpdateWidget(old);
    if (old.vm.current != widget.vm.current) {
      _syncControllersFromWorkspace();
      _loadOhSlots(); // reload OH slots when workspace changes
    }
  }

  void _syncControllersFromWorkspace() {
    final ws = widget.vm.current;
    if (ws == null) return;

    for (final key in _editableKeys) {
      String value = ws.fields[key] ?? '';
      // FIX: The PDF extractor writes 'course_title' but the UI field is
      // 'course_name'. Fall back to course_title so the field auto-fills.
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
        final ready = _isReady(ws);
        final missing = _missingFields(ws);

        return Scaffold(
          backgroundColor: AppColors.bg,
          // FIX: Wrap in ScrollConfiguration to disable the auto-injected web
          // Scrollbar. Flutter's MaterialScrollBehavior on web wraps every
          // scrollable with a Scrollbar that requires a single ScrollPosition.
          // NestedScrollView creates multiple ScrollPositions internally, so
          // the injected Scrollbar crashes with "attached to more than one
          // ScrollPosition" whenever an AnimationController (e.g. the bell
          // shake) notifies its status listeners during a scroll event.
          body: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: NestedScrollView(
              headerSliverBuilder: (_, __) => [_buildHeader(ws, ready)],
              body: Column(
                children: [
                  Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          )
                        : TabBarView(
                            controller: _tabs,
                            children: [
                              _InfoTab(
                                ws: ws,
                                editableKeys: _editableKeys,
                                ctrl: _ctrl,
                                onSave: _onSave,
                                ohSlots: _ohSlots,
                                onOhChanged: (slots) =>
                                    setState(() => _ohSlots = slots),
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
                                  if (widget.vm.error != null) {
                                    _showError(widget.vm.error!);
                                  }
                                },
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ), // ScrollConfiguration
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
                            label: semester,
                          ),
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
    // Validate OH slots before saving
    final ohError = _validateOhSlots();
    if (ohError != null) {
      _showError(ohError);
      return;
    }

    final updated = {
      for (final k in _editableKeys) k: (_fieldCtrl[k]?.text.trim() ?? ''),
      // workspaces_vm.updateFields() picks up 'office_hours_start' and
      // writes it to the real DB column 'office_hours'.
      'office_hours_start': _encodeOhSlots(),
    };
    await widget.vm.updateFields(updated);
    if (!mounted) return;
    if (widget.vm.error != null) {
      _showError(widget.vm.error!);
    } else {
      _syncControllersFromWorkspace();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Changes saved ✓'),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppColors.r12),
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

// ── Stat pill ──────────────────────────────────────────────────────────────────
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
              ? AppColors.accent.withOpacity(0.2)
              : Colors.white.withOpacity(0.15),
          borderRadius: AppColors.r20,
          border: Border.all(
            color: highlight
                ? AppColors.accent.withOpacity(0.5)
                : Colors.white.withOpacity(0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: highlight ? AppColors.accent : Colors.white,
              size: 11,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: highlight ? AppColors.accent : Colors.white,
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
      color: AppColors.warnSoft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.warn,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Complete: $labels',
              style: const TextStyle(
                color: AppColors.warn,
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

// ─── TAB 1 — Info ─────────────────────────────────────────────────────────────
class _InfoTab extends StatefulWidget {
  const _InfoTab({
    required this.ws,
    required this.editableKeys,
    required this.ctrl,
    required this.onSave,
    required this.ohSlots,
    required this.onOhChanged,
  });
  final Workspace ws;
  final List<String> editableKeys;
  final TextEditingController Function(String, String) ctrl;
  final Future<void> Function() onSave;
  final List<Map<String, dynamic>> ohSlots;
  final void Function(List<Map<String, dynamic>>) onOhChanged;

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

String? _validateField(String key, String value) {
  final v = value.trim();
  if (v.isEmpty) return '${_fieldLabels[key] ?? key} is required';
  switch (key) {
    case 'instructor_email':
      final emailRe = RegExp(
        r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$',
        caseSensitive: false,
      );
      if (!emailRe.hasMatch(v)) return 'Enter a valid email address';
      break;
  }
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
    if (key == 'instructor_email') return TextInputType.emailAddress;
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
          title: 'Course Details',
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap any field to edit. All fields are required.',
          style: TextStyle(fontSize: 12, color: AppColors.inkMid),
        ),
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
                return Column(
                  children: [
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
                            group.key,
                            widget.ctrl(group.key, '').text,
                          );
                        }
                      }),
                    ),
                    if (!isLast)
                      const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: AppColors.border,
                      ),
                  ],
                );
              }),
              // ── Office Hours Slots ──────────────────────────────────
              const Divider(height: 1, color: AppColors.border),
              _OfficeHoursSlotsWidget(
                slots: widget.ohSlots,
                onChanged: (slots) {
                  widget.onOhChanged(slots);
                  setState(() => _dirty = true);
                },
              ),
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
                                borderRadius: AppColors.r12,
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
                Row(
                  children: const [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warn,
                      size: 15,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Please fix the following:',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppColors.warn,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ..._errors.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '• ${e.value}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.warn,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Field group model ──────────────────────────────────────────────────────────
class _FieldGroup {
  final String key;
  final String? secondKey;
  bool get isPair => false;
  const _FieldGroup.single(this.key) : secondKey = null;
}

// ── Single field row ───────────────────────────────────────────────────────────
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
            Text(
              label,
              style: TextStyle(
                color: hasError ? AppColors.warn : AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl(fieldKey, value),
              autofocus: true,
              keyboardType: keyboardType,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                prefixIcon: Icon(
                  icon,
                  color: hasError ? AppColors.warn : AppColors.primary,
                  size: 17,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.check_circle_rounded,
                    color: hasError ? AppColors.warn : AppColors.accent,
                  ),
                  onPressed: onDone,
                ),
                hintText: _hintFor(fieldKey),
                hintStyle: const TextStyle(
                  color: AppColors.inkLight,
                  fontSize: 13,
                ),
                filled: true,
                fillColor:
                    hasError ? AppColors.warnSoft : AppColors.primarySoft,
                border: OutlineInputBorder(
                  borderRadius: AppColors.r12,
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppColors.r12,
                  borderSide: BorderSide(
                    color: hasError ? AppColors.warn : AppColors.primary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
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
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: hasError
                      ? AppColors.warnSoft
                      : (isEmpty ? AppColors.warnSoft : AppColors.primarySoft),
                  borderRadius: AppColors.r10,
                ),
                child: Icon(
                  icon,
                  color: hasError
                      ? AppColors.warn
                      : (isEmpty ? AppColors.warn : AppColors.primary),
                  size: 17,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.inkLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                      Text(
                        error!,
                        style: const TextStyle(
                          color: AppColors.warn,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
            ],
          ),
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
    case 'instructor_email':
      return 'e.g. prof@university.edu';
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
  });
  final Workspace ws;
  final WorkspacesViewModel vm;
  final void Function(String) onError;

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

  // ── Time helpers ────────────────────────────────────────────────────────────

  ({int hour, int minIdx, bool isPM}) _parseTime(String val) {
    if (val.isEmpty) return (hour: 8, minIdx: 0, isPM: false);
    final upper = val.toUpperCase();
    final isPM = upper.contains('PM');
    final isAM = upper.contains('AM');
    final clean = val.replaceAll(RegExp(r'[AaPp][Mm]'), '').trim();
    final parts = clean.split(':');
    int h = int.tryParse(parts[0].trim()) ?? 8;
    int m = int.tryParse(parts.length > 1 ? parts[1].trim() : '0') ?? 0;
    if (h == 0)
      h = 12;
    else if (h > 12 && !isPM)
      h -= 12; // handle 24h legacy input
    else if (h > 12) h -= 12;
    // Snap to nearest 5-min slot
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

  // ── Bottom sheet ────────────────────────────────────────────────────────────

  void _showSectionSheet(BuildContext ctx, {Section? editing}) {
    // Pre-fill from existing section or defaults
    String selName = editing?.name ?? '';
    String selLocation = editing?.location ?? '';
    List<String> selDays = List.from(editing?.schedule.days ?? []);
    int selReminderMins = editing?.schedule.reminderMinutes ?? 10;

    final startParsed = _parseTime(editing?.schedule.startTime ?? '');
    final endParsed = _parseTime(editing?.schedule.endTime ?? '');
    int startH = startParsed.hour, startMIdx = startParsed.minIdx;
    bool startPM = startParsed.isPM;
    int endH = endParsed.hour, endMIdx = endParsed.minIdx;
    bool endPM = endParsed.isPM;

    final nameCtrl = TextEditingController(text: selName);
    final locationCtrl = TextEditingController(text: selLocation);
    bool saving = false;
    String? sheetError;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (bsCtx, setBS) {
          Widget sectionLabel(String text) => Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.inkLight,
                    letterSpacing: 1.2,
                  ),
                ),
              );

          Widget hourRow(int selHour, void Function(int) onSel) =>
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(12, (idx) {
                    final h = idx + 1;
                    final sel = selHour == h;
                    return GestureDetector(
                      onTap: () => setBS(() => onSel(h)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 110),
                        margin: const EdgeInsets.only(right: 6),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : AppColors.surfaceAlt,
                          borderRadius: AppColors.r10,
                          border: Border.all(
                            color: sel ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$h',
                          style: TextStyle(
                            color: sel ? Colors.white : AppColors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );

          Widget minRow(int selMin, void Function(int) onSel) =>
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_minLabels.length, (idx) {
                    final sel = selMin == idx;
                    return GestureDetector(
                      onTap: () => setBS(() => onSel(idx)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 110),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : AppColors.surfaceAlt,
                          borderRadius: AppColors.r10,
                          border: Border.all(
                            color: sel ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        child: Text(
                          ':${_minLabels[idx]}',
                          style: TextStyle(
                            color: sel ? Colors.white : AppColors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );

          Widget ampmRow(bool isPM, void Function(bool) onSel) => Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: AppColors.r10,
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final pm in [false, true])
                      GestureDetector(
                        onTap: () => setBS(() => onSel(pm)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 110),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: isPM == pm
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: AppColors.r10,
                          ),
                          child: Text(
                            pm ? 'PM' : 'AM',
                            style: TextStyle(
                              color:
                                  isPM == pm ? Colors.white : AppColors.inkMid,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.94,
            minChildSize: 0.6,
            maxChildSize: 0.97,
            builder: (_, scrollCtrl) => ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  editing != null ? 'Edit Section' : 'New Section',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.ink,
                  ),
                ),

                // ── Name & Location ──────────────────────────────────────────
                sectionLabel('SECTION NAME'),
                TextField(
                  controller: nameCtrl,
                  onChanged: (v) => setBS(() {
                    selName = v;
                    sheetError = null;
                  }),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Section A',
                    hintStyle: const TextStyle(
                      color: AppColors.inkLight,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: AppColors.r10,
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppColors.r10,
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppColors.r10,
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),

                sectionLabel('LOCATION / ROOM'),
                TextField(
                  controller: locationCtrl,
                  onChanged: (v) => setBS(() => selLocation = v),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Room 204',
                    hintStyle: const TextStyle(
                      color: AppColors.inkLight,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: AppColors.r10,
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppColors.r10,
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppColors.r10,
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),

                // ── Days ────────────────────────────────────────────────────
                sectionLabel('DAYS'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _days.map((d) {
                    final sel = selDays.contains(d);
                    return GestureDetector(
                      onTap: () => setBS(() {
                        sel ? selDays.remove(d) : selDays.add(d);
                        sheetError = null;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 110),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : AppColors.surfaceAlt,
                          borderRadius: AppColors.r10,
                          border: Border.all(
                            color: sel ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        child: Text(
                          d,
                          style: TextStyle(
                            color: sel ? Colors.white : AppColors.inkMid,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // ── Start time ───────────────────────────────────────────────
                sectionLabel('START — HOUR'),
                hourRow(startH, (h) => startH = h),
                sectionLabel('START — MINUTES'),
                minRow(startMIdx, (m) => startMIdx = m),
                sectionLabel('START — PERIOD'),
                ampmRow(startPM, (pm) => startPM = pm),

                // ── End time ─────────────────────────────────────────────────
                sectionLabel('END — HOUR'),
                hourRow(endH, (h) => endH = h),
                sectionLabel('END — MINUTES'),
                minRow(endMIdx, (m) => endMIdx = m),
                sectionLabel('END — PERIOD'),
                ampmRow(endPM, (pm) => endPM = pm),

                // ── Reminder ─────────────────────────────────────────────────
                sectionLabel('REMINDER BEFORE CLASS'),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [5, 10, 15, 20, 30].map((mins) {
                      final sel = selReminderMins == mins;
                      return GestureDetector(
                        onTap: () => setBS(() => selReminderMins = mins),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 110),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color:
                                sel ? AppColors.primary : AppColors.surfaceAlt,
                            borderRadius: AppColors.r10,
                            border: Border.all(
                              color: sel ? AppColors.primary : AppColors.border,
                            ),
                          ),
                          child: Text(
                            '${mins}min',
                            style: TextStyle(
                              color: sel ? Colors.white : AppColors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Live preview pill ────────────────────────────────────────
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: AppColors.r20,
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      '${selDays.isEmpty ? "No days" : selDays.join(", ")}  ·  '
                      '${_formatTime(startH, startMIdx, startPM)} → ${_formatTime(endH, endMIdx, endPM)}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),

                // ── Error ────────────────────────────────────────────────────
                if (sheetError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warnSoft,
                      borderRadius: AppColors.r10,
                      border: Border.all(
                        color: AppColors.warn.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 15,
                          color: AppColors.warn,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            sheetError!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.warn,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Save button ──────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppColors.r12,
                      ),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            // ── Validation ──
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) {
                              setBS(
                                () => sheetError = 'Section name is required.',
                              );
                              return;
                            }
                            if (selDays.isEmpty) {
                              setBS(
                                () => sheetError =
                                    'Please select at least one day.',
                              );
                              return;
                            }
                            final startStr = _formatTime(
                              startH,
                              startMIdx,
                              startPM,
                            );
                            final endStr = _formatTime(endH, endMIdx, endPM);
                            final startMins = _timeToMins(startStr);
                            final endMins = _timeToMins(endStr);
                            if (startMins != null &&
                                endMins != null &&
                                endMins <= startMins) {
                              setBS(
                                () => sheetError =
                                    'End time must be after start time ($startStr → $endStr).',
                              );
                              return;
                            }

                            setBS(() => saving = true);
                            try {
                              final draft = SectionDraft()
                                ..name = name
                                ..location = locationCtrl.text.trim()
                                ..days = selDays
                                ..startTime = startStr
                                ..endTime = endStr
                                ..reminderMinutes = selReminderMins;

                              if (editing != null) {
                                // UPDATE in-place: preserves section_id → students stay intact
                                await widget.vm.updateSection(
                                  editing.id,
                                  draft,
                                );
                              } else {
                                await widget.vm.createSection(draft);
                              }

                              if (bsCtx.mounted) Navigator.pop(bsCtx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      editing != null
                                          ? 'Section updated ✓'
                                          : 'Section created ✓',
                                    ),
                                    backgroundColor: AppColors.accent,
                                    behavior: SnackBarBehavior.floating,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: AppColors.r12,
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              setBS(() {
                                saving = false;
                                sheetError = e.toString();
                              });
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            editing != null ? 'Save Changes' : 'Create Section',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      locationCtrl.dispose();
    });
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
            label: '+ Add Section',
            onTap: () => _showSectionSheet(context),
          ),
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
          ...ws.sections.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SectionCard(
                section: s,
                onDelete: () => _confirmDelete(s),
                onEdit: () => _showSectionSheet(context, editing: s),
                vm: widget.vm,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(Section s) async {
    final ok = await showDialog<bool>(
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
              'Delete "${s.name.isNotEmpty ? s.name : "this section"}"?',
              style: const TextStyle(fontSize: 13, color: AppColors.inkMid),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.inkLight),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
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
}

// ─── Section card ──────────────────────────────────────────────────────────────
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
        : '—';
    final count = vm.countForSection(section.id);

    return Material(
      color: AppColors.surface,
      borderRadius: AppColors.r16,
      child: InkWell(
        borderRadius: AppColors.r16,
        hoverColor: AppColors.primarySoft.withOpacity(0.5),
        splashColor: AppColors.primary.withOpacity(0.08),
        highlightColor: Colors.transparent,
        onTap: onEdit,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppColors.r16,
            boxShadow: AppColors.shadowSm,
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: AppColors.r12,
                ),
                child: const Icon(
                  Icons.groups_2_rounded,
                  color: AppColors.primary,
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
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          size: 11,
                          color: AppColors.inkLight,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            days,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.inkMid,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.schedule_rounded,
                          size: 11,
                          color: AppColors.inkLight,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            time,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.inkMid,
                            ),
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
                            color: AppColors.inkLight,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              section.location,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.inkMid,
                              ),
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
                          color: AppColors.inkLight,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            '$count student${count == 1 ? "" : "s"}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: count > 0
                                  ? AppColors.accent
                                  : AppColors.inkMid,
                              fontWeight:
                                  count > 0 ? FontWeight.w700 : FontWeight.w400,
                            ),
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
                  color: AppColors.primary,
                  size: 20,
                ),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'Delete section',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.red,
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

// ─── TAB 3 — Students ─────────────────────────────────────────────────────────
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
        const _SectionHeader(
          title: 'Students by Section',
          icon: Icons.people_alt_rounded,
        ),
        const SizedBox(height: 6),
        const Text(
          'Tap a section to view or import students.',
          style: TextStyle(fontSize: 12, color: AppColors.inkMid),
        ),
        const SizedBox(height: 14),
        if (ws.sections.isEmpty)
          const _EmptyState(
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
      final list = await widget.vm.api.listSectionStudents(
        widget.ws.id,
        widget.section.id,
      );
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

    // ── Detect same vs different file using SHA-256 ───────────────────────
    final newHash = sha256.convert(bytes).toString();
    final storedHash = widget.section.lastImportHash;
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
              isSameFile: isSameFile,
            ),
          ) ??
          false;
      if (!confirmed) return;
    }

    // ── Upload ────────────────────────────────────────────────────────────
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
                  ? '✓ ${result.imported} student${result.imported == 1 ? "" : "s"} imported successfully'
                  : 'No students found — check your file has name/email columns',
            ),
            backgroundColor:
                result.imported > 0 ? AppColors.accent : AppColors.warn,
            behavior: SnackBarBehavior.floating,
            shape: const RoundedRectangleBorder(borderRadius: AppColors.r12),
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
        color: AppColors.surface,
        borderRadius: AppColors.r16,
        boxShadow: AppColors.shadowSm,
        border: Border.all(
          color:
              _expanded ? AppColors.primary.withOpacity(0.4) : AppColors.border,
          width: _expanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : AppColors.r16,
            child: InkWell(
              onTap: _toggle,
              borderRadius: _expanded
                  ? const BorderRadius.vertical(top: Radius.circular(16))
                  : AppColors.r16,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: count > 0
                            ? AppColors.accentSoft
                            : AppColors.primarySoft,
                        borderRadius: AppColors.r12,
                      ),
                      child: Icon(
                        Icons.groups_2_rounded,
                        color: count > 0 ? AppColors.accent : AppColors.primary,
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
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.inkMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: count > 0
                            ? AppColors.accentSoft
                            : AppColors.surfaceAlt,
                        borderRadius: AppColors.r20,
                      ),
                      child: _importing
                          ? const SizedBox(
                              width: 36,
                              height: 12,
                              child: LinearProgressIndicator(
                                color: AppColors.accent,
                                backgroundColor: AppColors.accentSoft,
                              ),
                            )
                          : Text(
                              '$count student${count == 1 ? "" : "s"}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: count > 0
                                    ? AppColors.accent
                                    : AppColors.inkLight,
                              ),
                            ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.inkLight,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: _expanded
                ? Column(
                    children: [
                      const Divider(height: 1, color: AppColors.border),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Material(
                              color: _importing
                                  ? AppColors.surfaceAlt
                                  : AppColors.primarySoft,
                              borderRadius: AppColors.r12,
                              child: InkWell(
                                onTap:
                                    _importing ? null : () => _import(context),
                                borderRadius: AppColors.r12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: AppColors.r12,
                                    border: Border.all(
                                      color: _importing
                                          ? AppColors.border
                                          : AppColors.primary.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.upload_file_rounded,
                                        color: _importing
                                            ? AppColors.inkLight
                                            : AppColors.primary,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _importing
                                              ? 'Importing…'
                                              : 'Import student list (.csv / .xlsx)',
                                          style: TextStyle(
                                            color: _importing
                                                ? AppColors.inkLight
                                                : AppColors.primary,
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
                                            color: AppColors.primary,
                                          ),
                                        )
                                      else
                                        const Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          color: AppColors.primary,
                                          size: 12,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (_loadingRoster)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.primary,
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
                                        color: AppColors.surfaceAlt,
                                        borderRadius: AppColors.r12,
                                      ),
                                      child: const Icon(
                                        Icons.people_outline_rounded,
                                        color: AppColors.inkLight,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'No students imported yet',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: AppColors.inkMid,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Upload a CSV/XLSX with name, email, student_no columns.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.inkLight,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              const SizedBox(height: 10),
                              TextField(
                                controller: _searchCtrl,
                                onChanged: (v) => setState(() => _search = v),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.ink,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search students…',
                                  hintStyle: const TextStyle(
                                    color: AppColors.inkLight,
                                    fontSize: 12,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    color: AppColors.inkLight,
                                    size: 18,
                                  ),
                                  suffixIcon: _search.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.clear_rounded,
                                            color: AppColors.inkLight,
                                            size: 16,
                                          ),
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
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...filtered.asMap().entries.map((e) {
                                final i = e.key;
                                final s = e.value;
                                return Container(
                                  color: i.isEven
                                      ? Colors.transparent
                                      : AppColors.surfaceAlt.withOpacity(0.45),
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
                                            color: AppColors.inkLight,
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
                                            color: AppColors.ink,
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
                                            color: AppColors.inkMid,
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
                                            color: AppColors.inkLight,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _search.isNotEmpty
                                      ? '${filtered.length} of ${_students.length} shown'
                                      : '${_students.length} student${_students.length == 1 ? "" : "s"} total',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.inkLight,
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

// ─── TAB 4 — Ask AI ───────────────────────────────────────────────────────────
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
          color: AppColors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              const Icon(
                Icons.picture_as_pdf_rounded,
                color: AppColors.primary,
                size: 15,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "If AI isn't answering, re-upload the PDF.",
                  style: TextStyle(fontSize: 11, color: AppColors.inkMid),
                ),
              ),
              Material(
                color: AppColors.primary,
                borderRadius: AppColors.r8,
                child: InkWell(
                  onTap: onReupload,
                  borderRadius: AppColors.r8,
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
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Row(
            children: [
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
                      borderRadius: AppColors.r20,
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
                    color: asking ? AppColors.inkLight : AppColors.primary,
                    borderRadius: AppColors.r20,
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
            borderRadius: AppColors.r20,
          ),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: AppColors.r16,
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
              color: AppColors.inkMid,
            ),
          ),
        ),
        ...suggestions.map(
          (q) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.surface,
              borderRadius: AppColors.r12,
              child: InkWell(
                onTap: () => onAsk(q),
                borderRadius: AppColors.r12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: AppColors.r12,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: AppColors.r8,
                        ),
                        child: const Icon(
                          Icons.lightbulb_outline_rounded,
                          color: AppColors.primary,
                          size: 15,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          q,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 11,
                        color: AppColors.inkLight,
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
          child: Text(
            msg.text,
            style: TextStyle(
              color: msg.isUser ? Colors.white : AppColors.ink,
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
            color: AppColors.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomRight: Radius.circular(14),
              bottomLeft: Radius.circular(3),
            ),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.auto_awesome_rounded,
                  size: 13, color: AppColors.primary),
              SizedBox(width: 5),
              Text(
                'Thinking…',
                style: TextStyle(
                  color: AppColors.inkLight,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Office Hours Slots Widget ─────────────────────────────────────────────────
// Professional day-picker + time-range per slot, add/remove slots freely.
class _OfficeHoursSlotsWidget extends StatefulWidget {
  const _OfficeHoursSlotsWidget({required this.slots, required this.onChanged});
  final List<Map<String, dynamic>> slots;
  final void Function(List<Map<String, dynamic>>) onChanged;

  @override
  State<_OfficeHoursSlotsWidget> createState() =>
      _OfficeHoursSlotsWidgetState();
}

class _OfficeHoursSlotsWidgetState extends State<_OfficeHoursSlotsWidget> {
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

  List<Map<String, dynamic>> get _slots => widget.slots;
  void _notify() => widget.onChanged(List.of(_slots));

  void _addSlot() {
    setState(() => _slots.add({'days': <String>[], 'start': '', 'end': ''}));
    _notify();
  }

  void _removeSlot(int i) {
    setState(() => _slots.removeAt(i));
    _notify();
  }

  ({int hour, int minIdx, bool isPM}) _parse(String val) {
    if (val.isEmpty) return (hour: 9, minIdx: 0, isPM: false);
    final upper = val.toUpperCase();
    final isPM = upper.contains('PM');
    final clean = val.replaceAll(RegExp(r'[AaPp][Mm]'), '').trim();
    final parts = clean.split(':');
    int h = int.tryParse(parts[0].trim()) ?? 9;
    int m = int.tryParse(parts.length > 1 ? parts[1].trim() : '0') ?? 0;
    if (h == 0)
      h = 12;
    else if (h > 12) h -= 12;
    int minIdx = 0;
    int minDist = 999;
    for (int j = 0; j < _minLabels.length; j++) {
      final d = (int.parse(_minLabels[j]) - m).abs();
      if (d < minDist) {
        minDist = d;
        minIdx = j;
      }
    }
    return (hour: h, minIdx: minIdx, isPM: isPM);
  }

  String _format(int hour12, int minIdx, bool isPM) =>
      '$hour12:${_minLabels[minIdx]} ${isPM ? "PM" : "AM"}';

  void _setSlot(int i, {List<String>? days, String? start, String? end}) {
    setState(() {
      if (days != null) _slots[i]['days'] = days;
      if (start != null) _slots[i]['start'] = start;
      if (end != null) _slots[i]['end'] = end;
    });
    _notify();
  }

  void _showSlotSheet(BuildContext ctx, int i) {
    final slot = _slots[i];
    List<String> selDays = List<String>.from(slot['days'] as List);
    final startParsed = _parse(slot['start'] as String? ?? '');
    final endParsed = _parse(slot['end'] as String? ?? '');
    int startH = startParsed.hour, startM = startParsed.minIdx;
    bool startPM = startParsed.isPM;
    int endH = endParsed.hour, endM = endParsed.minIdx;
    bool endPM = endParsed.isPM;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (bsCtx, setBS) {
          Widget sectionLabel(String text) => Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.inkLight,
                    letterSpacing: 1.2,
                  ),
                ),
              );

          Widget hourRow(int selHour, void Function(int) onSel) =>
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(12, (idx) {
                    final h = idx + 1;
                    final sel = selHour == h;
                    return GestureDetector(
                      onTap: () => setBS(() => onSel(h)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 110),
                        margin: const EdgeInsets.only(right: 6),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : AppColors.surfaceAlt,
                          borderRadius: AppColors.r10,
                          border: Border.all(
                            color: sel ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$h',
                          style: TextStyle(
                            color: sel ? Colors.white : AppColors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );

          Widget minRow(int selMin, void Function(int) onSel) =>
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_minLabels.length, (idx) {
                    final sel = selMin == idx;
                    return GestureDetector(
                      onTap: () => setBS(() => onSel(idx)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 110),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : AppColors.surfaceAlt,
                          borderRadius: AppColors.r10,
                          border: Border.all(
                            color: sel ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        child: Text(
                          ':${_minLabels[idx]}',
                          style: TextStyle(
                            color: sel ? Colors.white : AppColors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );

          Widget ampmRow(bool isPM, void Function(bool) onSel) => Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: AppColors.r10,
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final pm in [false, true])
                      GestureDetector(
                        onTap: () => setBS(() => onSel(pm)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 110),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: isPM == pm
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: AppColors.r10,
                          ),
                          child: Text(
                            pm ? 'PM' : 'AM',
                            style: TextStyle(
                              color:
                                  isPM == pm ? Colors.white : AppColors.inkMid,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.92,
            minChildSize: 0.6,
            maxChildSize: 0.96,
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
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Slot ${i + 1} — Office Hours',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.ink,
                  ),
                ),
                sectionLabel('DAYS'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _days.map((d) {
                    final sel = selDays.contains(d);
                    return GestureDetector(
                      onTap: () => setBS(() {
                        sel ? selDays.remove(d) : selDays.add(d);
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 110),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : AppColors.surfaceAlt,
                          borderRadius: AppColors.r10,
                          border: Border.all(
                            color: sel ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        child: Text(
                          d,
                          style: TextStyle(
                            color: sel ? Colors.white : AppColors.inkMid,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                sectionLabel('START — HOUR'),
                hourRow(startH, (h) => startH = h),
                sectionLabel('START — MINUTES'),
                minRow(startM, (m) => startM = m),
                sectionLabel('START — PERIOD'),
                ampmRow(startPM, (pm) => startPM = pm),
                sectionLabel('END — HOUR'),
                hourRow(endH, (h) => endH = h),
                sectionLabel('END — MINUTES'),
                minRow(endM, (m) => endM = m),
                sectionLabel('END — PERIOD'),
                ampmRow(endPM, (pm) => endPM = pm),
                const SizedBox(height: 24),
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: AppColors.r20,
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      selDays.isEmpty
                          ? '${_format(startH, startM, startPM)} → ${_format(endH, endM, endPM)}'
                          : '${selDays.join(", ")}  ·  ${_format(startH, startM, startPM)} → ${_format(endH, endM, endPM)}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppColors.r12,
                      ),
                    ),
                    onPressed: () {
                      _setSlot(
                        i,
                        days: selDays,
                        start: _format(startH, startM, startPM),
                        end: _format(endH, endM, endPM),
                      );
                      Navigator.pop(bsCtx);
                    },
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                color: AppColors.primary,
                size: 15,
              ),
              const SizedBox(width: 6),
              const Text(
                'Office Hours',
                style: TextStyle(
                  color: AppColors.inkLight,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _addSlot,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: AppColors.r20,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Add slot',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_slots.isEmpty)
            GestureDetector(
              onTap: _addSlot,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: AppColors.r12,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      color: AppColors.inkLight,
                      size: 24,
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Tap to add office hours',
                      style: TextStyle(
                        color: AppColors.inkLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_slots.length, (i) {
              final slot = _slots[i];
              final days = List<String>.from(slot['days'] as List);
              final start = slot['start'] as String? ?? '';
              final end = slot['end'] as String? ?? '';
              final hasTime = start.isNotEmpty && end.isNotEmpty;
              final hasDays = days.isNotEmpty;

              return GestureDetector(
                onTap: () => _showSlotSheet(context, i),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppColors.r12,
                    border: Border.all(
                      color: hasTime && hasDays
                          ? AppColors.primary.withOpacity(0.25)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: AppColors.r10,
                        ),
                        child: const Icon(
                          Icons.access_time_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasDays ? days.join(', ') : 'No days selected',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: hasDays
                                    ? AppColors.ink
                                    : AppColors.inkLight,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hasTime ? '$start  →  $end' : 'Tap to set time',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: hasTime
                                    ? AppColors.inkMid
                                    : AppColors.inkLight,
                                fontStyle: hasTime
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.edit_outlined,
                            size: 15,
                            color: AppColors.inkLight,
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _removeSlot(i),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: AppColors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Shared widgets ────────────────────────────────────────────────────────────
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
          Icon(icon, color: AppColors.primary, size: 17),
          const SizedBox(width: 7),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
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
        color: AppColors.primary,
        borderRadius: AppColors.r20,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppColors.r20,
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
        style: const TextStyle(color: AppColors.ink, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.inkMid, fontSize: 12),
          prefixIcon: Icon(icon, color: AppColors.primary, size: 15),
          filled: true,
          fillColor: AppColors.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: AppColors.r12,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppColors.r12,
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppColors.r12,
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                  color: AppColors.primarySoft,
                  borderRadius: AppColors.r20,
                ),
                child: Icon(icon, color: AppColors.primary, size: 34),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.inkLight,
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

// ─── Replace Roster Confirmation Dialog ──────────────────────────────────────

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
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: isSameFile
                    ? const Color(0xFFFFF8ED)
                    : const Color(0xFFFFF0F0),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
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
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSameFile
                        ? 'This file was already imported'
                        : 'A different roster will replace the current one',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF888888),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // ── Body ──────────────────────────────────────────────────────
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
                    child: Row(
                      children: [
                        const Icon(
                          Icons.insert_drive_file_rounded,
                          color: Color(0xFF7C5CBF),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            filename,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2D2640),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isSameFile
                        ? 'This appears to be the same file you imported before. '
                            'Re-importing will refresh the list with $existingCount '
                            'student${existingCount == 1 ? "" : "s"}.'
                        : 'This section currently has $existingCount '
                            'student${existingCount == 1 ? "" : "s"}. '
                            'Uploading a new file will permanently replace '
                            'the existing roster. This cannot be undone.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B6480),
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
            // ── Actions ───────────────────────────────────────────────────
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
                          side: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
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
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
