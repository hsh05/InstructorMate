// lib/screens/workspace_sections.dart

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/state/workspaces_vm.dart';
import '../models/workspace_model.dart';
import '../app_styles.dart';

// ─── TAB 2 — Sections ─────────────────────────────────────────────────────────
class SectionsTab extends StatefulWidget {
  const SectionsTab({
    super.key,
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
  State<SectionsTab> createState() => _SectionsTabState();
}

class _SectionsTabState extends State<SectionsTab>
    with AutomaticKeepAliveClientMixin<SectionsTab> {
  @override
  bool get wantKeepAlive => true;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // Helper method to convert backend string to minutes for math
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
      builder: (_) => SectionSheetContent(
        editing: editing,
        vm: widget.vm,
        onSuccess: (msg) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(msg),
              backgroundColor: AppStyles.accent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
            ));
          }
        },
        onError: (e) {
          if (mounted) widget.onError(e);
        },
        timeToMins: _timeToMins,
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
                'Tap "+ Add Section" to create your first class section.',
          )
        else
          ...ws.sections.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SectionCard(
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
                style: const TextStyle(fontSize: 13, color: AppStyles.darkGray)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(color: AppStyles.darkGray)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppStyles.error,
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

// ─── Section Sheet Content ────────────────────────────────────────────────────
class SectionSheetContent extends StatefulWidget {
  const SectionSheetContent({
    super.key,
    required this.editing,
    required this.vm,
    required this.onSuccess,
    required this.onError,
    required this.timeToMins,
    required this.days,
  });
  final Section? editing;
  final WorkspacesViewModel vm;
  final void Function(String) onSuccess;
  final void Function(String) onError;
  final int? Function(String) timeToMins;
  final List<String> days;

  @override
  State<SectionSheetContent> createState() => _SectionSheetContentState();
}

class _SectionSheetContentState extends State<SectionSheetContent> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _locationCtrl;
  late List<String> _selDays;
  late int _selReminderMins;
  
  late TimeOfDay _startTime;
  late int _durationMinutes;
  
  bool _saving = false;
  String? _error;

  static const _standardDurations = [30, 60, 90, 120];
  static const _standardReminders = [5, 10, 15, 20, 30];

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');
    _selDays = List.from(e?.schedule.days ?? []);
    _selReminderMins = e?.schedule.reminderMinutes ?? 10;

    TimeOfDay defaultStart = const TimeOfDay(hour: 9, minute: 0);
    int defaultDuration = 60; 

    if (e != null && e.schedule.startTime.isNotEmpty) {
      final sMins = widget.timeToMins(e.schedule.startTime);
      final eMins = widget.timeToMins(e.schedule.endTime);
      
      if (sMins != null && eMins != null) {
        defaultDuration = eMins - sMins;
        if (defaultDuration <= 0) defaultDuration = 60; 
      }
      if (sMins != null) {
        defaultStart = TimeOfDay(hour: sMins ~/ 60, minute: sMins % 60);
      }
    }
    
    _startTime = defaultStart;
    _durationMinutes = defaultDuration;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  TimeOfDay _calculateEndTime() {
    final totalMins = _startTime.hour * 60 + _startTime.minute + _durationMinutes;
    return TimeOfDay(hour: (totalMins ~/ 60) % 24, minute: totalMins % 60);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppStyles.darkGray,
                letterSpacing: 1.2)),
      );

  Future<void> _showCustomDurationDialog() async {
    final isCustom = !_standardDurations.contains(_durationMinutes);
    final ctrl = TextEditingController(text: isCustom ? _durationMinutes.toString() : '');
    
    final val = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusL),
        title: const Text('Custom Duration', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppStyles.textPrimary)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppStyles.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. 45',
            hintStyle: const TextStyle(color: AppStyles.darkGray, fontSize: 14),
            suffixText: 'min',
            suffixStyle: const TextStyle(fontWeight: FontWeight.w700, color: AppStyles.darkGray),
            filled: true,
            fillColor: AppStyles.lightGray,
            border: OutlineInputBorder(borderRadius: AppStyles.borderRadiusM, borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: AppStyles.borderRadiusM, borderSide: const BorderSide(color: AppStyles.primaryPurple, width: 1.5)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppStyles.darkGray, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppStyles.primaryPurple,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
            ),
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('Set Time', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (val != null && val > 0) {
      setState(() => _durationMinutes = val);
    }
  }

  Future<void> _showCustomReminderDialog() async {
    final isCustom = !_standardReminders.contains(_selReminderMins);
    final ctrl = TextEditingController(text: isCustom ? _selReminderMins.toString() : '');
    
    final val = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusL),
        title: const Text('Custom Reminder', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppStyles.textPrimary)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppStyles.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. 45',
            hintStyle: const TextStyle(color: AppStyles.darkGray, fontSize: 14),
            suffixText: 'min',
            suffixStyle: const TextStyle(fontWeight: FontWeight.w700, color: AppStyles.darkGray),
            filled: true,
            fillColor: AppStyles.lightGray,
            border: OutlineInputBorder(borderRadius: AppStyles.borderRadiusM, borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: AppStyles.borderRadiusM, borderSide: const BorderSide(color: AppStyles.primaryPurple, width: 1.5)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppStyles.darkGray, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppStyles.primaryPurple,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
            ),
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('Set Reminder', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (val != null && val >= 0) {
      setState(() => _selReminderMins = val);
    }
  }

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

    final startStr = _formatTimeOfDay(_startTime);
    final endT = _calculateEndTime();
    final endStr = _formatTimeOfDay(endT);

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
    final endT = _calculateEndTime();

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
                  color: AppStyles.borderLight,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.editing != null ? 'Edit Section' : 'New Section',
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppStyles.textPrimary),
          ),
          
          _label('SECTION NAME'),
          TextField(
            controller: _nameCtrl,
            onChanged: (_) => setState(() => _error = null),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'e.g. Section A',
              hintStyle: const TextStyle(color: AppStyles.darkGray, fontSize: 13),
              filled: true,
              fillColor: AppStyles.lightGray,
              border: OutlineInputBorder(
                  borderRadius: AppStyles.borderRadiusM,
                  borderSide: const BorderSide(color: AppStyles.borderLight)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: AppStyles.borderRadiusM,
                  borderSide: const BorderSide(color: AppStyles.borderLight)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: AppStyles.borderRadiusM,
                  borderSide: const BorderSide(color: AppStyles.primaryPurple, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          
          _label('LOCATION / ROOM'),
          TextField(
            controller: _locationCtrl,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'e.g. Room 204',
              hintStyle: const TextStyle(color: AppStyles.darkGray, fontSize: 13),
              filled: true,
              fillColor: AppStyles.lightGray,
              border: OutlineInputBorder(
                  borderRadius: AppStyles.borderRadiusM,
                  borderSide: const BorderSide(color: AppStyles.borderLight)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: AppStyles.borderRadiusM,
                  borderSide: const BorderSide(color: AppStyles.borderLight)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: AppStyles.borderRadiusM,
                  borderSide: const BorderSide(color: AppStyles.primaryPurple, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? AppStyles.primaryPurple : AppStyles.lightGray,
                    borderRadius: AppStyles.borderRadiusM,
                    border: Border.all(color: sel ? AppStyles.primaryPurple : AppStyles.borderLight),
                  ),
                  child: Text(d,
                      style: TextStyle(
                          color: sel ? Colors.white : AppStyles.darkGray,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              );
            }).toList(),
          ),
          
          _label('CLASS START TIME'),
          Material(
            color: AppStyles.lightGray,
            borderRadius: AppStyles.borderRadiusM,
            child: InkWell(
              borderRadius: AppStyles.borderRadiusM,
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _startTime,
                  builder: (context, child) => Theme(
                    data: ThemeData.light().copyWith(
                      colorScheme: const ColorScheme.light(primary: AppStyles.primaryPurple),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  setState(() => _startTime = picked);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: AppStyles.borderLight),
                  borderRadius: AppStyles.borderRadiusM,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_rounded, color: AppStyles.primaryPurple, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      _formatTimeOfDay(_startTime),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppStyles.textPrimary),
                    ),
                    const Spacer(),
                    const Icon(Icons.edit_rounded, color: AppStyles.darkGray, size: 16),
                  ],
                ),
              ),
            ),
          ),

          _label('CLASS DURATION'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._standardDurations.map((mins) {
                  final sel = _durationMinutes == mins;
                  return GestureDetector(
                    onTap: () => setState(() => _durationMinutes = mins),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 110),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? AppStyles.primaryPurple : AppStyles.lightGray,
                        borderRadius: AppStyles.borderRadiusM,
                        border: Border.all(color: sel ? AppStyles.primaryPurple : AppStyles.borderLight),
                      ),
                      child: Text('$mins min',
                          style: TextStyle(
                              color: sel ? Colors.white : AppStyles.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ),
                  );
                }),
                Builder(
                  builder: (context) {
                    final isCustom = !_standardDurations.contains(_durationMinutes);
                    return GestureDetector(
                      onTap: _showCustomDurationDialog,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 110),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isCustom ? AppStyles.primaryPurple : AppStyles.lightGray,
                          borderRadius: AppStyles.borderRadiusM,
                          border: Border.all(
                            color: isCustom ? AppStyles.primaryPurple : AppStyles.borderLight,
                            strokeAlign: BorderSide.strokeAlignInside,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(isCustom ? '$_durationMinutes min' : 'Other...',
                                style: TextStyle(
                                    color: isCustom ? Colors.white : AppStyles.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            if (!isCustom) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.edit_rounded, size: 13, color: AppStyles.darkGray),
                            ]
                          ],
                        ),
                      ),
                    );
                  }
                ),
              ],
            ),
          ),

          _label('REMINDER BEFORE CLASS'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._standardReminders.map((mins) {
                  final sel = _selReminderMins == mins;
                  return GestureDetector(
                    onTap: () => setState(() => _selReminderMins = mins),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 110),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? AppStyles.primaryPurple : AppStyles.lightGray,
                        borderRadius: AppStyles.borderRadiusM,
                        border: Border.all(color: sel ? AppStyles.primaryPurple : AppStyles.borderLight),
                      ),
                      child: Text('${mins}min',
                          style: TextStyle(
                              color: sel ? Colors.white : AppStyles.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ),
                  );
                }),
                Builder(
                  builder: (context) {
                    final isCustom = !_standardReminders.contains(_selReminderMins);
                    return GestureDetector(
                      onTap: _showCustomReminderDialog,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 110),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isCustom ? AppStyles.primaryPurple : AppStyles.lightGray,
                          borderRadius: AppStyles.borderRadiusM,
                          border: Border.all(
                            color: isCustom ? AppStyles.primaryPurple : AppStyles.borderLight,
                            strokeAlign: BorderSide.strokeAlignInside,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(isCustom ? '${_selReminderMins}min' : 'Other...',
                                style: TextStyle(
                                    color: isCustom ? Colors.white : AppStyles.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            if (!isCustom) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.edit_rounded, size: 13, color: AppStyles.darkGray),
                            ]
                          ],
                        ),
                      ),
                    );
                  }
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppStyles.mediumGray,
                borderRadius: AppStyles.borderRadiusXL,
                border: Border.all(color: AppStyles.primaryPurple.withOpacity(0.3)),
              ),
              child: Text(
                '${_selDays.isEmpty ? "No days" : _selDays.join(", ")}  ·  '
                '${_formatTimeOfDay(_startTime)} → ${_formatTimeOfDay(endT)}',
                style: const TextStyle(
                    color: AppStyles.primaryPurple,
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
                color: AppStyles.warning.withOpacity(0.15),
                borderRadius: AppStyles.borderRadiusM,
                border: Border.all(color: AppStyles.warning.withOpacity(0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, size: 15, color: AppStyles.warning),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(_error!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppStyles.warning,
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
                backgroundColor: AppStyles.primaryPurple,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      widget.editing != null ? 'Save Changes' : 'Create Section',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
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

  String _stripSeconds(String time) {
    return time.replaceAllMapped(RegExp(r'(:[0-9]{2}):[0-9]{2}'), (match) => match.group(1)!);
  }

  @override
  Widget build(BuildContext context) {
    final sch = section.schedule;
    final activeDays = sch.days.toSet();
    
    final cleanStart = _stripSeconds(sch.startTime.trim());
    final rawEnd = _stripSeconds(sch.endTime.trim());
    
    final endDisplay = (rawEnd.isEmpty ||
            rawEnd == sch.timezone ||
            rawEnd.toUpperCase() == 'UTC')
        ? ''
        : rawEnd;
    final hasTime = cleanStart.isNotEmpty;
    final timeString = hasTime
        ? (endDisplay.isNotEmpty
            ? '$cleanStart – $endDisplay'
            : cleanStart)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: AppStyles.white,
        borderRadius: AppStyles.borderRadiusL,
        boxShadow: AppStyles.shadowMedium,
        border: Border.all(color: AppStyles.borderLight),
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
                    colors: [AppStyles.primaryPurple, Color(0xFF9B78E0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: AppStyles.borderRadiusM,
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
                          color: AppStyles.textPrimary,
                          letterSpacing: -0.3,
                          height: 1.2),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(children: [
                      _Badge(
                          label: 'Section',
                          color: AppStyles.primaryPurple,
                          bgColor: AppStyles.mediumGray),
                      if (section.location.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _Badge(
                            icon: Icons.location_on_rounded,
                            label: section.location,
                            color: AppStyles.accent,
                            bgColor: AppStyles.accent.withOpacity(0.15)),
                      ],
                    ]),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppStyles.darkGray, size: 20),
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
                          color: AppStyles.primaryPurple, size: 17),
                      SizedBox(width: 10),
                      Text('Edit Section',
                          style: TextStyle(
                              color: AppStyles.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ]),
                  ),
                  const PopupMenuDivider(height: 1),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: const [
                      Icon(Icons.delete_outline_rounded,
                          color: AppStyles.error, size: 17),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppStyles.lightGray,
              borderRadius: AppStyles.borderRadiusM,
              border: Border.all(color: AppStyles.borderLight),
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
                        color: active ? AppStyles.primaryPurple : AppStyles.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: active ? AppStyles.primaryPurple : AppStyles.borderLight,
                          width: active ? 0 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(d.substring(0, 1),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: active ? Colors.white : AppStyles.darkGray,
                              letterSpacing: 0.2)),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 36, color: AppStyles.borderLight),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.schedule_rounded,
                        size: 11,
                        color:
                            hasTime ? AppStyles.primaryPurple : AppStyles.darkGray),
                    const SizedBox(width: 4),
                    Text('TIME',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: hasTime
                                ? AppStyles.primaryPurple
                                : AppStyles.darkGray,
                            letterSpacing: 0.9)),
                  ]),
                  const SizedBox(height: 5),
                  Text(timeString ?? '—',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: hasTime ? AppStyles.textPrimary : AppStyles.darkGray,
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

// ─── Badge Chip ───────────────────────────────────────────────────────────────
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
        decoration: BoxDecoration(color: bgColor, borderRadius: AppStyles.borderRadiusS),
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
class StudentsTab extends StatelessWidget {
  const StudentsTab(
      {super.key, required this.ws, required this.vm, required this.onError});
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
            style: TextStyle(fontSize: 12, color: AppStyles.darkGray)),
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
                child: SectionRosterCard(
                    section: s, ws: ws, vm: vm, onError: onError),
              )),
      ],
    );
  }
}

// ─── Section Roster Card ──────────────────────────────────────────────────────
class SectionRosterCard extends StatefulWidget {
  const SectionRosterCard(
      {super.key,
      required this.section,
      required this.ws,
      required this.vm,
      required this.onError});
  final Section section;
  final Workspace ws;
  final WorkspacesViewModel vm;
  final void Function(String) onError;

  @override
  State<SectionRosterCard> createState() => _SectionRosterCardState();
}

class _SectionRosterCardState extends State<SectionRosterCard> {
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

  String _stripSeconds(String time) {
    return time.replaceAllMapped(RegExp(r'(:[0-9]{2}):[0-9]{2}'), (match) => match.group(1)!);
  }

  Future<void> _loadRoster() async {
    setState(() => _loadingRoster = true);
    try {
      final list = await widget.vm.api
          .listSectionStudents(widget.ws.id.toString(), widget.section.id);
      if (mounted) {
        setState(() {
          _students = list;
          _loadingRoster = false;
        });
      }
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
            builder: (_) => ReplaceRosterDialog(
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
        workspaceId: widget.ws.id.toString(),
        sectionId: widget.section.id,
        bytes: bytes,
        filename: f.name,
      );
      widget.vm.recordImport(widget.section.id, result.imported);
      await _loadRoster();
      widget.vm.api.getWorkspace(widget.ws.id.toString()).then((fresh) {
        widget.vm.current = fresh;
      }).catchError((_) {});
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(result.imported > 0
              ? '✓ ${result.imported} student${result.imported == 1 ? "" : "s"} imported successfully'
              : 'No students found — check your file has name/email columns'),
          backgroundColor:
              result.imported > 0 ? AppStyles.accent : AppStyles.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
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
    
    final cleanStart = _stripSeconds(sch.startTime.trim());
    final rawEnd = _stripSeconds(sch.endTime.trim());
    
    final endDisplay = (rawEnd.isEmpty ||
            rawEnd == sch.timezone ||
            rawEnd.toUpperCase() == 'UTC')
        ? ''
        : rawEnd;
        
    final time = cleanStart.isNotEmpty
        ? (endDisplay.isNotEmpty
            ? '$cleanStart – $endDisplay'
            : cleanStart)
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
        color: AppStyles.white,
        borderRadius: AppStyles.borderRadiusL,
        boxShadow: AppStyles.shadowLight,
        border: Border.all(
          color:
              _expanded ? AppStyles.primaryPurple.withOpacity(0.4) : AppStyles.borderLight,
          width: _expanded ? 1.5 : 1,
        ),
      ),
      child: Column(children: [
        ClipRRect(
          borderRadius: _expanded
              ? const BorderRadius.vertical(top: Radius.circular(16))
              : AppStyles.borderRadiusL,
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
                            ? AppStyles.accent.withOpacity(0.15)
                            : AppStyles.mediumGray,
                        borderRadius: AppStyles.borderRadiusM,
                        border: Border.all(
                          color: (hasStudents
                                  ? AppStyles.accent
                                  : AppStyles.primaryPurple)
                              .withOpacity(0.18),
                        ),
                      ),
                      child: Icon(Icons.groups_2_rounded,
                          color: hasStudents
                              ? AppStyles.accent
                              : AppStyles.primaryPurple,
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
                                color: AppStyles.textPrimary,
                                letterSpacing: -0.2),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (days.isNotEmpty || time.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(children: [
                              if (days.isNotEmpty) ...[
                                const Icon(Icons.calendar_today_rounded,
                                    size: 10, color: AppStyles.darkGray),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(days,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppStyles.darkGray,
                                          fontWeight: FontWeight.w500)),
                                ),
                              ],
                              if (days.isNotEmpty && time.isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 5),
                                  child: Text('·',
                                      style: TextStyle(
                                          color: AppStyles.darkGray,
                                          fontSize: 11)),
                                ),
                              if (time.isNotEmpty) ...[
                                const Icon(Icons.schedule_rounded,
                                    size: 10, color: AppStyles.darkGray),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(time,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppStyles.darkGray,
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
                            ? AppStyles.accent.withOpacity(0.15)
                            : AppStyles.lightGray,
                        borderRadius: AppStyles.borderRadiusXL,
                        border: Border.all(
                          color: hasStudents
                              ? AppStyles.accent.withOpacity(0.3)
                              : AppStyles.borderLight,
                        ),
                      ),
                      child: _importing
                          ? const SizedBox(
                              width: 36,
                              height: 11,
                              child: LinearProgressIndicator(
                                  color: AppStyles.accent,
                                  backgroundColor: AppStyles.mediumGray),
                            )
                          : Text(
                              '$count student${count == 1 ? "" : "s"}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: hasStudents
                                      ? AppStyles.accent
                                      : AppStyles.darkGray),
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
                              ? AppStyles.mediumGray
                              : AppStyles.lightGray,
                          borderRadius: AppStyles.borderRadiusS,
                        ),
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            color: _expanded
                                ? AppStyles.primaryPurple
                                : AppStyles.darkGray,
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
                  const Divider(height: 1, color: AppStyles.borderLight),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                          child: Material(
                            color: _importing
                                ? AppStyles.lightGray
                                : AppStyles.mediumGray,
                            borderRadius: AppStyles.borderRadiusM,
                            child: InkWell(
                              onTap: _importing ? null : () => _import(context),
                              borderRadius: AppStyles.borderRadiusM,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  borderRadius: AppStyles.borderRadiusM,
                                  border: Border.all(
                                    color: _importing
                                        ? AppStyles.borderLight
                                        : AppStyles.primaryPurple.withOpacity(0.3),
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
                                                color: AppStyles.primaryPurple),
                                          )
                                        : const Icon(Icons.upload_file_rounded,
                                            size: 14, color: AppStyles.primaryPurple),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        _importing ? 'Importing…' : 'Import',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _importing
                                              ? AppStyles.darkGray
                                              : AppStyles.primaryPurple,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),
                      if (_loadingRoster)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: AppStyles.primaryPurple, strokeWidth: 2)),
                        )
                      else if (_students.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Column(children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                  color: AppStyles.lightGray,
                                  borderRadius: AppStyles.borderRadiusM),
                              child: const Icon(Icons.people_outline_rounded,
                                  color: AppStyles.darkGray, size: 24),
                            ),
                            const SizedBox(height: 10),
                            const Text('No students imported yet',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: AppStyles.darkGray)),
                            const SizedBox(height: 4),
                            const Text(
                                'Upload a CSV/XLSX with name, email, student_no columns.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppStyles.darkGray,
                                    height: 1.4)),
                          ]),
                        )
                      else ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _search = v),
                          style: const TextStyle(
                              fontSize: 13, color: AppStyles.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Search students…',
                            hintStyle: const TextStyle(
                                color: AppStyles.darkGray, fontSize: 12),
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: AppStyles.darkGray, size: 18),
                            suffixIcon: _search.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded,
                                        color: AppStyles.darkGray, size: 16),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _search = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AppStyles.lightGray,
                            border: OutlineInputBorder(
                                borderRadius: AppStyles.borderRadiusM,
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
                            return Container(
                              color: i.isEven
                                  ? Colors.transparent
                                  : AppStyles.lightGray.withOpacity(0.45),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 9),
                              child: Row(children: [
                                SizedBox(
                                  width: 28,
                                  child: Text('${i + 1}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppStyles.darkGray,
                                          fontWeight: FontWeight.w600)),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(s.name.isEmpty ? '—' : s.name,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppStyles.textPrimary,
                                          fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(s.email.isEmpty ? '—' : s.email,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppStyles.darkGray),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                SizedBox(
                                  width: 56,
                                  child: Text(
                                      s.studentNo.isEmpty ? '—' : s.studentNo,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppStyles.darkGray),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ]),
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
                                fontSize: 11, color: AppStyles.darkGray),
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

// ─── Replace Roster Dialog ────────────────────────────────────────────────────
class ReplaceRosterDialog extends StatelessWidget {
  const ReplaceRosterDialog({
    super.key,
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

// ─── Shared Widgets (used only within sections/students) ─────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.title, required this.icon, this.trailing});
  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: AppStyles.primaryPurple, size: 17),
        const SizedBox(width: 7),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppStyles.textPrimary)),
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
        color: AppStyles.primaryPurple,
        borderRadius: AppStyles.borderRadiusXL,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppStyles.borderRadiusXL,
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
              decoration: BoxDecoration(
                  color: AppStyles.mediumGray, borderRadius: AppStyles.borderRadiusXL),
              child: Icon(icon, color: AppStyles.primaryPurple, size: 34),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppStyles.textPrimary)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppStyles.darkGray, fontSize: 13, height: 1.5)),
          ]),
        ),
      );
}