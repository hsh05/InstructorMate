// lib/screens/workspace_sections.dart

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/state/workspaces_vm.dart';
import '../models/workspace_model.dart';
import '../config/app_colors.dart';

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
      builder: (_) => SectionSheetContent(
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

// ─── Section Sheet Content ────────────────────────────────────────────────────
class SectionSheetContent extends StatefulWidget {
  const SectionSheetContent({
    super.key,
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
  State<SectionSheetContent> createState() => _SectionSheetContentState();
}

class _SectionSheetContentState extends State<SectionSheetContent> {
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

  Future<void> _loadRoster() async {
    setState(() => _loadingRoster = true);
    try {
      final list = await widget.vm.api
          .listSectionStudents(widget.ws.id.toString(), widget.section.id);
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
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        _importing ? 'Importing…' : 'Import',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _importing
                                              ? AppColors.inkMid
                                              : AppColors.primary,
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
                            return Container(
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