// lib/screens/workspace/workspace_detail.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'dart:convert';

import '../../state/workspaces_vm.dart';
import '../../models/workspace_model.dart';
import '../../app_styles.dart';
import '../../widgets/notification_bell.dart';
import '../../models/config_model.dart';
import '../../models/question_model.dart';

import 'workspace_sections.dart';
import 'workspace_ask.dart';
import 'review_screen.dart'; 

const _fieldLabels = {
  'course_title': 'Course Title',
  'course_code': 'Course Code',
  'semester': 'Semester',
  'start_date': 'Semester Start Date',
  'end_date': 'Semester End Date',
};
const _fieldIcons = {
  'course_title': Icons.book_rounded,
  'course_code': Icons.tag_rounded,
  'semester': Icons.calendar_today_rounded,
  'start_date': Icons.event_available_rounded,
  'end_date': Icons.event_busy_rounded,
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
  int _currentTabIndex = 0;

  Timer? _pollingTimer;

  final Map<String, TextEditingController> _fieldCtrl = {};

  final _askCtrl = TextEditingController();
  final _askScroll = ScrollController();
  bool _asking = false;

  // 👉 The Global Edit Mode Tracker
  bool _isEditingDetails = false;

  static const _editableKeys = ['course_title', 'course_code', 'semester', 'start_date', 'end_date'];

  bool _isGenerating = false;
  final Map<String, QuestionTypeConfig> _configs = {
    'MCQ': QuestionTypeConfig(name: 'Multiple Choice', isSelected: true, count: 10),
    'Essay': QuestionTypeConfig(name: 'Essay', isSelected: false, count: 2),
    'True/False': QuestionTypeConfig(name: 'True/False', isSelected: false, count: 5),
  };

  List<ChatMsg> get _chat =>
      widget.vm.chatHistory[widget.vm.current?.id ?? 0] ??= [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);

    _tabs.addListener(() {
      if (_tabs.index != _currentTabIndex) {
        setState(() {
          _currentTabIndex = _tabs.index;
          // Turn off edit mode if they navigate away from the info tab
          if (_currentTabIndex != 0) _isEditingDetails = false; 
        });
      }
    });
    
    _syncControllersFromWorkspace();
    widget.vm.addListener(_onVmUpdate);
    _startSmartPolling();
  }

  void _onVmUpdate() {
    final ws = widget.vm.current;
    if (ws != null && _needsPolling(ws)) {
      if (_pollingTimer == null || !_pollingTimer!.isActive) {
        _startSmartPolling();
      }
    }
  }

  void _startSmartPolling() {
    _pollingTimer?.cancel(); 

    final ws = widget.vm.current;
    if (ws != null && _needsPolling(ws)) {
      _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        await widget.vm.refreshCurrentQuietly(); 
        
        final updatedWs = widget.vm.current;
        if (updatedWs != null && !_needsPolling(updatedWs)) {
          timer.cancel(); 
          if (mounted) {
            setState(() {
              _syncControllersFromWorkspace();
            });
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
    for (final c in _fieldCtrl.values) {
      c.dispose();
    }
    for (var config in _configs.values) {
      config.topicController.dispose();
    }
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
    final topTitle = ws.title.toLowerCase();
    final titleField = (ws.fields['course_title'] ?? '').toLowerCase();
    final codeField = (ws.fields['course_code'] ?? '').toLowerCase();

    if (topTitle.contains('untitled') || titleField.contains('untitled')) return true;
    if (codeField == 'tbd' || codeField.isEmpty) return true;
    return false;
  }

  List<String> _missingFields(Workspace ws) =>
      _editableKeys.where((k) => (ws.fields[k] ?? '').trim().isEmpty).toList();

  void _generateQuiz() async {
    final selectedIds = widget.vm.selectedMaterialIdsForQuiz.toList();
    if (selectedIds.isEmpty || widget.vm.current == null) return;

    setState(() => _isGenerating = true);

    try {
      var activeConfigs = _configs.values.where((c) => c.isSelected && c.count > 0).toList();

      var questions = await widget.vm.api.generateQuiz(
        widget.vm.current!.id,
        selectedIds,
        activeConfigs,
      );

      if (mounted && questions.isNotEmpty) {
        widget.vm.clearMaterialSelection(); 
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => ReviewScreen(questions: questions.cast<QuizQuestion>()),
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("AI returned no questions.")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Generation Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.tune, color: AppStyles.primaryPurple), 
                  SizedBox(width: 10), 
                  Text("Configure Options")
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _configs.values.map((config) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: config.isSelected ? 2 : 0,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: config.isSelected ? AppStyles.primaryPurple : Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8)
                        ),
                        child: Column(
                          children: [
                            CheckboxListTile(
                              title: Text(config.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              value: config.isSelected,
                              activeColor: AppStyles.primaryPurple,
                              onChanged: (val) {
                                setDialogState(() { config.isSelected = val ?? false; });
                                setState(() {}); 
                              }
                            ),
                            if (config.isSelected)
                              Padding(
                                padding: const EdgeInsets.only(left: 15, right: 15, bottom: 15),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            initialValue: config.count.toString(),
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(labelText: "Count", isDense: true, border: OutlineInputBorder()),
                                            onChanged: (val) => config.count = int.tryParse(val) ?? 0,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: config.difficulty,
                                            decoration: const InputDecoration(labelText: "Difficulty", isDense: true, border: OutlineInputBorder()),
                                            items: ['Easy', 'Medium', 'Hard'].map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                                            onChanged: (val) {
                                              setDialogState(() { config.difficulty = val!; });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: config.topicController,
                                      decoration: const InputDecoration(
                                        labelText: "Optional Info / Focus",
                                        hintText: "e.g., Focus on Chapter 2",
                                        isDense: true,
                                        border: OutlineInputBorder()
                                      ),
                                    )
                                  ],
                                ),
                              )
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppStyles.primaryPurple, foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _generateQuiz(); 
                  },
                  child: const Text("Confirm & Generate"),
                )
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (_, __) {
        final ws = widget.vm.current;
        if (ws == null) {
          return const Scaffold(
            backgroundColor: AppStyles.lightGray,
            body: Center(child: Text('No workspace selected.')),
          );
        }

        if (!widget.vm.loadingDetail) {
          _syncControllersFromWorkspace();
        }

        final ready = !_needsPolling(ws);
        final missing = widget.vm.loadingDetail ? <String>[] : _missingFields(ws);

        return Scaffold(
          backgroundColor: AppStyles.lightGray,
          floatingActionButton: (ready && _currentTabIndex == 3) ? FloatingActionButton.extended(
            onPressed: widget.vm.selectedMaterialIdsForQuiz.isEmpty || _isGenerating 
                ? null 
                : _showSettings,
            icon: _isGenerating 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.auto_awesome_rounded), 
            label: Text(
              _isGenerating ? 'Thinking...' : 'Generate (${widget.vm.selectedMaterialIdsForQuiz.length})', 
              style: const TextStyle(fontWeight: FontWeight.w700)
            ),
            backgroundColor: widget.vm.selectedMaterialIdsForQuiz.isEmpty ? Colors.grey : AppStyles.primaryPurple, 
            foregroundColor: Colors.white,
            elevation: widget.vm.selectedMaterialIdsForQuiz.isEmpty ? 0 : 4,
          ) : null,
          
          body: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: NestedScrollView(
              headerSliverBuilder: (_, __) => [_buildHeader(ws, ready)],
              body: Column(
                children: [
                  Container(
                    color: AppStyles.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppStyles.lightGray,
                        borderRadius: AppStyles.borderRadiusXL,
                      ),
                      padding: const EdgeInsets.all(3),
                      child: TabBar(
                        controller: _tabs,
                        indicator: BoxDecoration(
                          color: AppStyles.primaryPurple,
                          borderRadius: AppStyles.borderRadiusL,
                          boxShadow: [
                            BoxShadow(
                              color: AppStyles.primaryPurple.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: AppStyles.darkGray,
                        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                        tabs: const [
                          Tab(icon: Icon(Icons.info_outline_rounded, size: 16), text: 'Info'),
                          Tab(icon: Icon(Icons.groups_2_rounded, size: 16), text: 'Sections'),
                          Tab(icon: Icon(Icons.people_alt_rounded, size: 16), text: 'Students'),
                          Tab(icon: Icon(Icons.folder_zip_rounded, size: 16), text: 'Materials'),
                          Tab(icon: Icon(Icons.auto_awesome_rounded, size: 16), text: 'Ask AI'),
                          Tab(icon: Icon(Icons.fact_check_outlined, size: 16), text: 'Attendance'),
                        ],
                      ),
                    ),
                  ),
                  if (!ready && missing.isNotEmpty && !widget.vm.loadingDetail)
                    _MissingBanner(fields: missing),
                  Expanded(
                    child: widget.vm.loadingDetail
                        ? const _DetailSkeleton()
                        : (!ready) 
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const CircularProgressIndicator(color: AppStyles.primaryPurple),
                                    const SizedBox(height: 20),
                                    Text(
                                      '✨ AI is extracting syllabus data...',
                                      style: TextStyle(
                                        color: AppStyles.primaryPurple.withOpacity(0.8),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'This usually takes about 5-10 seconds.',
                                      style: TextStyle(color: AppStyles.darkGray, fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            : widget.vm.loading
                                ? const Center(
                                    child: CircularProgressIndicator(color: AppStyles.primaryPurple),
                                  )
                                : TabBarView(
                                controller: _tabs,
                                children: [
                                  _InfoTab(
                                    ws: ws,
                                    editableKeys: _editableKeys,
                                    ctrl: _ctrl,
                                    onSave: _onSave,
                                    isGlobalEditing: _isEditingDetails, // Pass the global state
                                  ),
                                  SectionsTab(
                                    ws: ws,
                                    vm: widget.vm,
                                    onError: _showError,
                                    onNavigateToStudents: () => _tabs.animateTo(2),
                                  ),
                                  StudentsTab(
                                    ws: ws,
                                    vm: widget.vm,
                                    onError: _showError,
                                  ),
                                  MaterialsTab(
                                    ws: ws,
                                    vm: widget.vm,
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
                                        Icon(Icons.construction_rounded, size: 48, color: AppStyles.darkGray.withOpacity(0.5)),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Attendance Module Coming Soon',
                                          style: TextStyle(
                                            color: AppStyles.darkGray,
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
      backgroundColor: AppStyles.primaryDeepPurple,
      foregroundColor: Colors.white,
      actions: [
        // 👉 The Global Edit Toggle
        if (_currentTabIndex == 0)
          IconButton(
            icon: Icon(
              _isEditingDetails ? Icons.check_rounded : Icons.edit_rounded, 
              color: Colors.white,
            ),
            tooltip: _isEditingDetails ? 'Save Changes' : 'Edit Details',
            onPressed: () {
              if (_isEditingDetails) {
                // If they click the checkmark, save it!
                _onSave(); 
              }
              setState(() {
                _isEditingDetails = !_isEditingDetails;
              });
            },
          ),
        const NotificationBell(), 
        const SizedBox(width: 4)
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppStyles.primaryDeepPurple, Color(0xFF9B78E0)],
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppStyles.warning.withOpacity(0.2), 
                          borderRadius: AppStyles.borderRadiusXL,
                          border: Border.all(
                            color: ready ? AppStyles.accent : AppStyles.warning,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              ready ? Icons.check_circle_rounded : Icons.pending_rounded,
                              color: ready ? AppStyles.accent : AppStyles.warning,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ready ? 'Ready' : 'Draft',
                              style: TextStyle(
                                color: ready ? AppStyles.accent : AppStyles.warning,
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
                            _StatPill(icon: Icons.calendar_today_rounded, label: semester),
                            const SizedBox(width: 8),
                          ],
                          _StatPill(
                            icon: Icons.groups_2_rounded,
                            label: '$sectionCount section${sectionCount == 1 ? "" : "s"}',
                          ),
                          const SizedBox(width: 8),
                          _StatPill(
                            icon: Icons.people_alt_rounded,
                            label: '$totalStudents student${totalStudents == 1 ? "" : "s"}',
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
        backgroundColor: AppStyles.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
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
          backgroundColor: AppStyles.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
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
    required this.isGlobalEditing,
  });
  final Workspace ws;
  final List<String> editableKeys;
  final TextEditingController Function(String, String) ctrl;
  final Future<void> Function() onSave;
  final bool isGlobalEditing;

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

const _numericKeys = {'allow_validation', 'capacity', 'max_students'};

class _InfoTabState extends State<_InfoTab>
    with AutomaticKeepAliveClientMixin<_InfoTab> {
  @override
  bool get wantKeepAlive => true;

  final Map<String, String?> _errors = {};

  TextInputType _keyboardType(String key) {
    if (_numericKeys.contains(key)) return TextInputType.number;
    return TextInputType.text;
  }

  Future<void> _promptForDates() async {
    DateTime? currentStart = DateTime.tryParse(widget.ctrl('start_date', '').text);
    DateTime? currentEnd = DateTime.tryParse(widget.ctrl('end_date', '').text);

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      helpText: 'SELECT SEMESTER DATES',
      saveText: 'CONFIRM DATES',
      initialEntryMode: DatePickerEntryMode.calendarOnly, 
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: (currentStart != null && currentEnd != null && currentEnd.isAfter(currentStart))
          ? DateTimeRange(start: currentStart, end: currentEnd)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppStyles.primaryPurple,
              onPrimary: Colors.white,
              surface: AppStyles.white,
              onSurface: AppStyles.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        widget.ctrl('start_date', '').text = picked.start.toIso8601String().split('T').first;
        widget.ctrl('end_date', '').text = picked.end.toIso8601String().split('T').first;
      });
    }
  }

  String _calculateCurrentWeek() {
    final startStr = widget.ws.fields['start_date'];
    final endStr = widget.ws.fields['end_date'];
    
    if (startStr == null || startStr.isEmpty) return 'Week --';
    final start = DateTime.tryParse(startStr);
    if (start == null) return 'Week --';

    final now = DateTime.now();

    if (endStr != null && endStr.isNotEmpty) {
      final end = DateTime.tryParse(endStr);
      if (end != null && now.isAfter(end.add(const Duration(days: 1)))) {
        return 'Ended';
      }
    }

    final startOnly = DateTime(start.year, start.month, start.day);
    final nowOnly = DateTime(now.year, now.month, now.day);

    if (nowOnly.isBefore(startOnly)) return 'Starts Soon';

    final startMonday = startOnly.subtract(Duration(days: startOnly.weekday - 1));
    final nowMonday = nowOnly.subtract(Duration(days: nowOnly.weekday - 1));

    final diffDays = nowMonday.difference(startMonday).inDays;
    final weekNum = (diffDays / 7).floor() + 1;

    return 'Week $weekNum';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final List<_FieldGroup> groups = [];
    for (final key in widget.editableKeys) {
      groups.add(_FieldGroup.single(key));
    }

    final weekText = _calculateCurrentWeek();

    String topicsToCover = 'Check syllabus for this week\'s topics.';
    String assessmentsDue = 'None';

    final scheduleString = widget.ws.fields['weekly_schedule'];
    
    if (scheduleString != null && scheduleString.isNotEmpty) {
      try {
        // Decode the JSON dictionary the AI extracted from the PDF
        final Map<String, dynamic> schedule = jsonDecode(scheduleString);
        
        // Extract the raw number from our "Week X" string
        final match = RegExp(r'Week (\d+)').firstMatch(weekText);
        
        if (match != null) {
          final weekNumber = match.group(1)!; // e.g., "3"
          
          // Grab the exact text for this week from the AI's dictionary!
          if (schedule.containsKey(weekNumber)) {
            topicsToCover = schedule[weekNumber].toString();
          }
          
          // (Optional) If you have the AI extract assessments too:
          final assessmentsString = widget.ws.fields['assessments_schedule'];
          if (assessmentsString != null) {
            final Map<String, dynamic> assessments = jsonDecode(assessmentsString);
            if (assessments.containsKey(weekNumber)) {
              assessmentsDue = assessments[weekNumber].toString();
            }
          }
        }
      } catch (e) {
        debugPrint('Could not parse weekly schedule: $e');
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const _SectionHeader(title: 'Workspace Details', icon: Icons.info_outline_rounded),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppStyles.primaryPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10), 
                border: Border.all(color: AppStyles.primaryPurple.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.date_range_rounded, size: 16, color: AppStyles.primaryPurple),
                  const SizedBox(width: 6), 
                  Text(
                    weekText,
                    style: const TextStyle(
                      fontSize: 13, 
                      fontWeight: FontWeight.w800,
                      color: AppStyles.primaryPurple,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // Insert the new Weekly Overview Card here!
        _WeeklyOverviewCard(
          weekText: weekText,
          topics: topicsToCover,
          assessments: assessmentsDue,
        ),
        
        const SizedBox(height: 16),
        
        if (widget.isGlobalEditing) 
          const Padding(
            padding: EdgeInsets.only(bottom: 12.0),
            child: Text('Tap the checkmark in the top right to save changes.',
                style: TextStyle(fontSize: 12, color: AppStyles.primaryPurple, fontWeight: FontWeight.bold)),
          ),
        Container(
          decoration: BoxDecoration(
            color: AppStyles.white,
            borderRadius: AppStyles.borderRadiusL,
            boxShadow: AppStyles.shadowMedium,
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
                    isEditing: widget.isGlobalEditing, // Drive layout from global state
                    error: _errors[group.key],
                    keyboardType: _keyboardType(group.key),
                    onDateTap: () {
                      if (widget.isGlobalEditing && (group.key == 'start_date' || group.key == 'end_date')) {
                        _promptForDates();
                      }
                    },
                  ),
                  if (!isLast)
                    const Divider(height: 1, indent: 16, endIndent: 16, color: AppStyles.borderLight),
                ]);
              }),
            ],
          ),
        ),
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
    required this.onDateTap,
  });
  
  final String fieldKey;
  final String value;
  final TextEditingController Function(String, String) ctrl;
  final bool isEditing;
  final String? error;
  final TextInputType keyboardType;
  final VoidCallback onDateTap;

  @override
  Widget build(BuildContext context) {
    // If we are actively editing, render the input form fields
    if (isEditing) {
      return _buildEditableForm(context);
    } 
    // If not, render the clean, read-only list with NO pens
    else {
      return _buildReadOnlyDisplay(context);
    }
  }

  // ─── The Active Editing State ───────────────────────────────────────────
  Widget _buildEditableForm(BuildContext context) {
    final label = _fieldLabels[fieldKey] ?? fieldKey;
    final icon = _fieldIcons[fieldKey] ?? Icons.edit_rounded;
    final liveValue = ctrl(fieldKey, value).text;
    final hasError = error != null;

    Widget inputWidget;

    if (fieldKey == 'semester') {
      const semesterOptions = ['Spring', 'Fall', 'Summer 1', 'Summer 2', 'TBD'];
      String currentDropVal = semesterOptions.contains(liveValue) ? liveValue : 'TBD';
      if (liveValue != currentDropVal) ctrl(fieldKey, value).text = currentDropVal;

      inputWidget = DropdownButtonFormField<String>(
        value: currentDropVal,
        items: semesterOptions.map((String option) => DropdownMenuItem(value: option, child: Text(option))).toList(),
        onChanged: (String? newValue) {
          if (newValue != null) ctrl(fieldKey, value).text = newValue; 
        },
        icon: const Icon(Icons.arrow_drop_down_rounded),
        dropdownColor: AppStyles.white, 
        style: const TextStyle(color: AppStyles.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
        decoration: _buildInputDeco(icon, hasError),
      );
    } else if (fieldKey == 'start_date' || fieldKey == 'end_date') {
      inputWidget = GestureDetector(
        onTap: onDateTap,
        child: AbsorbPointer( // Prevents keyboard opening, forces tap to go to GestureDetector
          child: TextFormField(
            controller: ctrl(fieldKey, value),
            readOnly: true,
            style: const TextStyle(color: AppStyles.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
            decoration: _buildInputDeco(icon, hasError).copyWith(
              suffixIcon: const Icon(Icons.calendar_month_rounded, color: AppStyles.primaryPurple, size: 18),
            ),
          ),
        ),
      );
    } else {
      inputWidget = TextField(
        controller: ctrl(fieldKey, value),
        keyboardType: keyboardType,
        style: const TextStyle(color: AppStyles.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
        decoration: _buildInputDeco(icon, hasError),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: hasError ? AppStyles.warning : AppStyles.primaryPurple, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          inputWidget,
        ],
      ),
    );
  }

  InputDecoration _buildInputDeco(IconData icon, bool hasError) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: hasError ? AppStyles.warning : AppStyles.primaryPurple, size: 17),
      hintText: _hintFor(fieldKey),
      hintStyle: const TextStyle(color: AppStyles.darkGray, fontSize: 13),
      filled: true,
      fillColor: hasError ? AppStyles.warning.withOpacity(0.1) : AppStyles.mediumGray,
      border: OutlineInputBorder(borderRadius: AppStyles.borderRadiusM, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppStyles.borderRadiusM,
        borderSide: BorderSide(color: hasError ? AppStyles.warning : AppStyles.primaryPurple, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      errorText: error,
      errorStyle: const TextStyle(fontSize: 11),
    );
  }

  // ─── The Clean Read-Only State ──────────────────────────────────────────
  Widget _buildReadOnlyDisplay(BuildContext context) {
    final label = _fieldLabels[fieldKey] ?? fieldKey;
    final icon = _fieldIcons[fieldKey] ?? Icons.info_outline_rounded;
    final liveValue = ctrl(fieldKey, value).text;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: liveValue.isEmpty ? AppStyles.warning.withOpacity(0.1) : AppStyles.mediumGray,
            borderRadius: AppStyles.borderRadiusM,
          ),
          child: Icon(icon, color: liveValue.isEmpty ? AppStyles.warning : AppStyles.primaryPurple, size: 17),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppStyles.darkGray, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                liveValue.isEmpty ? 'Not set' : liveValue,
                style: TextStyle(
                  color: liveValue.isEmpty ? AppStyles.darkGray : AppStyles.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontStyle: liveValue.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
        // NOTE: No suffix icon here anymore! Clean design!
      ]),
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
          Icon(icon, color: AppStyles.primaryPurple, size: 17),
          const SizedBox(width: 7),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppStyles.textPrimary)),
        ],
      );
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label, this.highlight = false});
  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: highlight ? AppStyles.accent.withOpacity(0.2) : Colors.white.withOpacity(0.15),
          borderRadius: AppStyles.borderRadiusXL,
          border: Border.all(
            color: highlight ? AppStyles.accent.withOpacity(0.5) : Colors.white.withOpacity(0.25),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: highlight ? AppStyles.accent : Colors.white, size: 11),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: highlight ? AppStyles.accent : Colors.white,
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
      color: AppStyles.warning.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: AppStyles.warning, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Complete: $labels',
            style: const TextStyle(color: AppStyles.warning, fontSize: 12, fontWeight: FontWeight.w600),
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
        final dim = Color.lerp(const Color(0xFFE8E8EE), const Color(0xFFF2F2F6), t)!;
        final bright = Color.lerp(const Color(0xFFDDDDE6), const Color(0xFFECECF2), t)!;

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
            _skeletonCard(dim, bright, children: [_sectionRow(dim, bright, narrowName: true)]),
            const SizedBox(height: 28),
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: AppStyles.primaryPurple.withOpacity(0.3 + t * 0.2),
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  'Fetching workspace…',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppStyles.darkGray.withOpacity(0.55 + t * 0.2),
                  ),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }

  Widget _pill(Color color, {required double w, double h = 12, double r = 6}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(r)),
      );

  Widget _divider(Color color) => Container(height: 1, color: color);

  Widget _skeletonCard(Color bg, Color hi, {required List<Widget> children}) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppStyles.borderRadiusL,
          border: Border.all(color: AppStyles.borderLight),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(children: children),
      );

  Widget _fieldRow(Color bg, Color hi) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: hi, borderRadius: AppStyles.borderRadiusM)),
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
          Container(width: 42, height: 42, decoration: BoxDecoration(color: hi, borderRadius: AppStyles.borderRadiusM)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
  const _ShimmerBar({required this.width, required this.height, required this.light, required this.lighter});
  final double width, height;
  final Color light, lighter;

  @override
  State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
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

// ─── TAB 4 — Materials ────────────────────────────────────────────────────────
class MaterialsTab extends StatefulWidget {
  const MaterialsTab({super.key, required this.ws, required this.vm});
  final Workspace ws;
  final WorkspacesViewModel vm;

  @override
  State<MaterialsTab> createState() => _MaterialsTabState();
}

class _MaterialsTabState extends State<MaterialsTab> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final materials = widget.vm.current?.materials ?? [];

    return DropTarget(
      onDragDone: (detail) {
        setState(() => _isDragging = false);
        widget.vm.uploadMaterial(droppedFiles: detail.files);
      },
      onDragEntered: (detail) {
        setState(() => _isDragging = true);
      },
      onDragExited: (detail) {
        setState(() => _isDragging = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: double.infinity,
        color: _isDragging ? AppStyles.primaryPurple.withOpacity(0.08) : Colors.transparent,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: InkWell(
                onTap: widget.vm.uploadingMaterial ? null : () => widget.vm.uploadMaterial(),
                borderRadius: AppStyles.borderRadiusM,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: _isDragging ? AppStyles.mediumGray.withOpacity(0.15) : AppStyles.mediumGray,
                    borderRadius: AppStyles.borderRadiusM,
                    border: Border.all(
                      color: _isDragging ? AppStyles.primaryPurple : AppStyles.primaryPurple.withOpacity(0.3),
                      width: _isDragging ? 2.0 : 1.5,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.vm.uploadingMaterial)
                        const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppStyles.primaryPurple),
                        )
                      else
                        Icon(
                          _isDragging ? Icons.download_rounded : Icons.cloud_upload_rounded, 
                          color: AppStyles.primaryPurple, 
                          size: 24
                        ),
                      const SizedBox(width: 12),
                      Text(
                        widget.vm.uploadingMaterial 
                            ? 'Uploading material...' 
                            : (_isDragging ? 'Drop files here!' : 'Upload Course Material'),
                        style: const TextStyle(
                          color: AppStyles.primaryPurple,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: materials.isEmpty
                  ? const Center(
                      child: Text(
                        'No materials uploaded yet.\nDrop PDFs, slides, or reading materials here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppStyles.darkGray, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: materials.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final material = materials[index]; 
                        final isSelected = widget.vm.selectedMaterialIdsForQuiz.contains(material.id);
                        
                        return Container(
                          decoration: BoxDecoration(
                            color: isSelected ? AppStyles.mediumGray : Colors.white,
                            borderRadius: AppStyles.borderRadiusM,
                            boxShadow: AppStyles.shadowMedium,
                            border: isSelected ? Border.all(color: AppStyles.primaryPurple.withOpacity(0.5)) : null,
                          ),
                          child: CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            activeColor: AppStyles.primaryPurple,
                            checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            value: isSelected,
                            onChanged: (bool? value) {
                              widget.vm.toggleMaterialSelection(material.id);
                            },
                            title: Row(
                              children: [
                                const Icon(Icons.insert_drive_file_rounded, color: AppStyles.primaryPurple, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    material.fileName,
                                    style: const TextStyle(color: AppStyles.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            secondary: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: AppStyles.warning, size: 20),
                              onPressed: () => widget.vm.deleteMaterial(material.id),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyOverviewCard extends StatelessWidget {
  const _WeeklyOverviewCard({
    required this.weekText,
    required this.topics,
    required this.assessments,
  });

  final String weekText;
  final String topics;
  final String assessments;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppStyles.primaryPurple.withOpacity(0.08), AppStyles.primaryPurple.withOpacity(0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppStyles.borderRadiusL,
        border: Border.all(color: AppStyles.primaryPurple.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: AppStyles.primaryPurple, size: 18),
              const SizedBox(width: 8),
              Text(
                '$weekText Overview',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppStyles.primaryPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRow(Icons.menu_book_rounded, 'To Cover:', topics),
          const SizedBox(height: 8),
          _buildRow(Icons.assignment_late_rounded, 'Assessments:', assessments, isAlert: assessments.toLowerCase() != 'none'),
        ],
      ),
    );
  }

  Widget _buildRow(IconData icon, String label, String content, {bool isAlert = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: isAlert ? AppStyles.warning : AppStyles.darkGray),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: AppStyles.textPrimary, height: 1.4),
              children: [
                TextSpan(
                  text: '$label ',
                  style: TextStyle(
                    fontWeight: FontWeight.w700, 
                    color: isAlert ? AppStyles.warning : AppStyles.darkGray
                  ),
                ),
                TextSpan(
                  text: content,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}