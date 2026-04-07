// lib/screens/workspace_detail.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../app/state/workspaces_vm.dart';
import '../models/workspace_model.dart';
import '../config/app_colors.dart';
import 'widgets/notification_bell.dart';
import 'workspace_sections.dart';
import 'workspace_ask.dart';

const _fieldLabels = {
  'course_title': 'Course Title',
  'course_code': 'Course Code',
  'semester': 'Semester',
};
const _fieldIcons = {
  'course_title': Icons.book_rounded,
  'course_code': Icons.tag_rounded,
  'semester': Icons.calendar_today_rounded,
};

// ─── Main Page ────────────────────────────────────────────────────────────────
class WorkspaceDetailPage extends StatefulWidget {
  const WorkspaceDetailPage({super.key, required this.vm});
  final WorkspacesViewModel vm;

  @override
  State<WorkspaceDetailPage> createState() => _WorkspaceDetailPageState();
}

class _WorkspaceDetailPageState extends State<WorkspaceDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  Timer? _pollingTimer;

  final Map<String, TextEditingController> _fieldCtrl = {};

  final _askCtrl = TextEditingController();
  final _askScroll = ScrollController();
  bool _asking = false;

  static const _editableKeys = ['course_title', 'course_code', 'semester'];

  /// Chat history lives in the VM keyed by workspace id so it survives
  /// navigation. Falls back to an empty list (auto-created on first write).
  List<ChatMsg> get _chat =>
      widget.vm.chatHistory[widget.vm.current?.id ?? 0] ??= [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _syncControllersFromWorkspace();

    widget.vm.addListener(_onVmUpdate);

    _startSmartPolling();
  }

  void _onVmUpdate() {
    final ws = widget.vm.current;
    if (ws != null && _needsPolling(ws)) {
      // If it's a draft and we aren't already polling, start the engine!
      if (_pollingTimer == null || !_pollingTimer!.isActive) {
        debugPrint("🔄 Detected Draft Workspace. Starting Polling Timer...");
        _startSmartPolling();
      }
    }
  }

  void _startSmartPolling() {
    _pollingTimer?.cancel(); 

    final ws = widget.vm.current;
    if (ws != null && _needsPolling(ws)) {
      _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        debugPrint("⏳ Polling backend for AI updates..."); // Watch this in your console!
        
        await widget.vm.refreshCurrentQuietly(); 
        
        final updatedWs = widget.vm.current;
        if (updatedWs != null && !_needsPolling(updatedWs)) {
          debugPrint("✅ AI Finished! Killing Timer.");
          timer.cancel(); 
          if (mounted) {
            setState(() {
              _syncControllersFromWorkspace();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✨ AI Extraction Complete!'), 
                backgroundColor: AppColors.accent
              ),
            );
          }
        }
      });
    }
  }

  @override
  void didUpdateWidget(WorkspaceDetailPage old) {
    super.didUpdateWidget(old);
    if (old.vm.current != widget.vm.current) {
      _syncControllersFromWorkspace();
      _startSmartPolling();
    }
  }

  void _syncControllersFromWorkspace() {
    final ws = widget.vm.current;
    if (ws == null) return;
    for (final key in _editableKeys) {
      String value = ws.fields[key] ?? '';
      if (key == 'workspace_name' && value.isEmpty) {
        value = ws.fields['workspace_title'] ?? '';
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
    widget.vm.removeListener(_onVmUpdate);

    _pollingTimer?.cancel();
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

  bool _needsPolling(Workspace ws) {
    if (!ws.isReady) return true;
    
    // Grab all the fields and force them to lowercase so we don't get tricked by capitalization
    final topTitle = ws.title.toLowerCase();
    final titleField = (ws.fields['course_title'] ?? '').toLowerCase();
    final codeField = (ws.fields['course_code'] ?? '').toLowerCase();

    // If ANY of these have our default placeholders, the AI is still processing!
    if (topTitle.contains('untitled') || titleField.contains('untitled')) return true;
    if (codeField == 'tbd' || codeField.isEmpty) return true;
    
    return false;
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
            backgroundColor: AppColors.bg,
            body: Center(child: Text('No workspace selected.')),
          );
        }

        if (!widget.vm.loadingDetail) {
          _syncControllersFromWorkspace();
        }

        final ready = !_needsPolling(ws);
        final missing =
            widget.vm.loadingDetail ? <String>[] : _missingFields(ws);

        return Scaffold(
          backgroundColor: AppColors.bg,

          floatingActionButton: ready ? FloatingActionButton.extended(
            onPressed: () {
              Navigator.pushNamed(context, '/generate');
            },
            icon: const Icon(Icons.auto_awesome_rounded), 
            label: const Text('Generate', style: TextStyle(fontWeight: FontWeight.w700)),
            backgroundColor: AppColors.primary, 
            foregroundColor: Colors.white,
            elevation: 4,
          ) : null, // Only show the button if the workspace is "Ready"
          
          body: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: NestedScrollView(
              headerSliverBuilder: (_, __) => [_buildHeader(ws, ready)],
              body: Column(
                children: [
                  // ── Tab bar ──────────────────────────────────────────
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
                          Tab(
                              icon: Icon(Icons.upload_file_rounded, size: 16),
                              text: 'Attendance'), 
                        ],
                      ),
                    ),
                  ),
                  if (!ready && missing.isNotEmpty && !widget.vm.loadingDetail)
                    _MissingBanner(fields: missing),
                  // ── Tab content ──────────────────────────────────────
                  Expanded(
                    child: widget.vm.loadingDetail
                        ? const _DetailSkeleton()
                        : (!ready) // 👉 THE FIX: Intercept the UI if AI is processing!
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const CircularProgressIndicator(color: AppColors.primary),
                                    const SizedBox(height: 20),
                                    Text(
                                      '✨ AI is extracting syllabus data...',
                                      style: TextStyle(
                                        color: AppColors.primary.withOpacity(0.8),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'This usually takes about 5-10 seconds.',
                                      style: TextStyle(color: AppColors.inkLight, fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            : widget.vm.loading
                                ? const Center(
                                    child: CircularProgressIndicator(color: AppColors.primary),
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
                                  SectionsTab(
                                    ws: ws,
                                    vm: widget.vm,
                                    onError: _showError,
                                    onNavigateToStudents: () =>
                                        _tabs.animateTo(2),
                                  ),
                                  StudentsTab(
                                    ws: ws,
                                    vm: widget.vm,
                                    onError: _showError,
                                  ),
                                  AskTab(
                                    chat: _chat,
                                    ctrl: _askCtrl,
                                    scrollCtrl: _askScroll,
                                    asking: _asking,
                                    onAsk: _onAsk,
                                  ),
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.construction_rounded, size: 48, color: AppColors.inkLight.withOpacity(0.5)),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Attendance Module Coming Soon',
                                          style: TextStyle(
                                            color: AppColors.inkLight,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
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
    final code = ws.fields['workspace_code'] ?? '';
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
                        // 👉 THE FIX: Show shimmer effect instead of "Untitled Workspace"
                        child: (!ready)
                            ? _ShimmerBar(
                                width: 200,
                                height: 24,
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

                  if(!ready)
                    const SizedBox(height: 24)
                  else
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
    final historySnapshot = _chat.map((m) => m.toHistoryEntry()).toList();
    setState(() {
      _chat.add(ChatMsg(text: q, isUser: true));
      _asking = true;
    });
    _askCtrl.clear();
    _scrollChat();
    final answer = await widget.vm.askInWorkspace(q, history: historySnapshot);
    setState(() {
      _chat.add(ChatMsg(
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
            title: 'workspace Details', icon: Icons.info_outline_rounded),
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
      Widget inputWidget;

      // 👉 THE FIX: If the field is Semester, show the strict Dropdown!
      if (fieldKey == 'semester') {
        const semesterOptions = ['Spring', 'Fall', 'Summer 1', 'Summer 2', 'TBD'];
        // Fallback to TBD if the current value isn't in our strict list
        String currentDropVal = semesterOptions.contains(liveValue) ? liveValue : 'TBD';
        
        // Quietly sync the controller to match the dropdown visual
        if (liveValue != currentDropVal) {
          ctrl(fieldKey, value).text = currentDropVal;
        }

        inputWidget = DropdownButtonFormField<String>(
          value: currentDropVal,
          items: semesterOptions.map((String option) {
            return DropdownMenuItem<String>(
              value: option,
              child: Text(option),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              ctrl(fieldKey, value).text = newValue; // Updates your saving logic!
            }
          },
          icon: const SizedBox.shrink(), // Hides default arrow to favor your checkmark
          dropdownColor: AppColors.surface, // Matches your theme
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
            filled: true,
            fillColor: hasError ? AppColors.warnSoft : AppColors.primarySoft,
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
        );
      } else {
        // Render the standard text field for everything else
        inputWidget = TextField(
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
            fillColor: hasError ? AppColors.warnSoft : AppColors.primarySoft,
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
        );
      }

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
            inputWidget, // Uses the Dropdown OR TextField dynamically
          ],
        ),
      );
    }

    // View Mode (When not editing)
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
    case 'workspace_name':
      return 'e.g. Introduction to Computer Science';
    case 'workspace_code':
      return 'e.g. CS101';
    case 'semester':
      return 'e.g. Fall';
    default:
      return '';
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  
  final String title;
  final IconData icon;

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
        ],
      );
}

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

// ─── Shimmer Bar ──────────────────────────────────────────────────────────────
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
