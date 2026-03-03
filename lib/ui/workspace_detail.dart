// lib/ui/workspace_detail.dart
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  'office_hours_start': 'Office Hours Start',
  'office_hours_end': 'Office Hours End',
  'instructor_email': 'Instructor Email',
};
const _fieldIcons = {
  'course_name': Icons.book_rounded,
  'course_code': Icons.tag_rounded,
  'semester': Icons.calendar_today_rounded,
  'office_hours_start': Icons.access_time_rounded,
  'office_hours_end': Icons.access_time_filled_rounded,
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

  // FIX: controllers live here (not in _InfoTabState) so they survive tab switches.
  // But they MUST be refreshed when the workspace object changes after a save.
  final Map<String, TextEditingController> _fieldCtrl = {};

  final _askCtrl = TextEditingController();
  final _askScroll = ScrollController();
  final List<_ChatMsg> _chat = [];
  bool _asking = false;

  static const _editableKeys = [
    'course_name',
    'course_code',
    'semester',
    'office_hours_start',
    'office_hours_end',
    'instructor_email',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    // Seed controllers from the current workspace on first load
    _syncControllersFromWorkspace();
  }

  @override
  void didUpdateWidget(WorkspaceDetailPage old) {
    super.didUpdateWidget(old);
    // FIX: workspace object is replaced after every save/reload.
    // putIfAbsent never updates existing controllers — we must push
    // new values in explicitly so the UI reflects what was actually saved.
    if (old.vm.current != widget.vm.current) {
      _syncControllersFromWorkspace();
    }
  }

  /// Push current workspace field values into all controllers.
  /// Called on init and whenever the workspace object is replaced.
  void _syncControllersFromWorkspace() {
    final ws = widget.vm.current;
    if (ws == null) return;

    // Sync plain fields
    for (final key in _editableKeys) {
      if (key == 'office_hours_start' || key == 'office_hours_end') continue;
      final value = ws.fields[key] ?? '';
      final existing = _fieldCtrl[key];
      if (existing == null) {
        _fieldCtrl[key] = TextEditingController(text: value);
      } else if (existing.text != value) {
        // FIX: force-update — putIfAbsent would silently skip this
        existing.text = value;
      }
    }

    // Sync office hours — backend stores as combined 'office_hours',
    // UI splits into start/end
    final combined = ws.fields['office_hours'] ?? '';
    final directStart = ws.fields['office_hours_start'] ?? '';
    final directEnd = ws.fields['office_hours_end'] ?? '';

    String startVal = directStart;
    String endVal = directEnd;
    if (startVal.isEmpty && combined.isNotEmpty) {
      final parts = combined.split(
        RegExp(r'\s*[-–to]+\s*', caseSensitive: false),
      );
      if (parts.length >= 2) {
        startVal = parts[0].trim();
        endVal = parts[1].trim();
      } else {
        startVal = combined.trim();
      }
    }

    final existingStart = _fieldCtrl['office_hours_start'];
    if (existingStart == null) {
      _fieldCtrl['office_hours_start'] = TextEditingController(text: startVal);
    } else if (existingStart.text != startVal) {
      existingStart.text = startVal;
    }

    final existingEnd = _fieldCtrl['office_hours_end'];
    if (existingEnd == null) {
      _fieldCtrl['office_hours_end'] = TextEditingController(text: endVal);
    } else if (existingEnd.text != endVal) {
      existingEnd.text = endVal;
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

  // FIX: _ctrl now always syncs the value if the controller already exists
  // (putIfAbsent alone only seeds on first creation — subsequent calls with
  // a different value are silently ignored, causing stale data after reload).
  TextEditingController _ctrl(String key, String value) {
    final existing = _fieldCtrl[key];
    if (existing == null) {
      final c = TextEditingController(text: value);
      _fieldCtrl[key] = c;
      return c;
    }
    // Only overwrite if the parent is providing a fresh non-empty value
    // AND the user isn't currently editing (controller text differs from value
    // only when the workspace was just reloaded from backend)
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
            backgroundColor: _DS.bg,
            body: Center(child: Text('No workspace selected.')),
          );
        }
        final ready = _isReady(ws);
        final missing = _missingFields(ws);

        return Scaffold(
          backgroundColor: _DS.bg,
          body: NestedScrollView(
            headerSliverBuilder: (_, __) => [_buildHeader(ws, ready)],
            body: Column(
              children: [
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
      // FIX: sync controllers from the freshly-saved workspace so they
      // reflect the canonical server values (e.g. trimmed whitespace)
      _syncControllersFromWorkspace();
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
      backgroundColor: _DS.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: _DS.r12),
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
  switch (key) {
    case 'instructor_email':
      final emailRe = RegExp(
        r'^[\w.+-]+@[\w-]+\.[a-z]{2,}$',
        caseSensitive: false,
      );
      if (!emailRe.hasMatch(v)) return 'Enter a valid email address';
      break;
    case 'office_hours_start':
    case 'office_hours_end':
      final timeRe = RegExp(r'^\d{1,2}:\d{2}$');
      if (!timeRe.hasMatch(v)) return 'Use format HH:MM (e.g. 09:00)';
      break;
  }
  return null;
}

const _numericKeys = {'allow_validation', 'capacity', 'max_students'};
const _officeHoursPair = {'office_hours_start', 'office_hours_end'};

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
    final startText = widget.ctrl('office_hours_start', '').text.trim();
    final endText = widget.ctrl('office_hours_end', '').text.trim();
    if (_errors['office_hours_start'] == null &&
        _errors['office_hours_end'] == null &&
        startText.isNotEmpty &&
        endText.isNotEmpty) {
      final startMins = _timeToMinutes(startText);
      final endMins = _timeToMinutes(endText);
      if (startMins != null && endMins != null) {
        if (startMins == endMins) {
          _errors['office_hours_end'] = 'End time must differ from start time';
        } else if (endMins < startMins) {
          _errors['office_hours_end'] = 'End time must be after start time';
        }
      }
    }
    return _errors.isEmpty;
  }

  int? _timeToMinutes(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
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
    if (_officeHoursPair.contains(key)) return TextInputType.datetime;
    return TextInputType.text;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasEdits = _editing.isNotEmpty;

    final List<_FieldGroup> groups = [];
    bool ohStartAdded = false;
    for (final key in widget.editableKeys) {
      if (key == 'office_hours_start') {
        ohStartAdded = true;
        continue;
      }
      if (key == 'office_hours_end') {
        groups.add(_FieldGroup.pair('office_hours_start', 'office_hours_end'));
        continue;
      }
      groups.add(_FieldGroup.single(key));
    }
    if (ohStartAdded && !groups.any((g) => g.isPair)) {
      groups.add(_FieldGroup.single('office_hours_start'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(
          title: 'Course Details',
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap any field to edit. All fields are required.',
          style: TextStyle(fontSize: 12, color: _DS.inkMid),
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
              ...groups.asMap().entries.map((entry) {
                final idx = entry.key;
                final group = entry.value;
                final isLast = idx == groups.length - 1;
                return Column(
                  children: [
                    if (group.isPair)
                      _OfficeHoursPairRow(
                        wsFields: widget.ws.fields,
                        ctrl: widget.ctrl,
                        editing: _editing,
                        errors: _errors,
                        triedSave: _triedSave,
                        onEditStart: (k) => setState(() {
                          _editing.add(k);
                          _dirty = true;
                        }),
                        onEditDone: (k) => setState(() {
                          _editing.remove(k);
                          if (_triedSave) {
                            _errors[k] = _validateField(
                              k,
                              widget.ctrl(k, '').text,
                            );
                          }
                        }),
                      )
                    else
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
                        color: _DS.border,
                      ),
                  ],
                );
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
        if (_triedSave && _errors.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _DS.warnSoft,
              borderRadius: _DS.r12,
              border: Border.all(color: _DS.warn.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: _DS.warn,
                      size: 15,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Please fix the following:',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _DS.warn,
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
                      style: const TextStyle(fontSize: 12, color: _DS.warn),
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
  bool get isPair => secondKey != null;
  const _FieldGroup.single(this.key) : secondKey = null;
  const _FieldGroup.pair(this.key, this.secondKey);
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
                color: hasError ? _DS.warn : _DS.primary,
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
                color: _DS.ink,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                prefixIcon: Icon(
                  icon,
                  color: hasError ? _DS.warn : _DS.primary,
                  size: 17,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.check_circle_rounded,
                    color: hasError ? _DS.warn : _DS.accent,
                  ),
                  onPressed: onDone,
                ),
                hintText: _hintFor(fieldKey),
                hintStyle: const TextStyle(color: _DS.inkLight, fontSize: 13),
                filled: true,
                fillColor: hasError ? _DS.warnSoft : _DS.primarySoft,
                border: OutlineInputBorder(
                  borderRadius: _DS.r12,
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: _DS.r12,
                  borderSide: BorderSide(
                    color: hasError ? _DS.warn : _DS.primary,
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
        hoverColor: _DS.primarySoft.withOpacity(0.5),
        splashColor: _DS.primary.withOpacity(0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: hasError
                      ? _DS.warnSoft
                      : (isEmpty ? _DS.warnSoft : _DS.primarySoft),
                  borderRadius: _DS.r10,
                ),
                child: Icon(
                  icon,
                  color: hasError
                      ? _DS.warn
                      : (isEmpty ? _DS.warn : _DS.primary),
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
                        color: _DS.inkLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      liveValue.isEmpty ? 'Tap to add…' : liveValue,
                      style: TextStyle(
                        color: liveValue.isEmpty ? _DS.inkLight : _DS.ink,
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
                          color: _DS.warn,
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
                    ? _DS.warn
                    : (isEmpty ? _DS.warn : _DS.inkLight),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Office hours pair row ──────────────────────────────────────────────────────
class _OfficeHoursPairRow extends StatelessWidget {
  const _OfficeHoursPairRow({
    required this.wsFields,
    required this.ctrl,
    required this.editing,
    required this.errors,
    required this.triedSave,
    required this.onEditStart,
    required this.onEditDone,
  });
  final Map<String, String> wsFields;
  final TextEditingController Function(String, String) ctrl;
  final Set<String> editing;
  final Map<String, String?> errors;
  final bool triedSave;
  final void Function(String) onEditStart;
  final void Function(String) onEditDone;

  @override
  Widget build(BuildContext context) {
    const startKey = 'office_hours_start';
    const endKey = 'office_hours_end';
    // FIX: read live value from controller, not wsFields
    // wsFields reflects the last-saved backend value, but the controller
    // has the most current user-entered or seeded value
    final startVal = ctrl(startKey, wsFields[startKey] ?? '').text;
    final endVal = ctrl(endKey, wsFields[endKey] ?? '').text;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.access_time_rounded, color: _DS.primary, size: 15),
              SizedBox(width: 6),
              Text(
                'Office Hours',
                style: TextStyle(
                  color: _DS.inkLight,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TimePickerField(
                  label: 'Start time',
                  fieldKey: startKey,
                  value: startVal,
                  ctrl: ctrl,
                  isEditing: editing.contains(startKey),
                  error: errors[startKey],
                  onTap: () => onEditStart(startKey),
                  onDone: () => onEditDone(startKey),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '—',
                  style: const TextStyle(
                    color: _DS.inkMid,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Expanded(
                child: _TimePickerField(
                  label: 'End time',
                  fieldKey: endKey,
                  value: endVal,
                  ctrl: ctrl,
                  isEditing: editing.contains(endKey),
                  error: errors[endKey],
                  onTap: () => onEditStart(endKey),
                  onDone: () => onEditDone(endKey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Time picker mini field ─────────────────────────────────────────────────────
class _TimePickerField extends StatefulWidget {
  const _TimePickerField({
    required this.label,
    required this.fieldKey,
    required this.value,
    required this.ctrl,
    required this.isEditing,
    required this.error,
    required this.onTap,
    required this.onDone,
  });
  final String label;
  final String fieldKey;
  final String value;
  final TextEditingController Function(String, String) ctrl;
  final bool isEditing;
  final String? error;
  final VoidCallback onTap;
  final VoidCallback onDone;

  @override
  State<_TimePickerField> createState() => _TimePickerFieldState();
}

class _TimePickerFieldState extends State<_TimePickerField> {
  late String _displayValue;

  @override
  void initState() {
    super.initState();
    _displayValue = widget.value;
  }

  @override
  void didUpdateWidget(_TimePickerField old) {
    super.didUpdateWidget(old);
    // FIX: always sync display value from the controller (not widget.value prop)
    // The controller is the source of truth after _syncControllersFromWorkspace
    final ctrlText = widget.ctrl(widget.fieldKey, widget.value).text;
    if (ctrlText != _displayValue) {
      _displayValue = ctrlText;
    }
  }

  Future<void> _pickTime() async {
    TimeOfDay initial = TimeOfDay.now();
    final parts = _displayValue.split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) initial = TimeOfDay(hour: h, minute: m);
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.input,
    );

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      widget.ctrl(widget.fieldKey, widget.value).text = formatted;
      setState(() => _displayValue = formatted);
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;
    final isEmpty = _displayValue.trim().isEmpty;

    return GestureDetector(
      onTap: () {
        widget.onTap();
        _pickTime();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: hasError
              ? _DS.warnSoft
              : (isEmpty ? _DS.warnSoft : _DS.primarySoft),
          borderRadius: _DS.r12,
          border: Border.all(
            color: hasError
                ? _DS.warn.withOpacity(0.5)
                : (isEmpty
                      ? _DS.warn.withOpacity(0.3)
                      : _DS.primary.withOpacity(0.25)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label,
              style: TextStyle(
                color: hasError ? _DS.warn : _DS.inkMid,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: hasError
                      ? _DS.warn
                      : (isEmpty ? _DS.warn : _DS.primary),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    isEmpty ? 'Tap to set…' : _displayValue,
                    style: TextStyle(
                      color: isEmpty
                          ? _DS.inkLight
                          : (hasError ? _DS.warn : _DS.ink),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 13,
                  color: hasError ? _DS.warn : _DS.inkLight,
                ),
              ],
            ),
            if (hasError) ...[
              const SizedBox(height: 3),
              Text(
                widget.error!,
                style: const TextStyle(
                  color: _DS.warn,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
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

  bool _showForm = false;
  Section? _editingSection;
  final _draft = SectionDraft();
  final _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  // FIX: no default values — start empty so user must explicitly set a time.
  // Previously defaulting to '09:00'/'10:15' meant if the user didn't change
  // them the section always saved with 09:00 regardless of what they entered.
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  bool _saving = false;

  void _startEdit(Section s) {
    _editingSection = s;
    _nameCtrl.text = s.name;
    _locationCtrl.text = s.location;
    // FIX: only assign non-empty values. If the stored endTime is the
    // timezone string "UTC" (legacy bad data), treat it as empty.
    _startCtrl.text = s.schedule.startTime;
    final rawEnd = s.schedule.endTime.trim();
    _endCtrl.text =
        (rawEnd == s.schedule.timezone || rawEnd.toUpperCase() == 'UTC')
        ? ''
        : rawEnd;
    _draft.days = List<String>.from(s.schedule.days);
    _draft.timezone = s.schedule.timezone;
    _draft.reminderMinutes = s.schedule.reminderMinutes;
    setState(() => _showForm = true);
  }

  void _cancelForm() {
    _editingSection = null;
    _nameCtrl.text = '';
    _locationCtrl.text = '';
    // FIX: reset to empty, not '09:00' — avoids phantom default time
    _startCtrl.text = '';
    _endCtrl.text = '';
    _draft.days = const [];
    setState(() => _showForm = false);
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _locationCtrl, _startCtrl, _endCtrl]) {
      c.dispose();
    }
    super.dispose();
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_showForm)
                _PillButton(
                  label: '+ Add Section',
                  onTap: () => setState(() => _showForm = true),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_showForm) ...[_buildForm(), const SizedBox(height: 14)],
        if (ws.sections.isEmpty && !_showForm)
          const _EmptyState(
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
                child: _SectionTimePicker(
                  label: 'Start time',
                  ctrl: _startCtrl,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SectionTimePicker(label: 'End time', ctrl: _endCtrl),
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
                  _draft.days = sel
                      ? _draft.days.where((x) => x != d).toList()
                      : [..._draft.days, d];
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
      ..startTime = _startCtrl.text.trim()
      ..endTime = _endCtrl.text.trim()
      ..days = _draft.days
          .map((d) => d.trim())
          .where((d) => d.isNotEmpty)
          .toList();

    if (_draft.name.isEmpty) {
      widget.onError('Section name is required.');
      return;
    }
    if (_draft.days.isEmpty) {
      widget.onError('Select at least one day.');
      return;
    }
    if (_draft.startTime.isEmpty) {
      widget.onError('Start time is required for notifications to work.');
      return;
    }

    final startMins = _timeToMinutes(_draft.startTime);
    final endMins = _timeToMinutes(_draft.endTime);
    if (_draft.endTime.isNotEmpty && startMins != null && endMins != null) {
      if (startMins == endMins) {
        widget.onError('Start and end time cannot be the same.');
        return;
      }
      if (endMins < startMins) {
        widget.onError('End time must be after start time.');
        return;
      }
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

  int? _timeToMinutes(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
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
    // FIX: guard end time — don't show timezone string as time
    final rawEnd = sch.endTime.trim();
    final endDisplay =
        (rawEnd.isEmpty ||
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
                                              : 'Import student list (.csv / .xlsx)',
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
                                      'Upload a CSV/XLSX with name, email, student_no columns.',
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
                              const SizedBox(height: 6),
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
        children: const [
          Icon(Icons.auto_awesome_rounded, size: 13, color: _DS.primary),
          SizedBox(width: 5),
          Text(
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

// ── Section time picker ────────────────────────────────────────────────────────
class _SectionTimePicker extends StatefulWidget {
  const _SectionTimePicker({required this.label, required this.ctrl});
  final String label;
  final TextEditingController ctrl;

  @override
  State<_SectionTimePicker> createState() => _SectionTimePickerState();
}

class _SectionTimePickerState extends State<_SectionTimePicker> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(_onCtrlChanged);
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_onCtrlChanged);
    super.dispose();
  }

  void _onCtrlChanged() => setState(() {});

  Future<void> _pick() async {
    final current = widget.ctrl.text.trim();
    TimeOfDay initial = TimeOfDay.now();
    if (current.isNotEmpty) {
      final parts = current.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) initial = TimeOfDay(hour: h, minute: m);
      }
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked != null) {
      widget.ctrl.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.ctrl.text.trim();
    final isEmpty = text.isEmpty;
    return GestureDetector(
      onTap: _pick,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: isEmpty ? _DS.warnSoft : _DS.primarySoft,
          borderRadius: _DS.r12,
          border: Border.all(
            color: isEmpty
                ? _DS.warn.withOpacity(0.3)
                : _DS.primary.withOpacity(0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label,
              style: TextStyle(
                color: isEmpty ? _DS.warn : _DS.inkMid,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: isEmpty ? _DS.warn : _DS.primary,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    isEmpty ? 'Tap to set…' : text,
                    style: TextStyle(
                      color: isEmpty ? _DS.inkLight : _DS.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 13,
                  color: isEmpty ? _DS.warn : _DS.inkLight,
                ),
              ],
            ),
          ],
        ),
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
