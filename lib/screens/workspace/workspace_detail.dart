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
    _tabs = TabController(length: 7, vsync: this);

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

  void _initiateGenerationFromAssessment(List<int> materialIds, String assessmentName) {
    // 1. Set the materials
    widget.vm.clearMaterialSelection();
    for (final id in materialIds) {
      widget.vm.toggleMaterialSelection(id);
    }

    // 2. Pre-fill the AI instructions to focus on this assessment!
    for (var config in _configs.values) {
      config.topicController.text = "Focus entirely on generating questions for: $assessmentName";
    }

    // 3. Pop the config dialog
    _showSettings();
  }

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
                  Icon(Icons.tune, color: AppStyles.primary), 
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
                          side: BorderSide(color: config.isSelected ? AppStyles.primary : Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8)
                        ),
                        child: Column(
                          children: [
                            CheckboxListTile(
                              title: Text(config.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              value: config.isSelected,
                              activeColor: AppStyles.primary,
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
                  style: ElevatedButton.styleFrom(backgroundColor: AppStyles.primary, foregroundColor: Colors.white),
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
            backgroundColor: widget.vm.selectedMaterialIdsForQuiz.isEmpty ? Colors.grey : AppStyles.primary, 
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
                          color: AppStyles.primary,
                          borderRadius: AppStyles.borderRadiusL,
                          boxShadow: [
                            BoxShadow(
                              color: AppStyles.primary.withOpacity(0.3),
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
                          Tab(icon: Icon(Icons.assignment_rounded, size: 16), text: 'Assessments'),
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
                                    const CircularProgressIndicator(color: AppStyles.primary),
                                    const SizedBox(height: 20),
                                    Text(
                                      '✨ AI is extracting syllabus data...',
                                      style: TextStyle(
                                        color: AppStyles.primary.withOpacity(0.8),
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
                                    child: CircularProgressIndicator(color: AppStyles.primary),
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
                                  AssessmentsTab(
                                    ws: ws,
                                    onGenerateRequested: _initiateGenerationFromAssessment,
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
      backgroundColor: AppStyles.tertiaryDark,
      foregroundColor: AppStyles.textPrimary,
      actions: [
        // 👉 The Global Edit Toggle
        if (_currentTabIndex == 0)
          IconButton(
            icon: Icon(
              _isEditingDetails ? Icons.check_rounded : Icons.edit_rounded, 
              color: AppStyles.textPrimary,
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
              colors: [AppStyles.tertiaryDark, AppStyles.tertiary],
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
                                  color: AppStyles.textPrimary,
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
                          color: ready ? AppStyles.readyBg : AppStyles.draftBg, 
                          borderRadius: AppStyles.borderRadiusXL,
                          border: Border.all(
                            color: ready ? AppStyles.readyFg : AppStyles.draftFg,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              ready ? Icons.check_circle_rounded : Icons.pending_rounded,
                              color: ready ? AppStyles.readyFg : AppStyles.draftFg,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ready ? 'Ready' : 'Draft',
                              style: TextStyle(
                                color: ready ? AppStyles.readyFg : AppStyles.draftFg,
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
    
    final List<_FieldGroup> groups = [
      const _FieldGroup.pair('course_title', 'course_code', flex1: 1, flex2: 1),
      const _FieldGroup.single('semester'),
      const _FieldGroup.pair('start_date', 'end_date', flex1: 1, flex2: 1),
    ];

    // 👉 THE FIX 1: Removed the old 'for' loop here that was duplicating your fields!

    final weekText = _calculateCurrentWeek();

    String topicsToCover = 'Check syllabus for this week\'s topics.';
    String assessmentsDue = 'None';

    final scheduleString = widget.ws.fields['weekly_schedule'];

    if (scheduleString != null && scheduleString.isNotEmpty) {
      try {
        final Map<String, dynamic> schedule = jsonDecode(scheduleString);
        final match = RegExp(r'Week (\d+)').firstMatch(weekText);
        
        if (match != null) {
          final weekNumber = match.group(1)!;
          if (schedule.containsKey(weekNumber)) {
            topicsToCover = schedule[weekNumber].toString();
          }
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
                color: AppStyles.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10), 
                border: Border.all(color: AppStyles.primary.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.date_range_rounded, size: 16, color: AppStyles.primary),
                  const SizedBox(width: 6), 
                  Text(
                    weekText,
                    style: const TextStyle(
                      fontSize: 13, 
                      fontWeight: FontWeight.w800,
                      color: AppStyles.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
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
                style: TextStyle(fontSize: 12, color: AppStyles.primary, fontWeight: FontWeight.bold)),
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
                
                Widget content;
                
                if (group.isPair) {
                  content = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: group.flex1,
                        child: _InfoFieldRow(
                          fieldKey: group.key,
                          value: widget.ws.fields[group.key] ?? '',
                          ctrl: widget.ctrl,
                          isEditing: widget.isGlobalEditing,
                          error: _errors[group.key],
                          keyboardType: _keyboardType(group.key),
                          onDateTap: () {
                            if (widget.isGlobalEditing && (group.key == 'start_date' || group.key == 'end_date')) _promptForDates();
                          },
                          isFirstInPair: true, 
                        ),
                      ),
                      Expanded(
                        flex: group.flex2,
                        child: _InfoFieldRow(
                          fieldKey: group.secondKey!,
                          value: widget.ws.fields[group.secondKey!] ?? '',
                          ctrl: widget.ctrl,
                          isEditing: widget.isGlobalEditing,
                          error: _errors[group.secondKey!],
                          keyboardType: _keyboardType(group.secondKey!),
                          onDateTap: () {
                            if (widget.isGlobalEditing && (group.secondKey! == 'start_date' || group.secondKey! == 'end_date')) _promptForDates();
                          },
                          isSecondInPair: true, 
                        ),
                      ),
                    ],
                  );
                } else {
                  content = _InfoFieldRow(
                    fieldKey: group.key,
                    value: widget.ws.fields[group.key] ?? '',
                    ctrl: widget.ctrl,
                    isEditing: widget.isGlobalEditing,
                    error: _errors[group.key],
                    keyboardType: _keyboardType(group.key),
                    onDateTap: () {},
                  );
                }

                return Column(children: [
                  content,
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
  final int flex1;
  final int flex2;
  
  bool get isPair => secondKey != null;

  const _FieldGroup.single(this.key) 
      : secondKey = null, flex1 = 1, flex2 = 1;
      
  // Allows us to set flex properties (e.g. 60% width for Title, 40% for Code)
  const _FieldGroup.pair(this.key, this.secondKey, {this.flex1 = 1, this.flex2 = 1});
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
    this.isFirstInPair = false,
    this.isSecondInPair = false,
  });
  
  final String fieldKey;
  final String value;
  final TextEditingController Function(String, String) ctrl;
  final bool isEditing;
  final String? error;
  final TextInputType keyboardType;
  final VoidCallback onDateTap;
  final bool isFirstInPair;
  final bool isSecondInPair;

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
              suffixIcon: const Icon(Icons.calendar_month_rounded, color: AppStyles.primary, size: 18),
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
      padding: EdgeInsets.fromLTRB(
        isSecondInPair ? 8 : 16, 
        14, 
        isFirstInPair ? 8 : 16, 
        14
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: hasError ? AppStyles.warning : AppStyles.primary, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          inputWidget,
        ],
      ),
    );
  }

  InputDecoration _buildInputDeco(IconData icon, bool hasError) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: hasError ? AppStyles.warning : AppStyles.primary, size: 17),
      hintText: _hintFor(fieldKey),
      hintStyle: const TextStyle(color: AppStyles.darkGray, fontSize: 13),
      filled: true,
      fillColor: hasError ? AppStyles.warning.withOpacity(0.1) : AppStyles.mediumGray,
      border: OutlineInputBorder(borderRadius: AppStyles.borderRadiusM, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppStyles.borderRadiusM,
        borderSide: BorderSide(color: hasError ? AppStyles.warning : AppStyles.primary, width: 2),
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
      padding: EdgeInsets.fromLTRB(
        isSecondInPair ? 8 : 16, 
        15, 
        isFirstInPair ? 8 : 16, 
        15
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: liveValue.isEmpty ? AppStyles.warning.withOpacity(0.1) : AppStyles.mediumGray,
            borderRadius: AppStyles.borderRadiusM,
          ),
          child: Icon(icon, color: liveValue.isEmpty ? AppStyles.warning : AppStyles.primary, size: 17),
        ),
        SizedBox(width: (isFirstInPair || isSecondInPair) ? 8 : 13),
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
          Icon(icon, color: AppStyles.primary, size: 17),
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
        // Slightly increased padding for breathing room
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          // 👉 THE FIX: Increased background opacity to 0.2 / 0.25 for a more solid feel
          color: highlight ? AppStyles.accent.withOpacity(0.25) : AppStyles.primary.withOpacity(0.2),
          borderRadius: AppStyles.borderRadiusXL,
          border: Border.all(
            // 👉 THE FIX: Stronger border opacity to frame the pill clearly
            color: highlight ? AppStyles.accent.withOpacity(0.8) : AppStyles.primary.withOpacity(0.5),
            width: 1.0,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // 👉 THE FIX: Switched to textPrimary (almost black) for maximum contrast
          Icon(
            icon, 
            color: highlight ? AppStyles.accent : AppStyles.textPrimary, 
            size: 12
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              // 👉 THE FIX: Dark text and heavier font weight
              color: highlight ? AppStyles.accent : AppStyles.textPrimary,
              fontSize: 12, 
              fontWeight: FontWeight.w800, 
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
                    color: AppStyles.primary.withOpacity(0.3 + t * 0.2),
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
        color: _isDragging ? AppStyles.primary.withOpacity(0.08) : Colors.transparent,
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
                      color: _isDragging ? AppStyles.primary : AppStyles.primary.withOpacity(0.3),
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
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppStyles.primary),
                        )
                      else
                        Icon(
                          _isDragging ? Icons.download_rounded : Icons.cloud_upload_rounded, 
                          color: AppStyles.primary, 
                          size: 24
                        ),
                      const SizedBox(width: 12),
                      Text(
                        widget.vm.uploadingMaterial 
                            ? 'Uploading material...' 
                            : (_isDragging ? 'Drop files here!' : 'Upload Course Material'),
                        style: const TextStyle(
                          color: AppStyles.primary,
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
                            border: isSelected ? Border.all(color: AppStyles.primary.withOpacity(0.5)) : null,
                          ),
                          child: CheckboxListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            activeColor: AppStyles.primary,
                            checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            value: isSelected,
                            onChanged: (bool? value) {
                              widget.vm.toggleMaterialSelection(material.id);
                            },
                            title: Row(
                              children: [
                                const Icon(Icons.insert_drive_file_rounded, color: AppStyles.primary, size: 20),
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
          colors: [AppStyles.primary.withOpacity(0.08), AppStyles.primary.withOpacity(0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppStyles.borderRadiusL,
        border: Border.all(color: AppStyles.primary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: AppStyles.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                '$weekText Overview',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppStyles.primary,
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

// ─── Helper Class for Smart Parsing ───────────────────────────────────────────
class _AssessmentItem {
  final String name;
  final String subtitle;
  _AssessmentItem(this.name, this.subtitle);
}

// =============================================================================
// ── TAB 5 — Assessments (With Bidirectional & Regex Parsing) ─────────────────
// =============================================================================

class AssessmentsTab extends StatelessWidget {
  const AssessmentsTab({super.key, required this.ws, required this.onGenerateRequested});
  final Workspace ws;
  final void Function(List<int> materialIds, String assessmentName) onGenerateRequested;

  List<_AssessmentItem> _getAssessments() {
    final List<_AssessmentItem> list = [];
    final Set<String> foundKeys = {};

    // Helper to safely add items and prevent duplicates
    void addSafely(String name, String weekRaw) {
      String cleanName = name.trim();
      String cleanWeek = weekRaw.trim();

      // Standardize the week text to "Week X"
      final weekMatch = RegExp(r'\d+').firstMatch(cleanWeek);
      String finalWeek = weekMatch != null ? 'Week ${weekMatch.group(0)}' : 'Scheduled';

      if (cleanName.isEmpty || cleanName.toLowerCase() == 'none' || cleanName.toLowerCase() == 'n/a') return;

      // Unique ID prevents adding "Quiz 1" to "Week 4" twice!
      final uniqueId = '${cleanName.toLowerCase()}_$finalWeek';
      if (foundKeys.contains(uniqueId)) return;
      foundKeys.add(uniqueId);

      list.add(_AssessmentItem(cleanName, finalWeek));
    }

    // 1. Process Official Assessments (Handles BOTH flipped AI formats safely)
    final assessStr = ws.fields['assessments_schedule'] ?? '';
    if (assessStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(assessStr);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            final keyStr = k.toString().trim();
            final valStr = v.toString().trim();

            final keyIsNum = int.tryParse(keyStr) != null;
            final keyHasWeek = keyStr.toLowerCase().startsWith('week');
            final valIsNum = int.tryParse(valStr) != null;
            final valHasWeek = valStr.toLowerCase().startsWith('week');

            if (keyIsNum || keyHasWeek) {
              // Format A: {"9": "Midterm Exam"}
              final parts = valStr.split(',');
              for (var p in parts) addSafely(p, keyStr);
            } else if (valIsNum || valHasWeek) {
              // Format B: {"Midterm Exam": "9"} -> This is what broke your old code!
              addSafely(keyStr, valStr);
            } else {
              // Fallback
              addSafely(valStr, keyStr);
            }
          });
        }
      } catch (_) {}
    }

    // 2. 🕵️‍♂️ Aggressively Scan Weekly Schedule as a Safety Net
    final weeklyStr = ws.fields['weekly_schedule'] ?? '';
    if (weeklyStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(weeklyStr);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            final valStr = v.toString();
            
            // This Regex hunts for ANY assessment hiding in the text
            final matches = RegExp(r'\b(Quiz\s*\d+|Quiz|Test\s*\d+|Test|Midterm\s*Exam|Midterm|Final\s*Exam|Final|Assignment\s*\d+|Project)\b', caseSensitive: false).allMatches(valStr);

            for (final m in matches) {
              final raw = m.group(0)!;
              // Cleanly capitalize (e.g. "midterm exam" -> "Midterm Exam")
              final clean = raw.split(' ').map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1).toLowerCase() : '').join(' ');

              final weekMatch = RegExp(r'\d+').firstMatch(k.toString());
              final weekStr = weekMatch != null ? 'Week ${weekMatch.group(0)}' : 'Scheduled';

              // Smart check: If "Midterm Exam" is already in the list from Step 1, 
              // we don't want to add "Midterm" again here.
              bool hasSpecific = list.any((item) =>
                  item.subtitle == weekStr &&
                  item.name.toLowerCase().contains(clean.toLowerCase()) &&
                  item.name.length >= clean.length);

              if (!hasSpecific) {
                addSafely(clean, k.toString());
              }
            }
          });
        }
      } catch (_) {}
    }

    // 3. Sort chronologically by Week Number
    list.sort((a, b) {
      final aMatch = RegExp(r'\d+').firstMatch(a.subtitle);
      final bMatch = RegExp(r'\d+').firstMatch(b.subtitle);
      final aNum = aMatch != null ? int.parse(aMatch.group(0)!) : 99;
      final bNum = bMatch != null ? int.parse(bMatch.group(0)!) : 99;
      return aNum.compareTo(bNum);
    });

    return list;
  }

  void _openLinkingSheet(BuildContext context, String assessmentName) async {
    if (ws.materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload materials to the workspace first!')),
      );
      return;
    }

    final confirmedIds = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AssessmentLinkSheet(
        assessmentName: assessmentName,
        materials: ws.materials,
      ),
    );

    if (confirmedIds != null && confirmedIds.isNotEmpty) {
      onGenerateRequested(confirmedIds, assessmentName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assessments = _getAssessments();

    if (assessments.isEmpty) {
      return const Center(
        child: Text(
          'No assessments found in syllabus.',
          style: TextStyle(color: AppStyles.darkGray, fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: assessments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = assessments[index]; 

        return InkWell(
          onTap: () => _openLinkingSheet(context, item.name),
          borderRadius: AppStyles.borderRadiusM,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppStyles.borderRadiusM,
              boxShadow: AppStyles.shadowMedium,
              border: Border.all(color: AppStyles.borderLight),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppStyles.primary.withOpacity(0.1),
                    borderRadius: AppStyles.borderRadiusM,
                  ),
                  child: const Icon(Icons.assignment_rounded, color: AppStyles.primary, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppStyles.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle, 
                        style: const TextStyle(fontSize: 12, color: AppStyles.darkGray, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.auto_awesome_rounded, color: AppStyles.primary, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Smart Bottom Sheet ───────────────────────────────────────────────────────
class _AssessmentLinkSheet extends StatefulWidget {
  const _AssessmentLinkSheet({required this.assessmentName, required this.materials});
  final String assessmentName;
  final List<WorkspaceMaterial> materials;

  @override
  State<_AssessmentLinkSheet> createState() => _AssessmentLinkSheetState();
}

class _AssessmentLinkSheetState extends State<_AssessmentLinkSheet> {
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _runAutoMatcher();
  }

  // 👉 Option B: AI/Regex Auto-Matcher
  void _runAutoMatcher() {
    final a = widget.assessmentName.toLowerCase();
    
    for (final m in widget.materials) {
      final f = m.fileName.toLowerCase();
      
      // 1. Direct overlap (e.g. "Midterm" matches "midterm_review.pdf")
      if (f.contains(a)) {
        _selectedIds.add(m.id);
        continue;
      }
      
      // 2. Semantic & Abbreviation matching
      if (a.contains('quiz')) {
        // Matches "quiz" OR "q1", "q2", "q12", etc.
        if (f.contains('quiz') || RegExp(r'\bq\d+\b').hasMatch(f)) { 
          _selectedIds.add(m.id); continue; 
        }
      }
      if (a.contains('test') && (f.contains('test') || RegExp(r'\bt\d+\b').hasMatch(f))) { 
        _selectedIds.add(m.id); continue; 
      }
      if (a.contains('midterm') && f.contains('midterm')) { _selectedIds.add(m.id); continue; }
      if (a.contains('exam') && f.contains('exam')) { _selectedIds.add(m.id); continue; }
      if (a.contains('assignment') && f.contains('assignment')) { _selectedIds.add(m.id); continue; }
      if (a.contains('project') && f.contains('project')) { _selectedIds.add(m.id); continue; }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppStyles.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 12),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppStyles.borderLight, borderRadius: BorderRadius.circular(2))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI Quiz Generator', style: TextStyle(color: AppStyles.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Link Materials to ${widget.assessmentName}', style: const TextStyle(color: AppStyles.textPrimary, fontWeight: FontWeight.w800, fontSize: 20)),
                  const SizedBox(height: 6),
                  const Text('We auto-selected materials based on the filename. Review and confirm below:', style: TextStyle(color: AppStyles.darkGray, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            const Divider(color: AppStyles.borderLight),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: widget.materials.length,
                itemBuilder: (context, index) {
                  final mat = widget.materials[index];
                  final isSelected = _selectedIds.contains(mat.id);
                  
                  return CheckboxListTile(
                    activeColor: AppStyles.primary,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    title: Row(
                      children: [
                        Icon(Icons.insert_drive_file_rounded, color: isSelected ? AppStyles.primary : AppStyles.darkGray, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(mat.fileName, style: TextStyle(
                            color: isSelected ? AppStyles.textPrimary : AppStyles.darkGray, 
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, 
                            fontSize: 14,
                          )),
                        ),
                      ],
                    ),
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        val == true ? _selectedIds.add(mat.id) : _selectedIds.remove(mat.id);
                      });
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppStyles.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text('Confirm ${_selectedIds.length} Files & Generate', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  onPressed: _selectedIds.isEmpty ? null : () => Navigator.pop(context, _selectedIds.toList()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}