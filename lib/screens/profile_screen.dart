// lib/screens/profile_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_styles.dart';
import '../models/instructor_model.dart';
import '../models/workspace_model.dart';
import '../services/auth_service.dart';
import '../widgets/profile_header_card.dart';
import '../widgets/profile_section.dart';
import '../state/workspaces_vm.dart'; 
import '../services/notifications/notification_scheduler.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Instructor? _profile;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;
  String? _error;

  late TextEditingController _fullNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _universityCtrl;
  late TextEditingController _collegeCtrl;
  late TextEditingController _departmentCtrl;
  late TextEditingController _jobTitleCtrl;
  late TextEditingController _officeCtrl;

  // 👉 NEW: Notification Preference State
  String _selectedDay = 'Monday';
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);
  final List<String> _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _universityCtrl.dispose();
    _collegeCtrl.dispose();
    _departmentCtrl.dispose();
    _jobTitleCtrl.dispose();
    _officeCtrl.dispose();
    super.dispose();
  }

  void _syncControllers(Instructor p) {
    _fullNameCtrl = TextEditingController(text: p.name);
    _phoneCtrl = TextEditingController(text: p.phone ?? '');
    _universityCtrl = TextEditingController(text: p.universityName ?? '');
    _collegeCtrl = TextEditingController(text: p.college ?? '');
    _departmentCtrl = TextEditingController(text: p.department ?? '');
    _jobTitleCtrl = TextEditingController(text: p.jobTitle ?? '');
    _officeCtrl = TextEditingController(text: p.officeLocation ?? '');
  }

  // 👉 NEW: Load preferences from secure storage locally
  Future<void> _loadPreferences() async {
    final day = await _storage.read(key: 'overview_day');
    final hourStr = await _storage.read(key: 'overview_hour');
    final minStr = await _storage.read(key: 'overview_minute');

    if (day != null && _days.contains(day)) {
      _selectedDay = day;
    }
    if (hourStr != null && minStr != null) {
      _selectedTime = TimeOfDay(
        hour: int.tryParse(hourStr) ?? 8, 
        minute: int.tryParse(minStr) ?? 0
      );
    }
  }

  Future<void> _loadProfile() async {
    try {
      await _loadPreferences(); // Load local notification settings first
      final profile = await AuthService.getProfile(widget.userId);
      setState(() {
        _profile = profile;
        _syncControllers(profile);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      // 1. Save standard profile data to backend
      final updated = await AuthService.updateProfile(widget.userId, {
        'full_name': _fullNameCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'university_name': _universityCtrl.text.trim(),
        'college': _collegeCtrl.text.trim(),
        'department': _departmentCtrl.text.trim(),
        'job_title': _jobTitleCtrl.text.trim(),
        'office_number': _officeCtrl.text.trim(),
      });
      
      // 2. Save notification preferences locally
      await _storage.write(key: 'overview_day', value: _selectedDay);
      await _storage.write(key: 'overview_hour', value: _selectedTime.hour.toString());
      await _storage.write(key: 'overview_minute', value: _selectedTime.minute.toString());

      // 3. Trigger dart scheduler
      if (mounted) {
        final vm = Provider.of<WorkspacesViewModel>(context, listen: false);
        final api = ApiService(); 
        
        List<Workspace> fullWorkspaces = [];
        
        // Fetch the full workspace object for each summary so we have access to the JSON fields
        for (final summary in vm.workspaces) {
          try {
            final fullWs = await api.getWorkspace(summary.id.toString());
            fullWorkspaces.add(fullWs);
          } catch (e) {
            debugPrint('Failed to load workspace for scheduler: $e');
          }
        }

        await NotificationScheduler.scheduleWeeklyOverviews(
          workspaces: fullWorkspaces,
          preferredDay: _selectedDay,
          hour: _selectedTime.hour,
          minute: _selectedTime.minute,
        );
      }

      setState(() {
        _profile = updated;
        _isEditing = false;
        _isSaving = false;
      });
      _showSnackbar('Profile & Settings updated', AppStyles.success);
    } catch (e) {
      setState(() => _isSaving = false);
      _showSnackbar('Failed to save: $e', AppStyles.error);
    }
  }

  void _cancelEdit() {
    _syncControllers(_profile!);
    _loadPreferences(); // Re-sync local dropdowns to what was previously saved
    setState(() => _isEditing = false);
  }

  void _showSnackbar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppStyles.borderRadiusM),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.lightGray,
      appBar: AppBar(
        title: const Text('My Profile'),
        titleTextStyle: AppStyles.headingSmall,
        backgroundColor: AppStyles.white,
        foregroundColor: AppStyles.primary,
        elevation: 0,
        actions: [
          if (!_isLoading && _error == null)
            _isEditing ? _buildEditActions() : _buildEditButton(),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppStyles.primary))
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildEditButton() => IconButton(
        icon: const Icon(Icons.edit_outlined),
        color: AppStyles.primary,
        onPressed: () => setState(() => _isEditing = true),
      );

  Widget _buildEditActions() => Row(children: [
        TextButton(
          onPressed: _cancelEdit,
          child: Text('Cancel',
              style: AppStyles.bodyMedium.copyWith(color: AppStyles.darkGray)),
        ),
        TextButton(
          onPressed: _isSaving ? null : _saveProfile,
          child: _isSaving
              ? const SizedBox(
                  width: AppStyles.loadingIndicatorSize,
                  height: AppStyles.loadingIndicatorSize,
                  child: CircularProgressIndicator(
                    strokeWidth: AppStyles.loadingIndicatorStrokeWidth,
                    color: AppStyles.primary,
                  ),
                )
              : Text('Save',
                  style: AppStyles.bodyMedium.copyWith(
                      color: AppStyles.primary,
                      fontWeight: FontWeight.bold)),
        ),
      ]);

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppStyles.paddingXL),
          child:
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline,
                size: AppStyles.iconXL, color: AppStyles.error),
            const SizedBox(height: AppStyles.gapL),
            Text(_error!,
                textAlign: TextAlign.center,
                style: AppStyles.bodyMedium.copyWith(color: AppStyles.error)),
            const SizedBox(height: AppStyles.gapXXL),
            Container(
              decoration: AppStyles.buttonDecoration,
              child: ElevatedButton(
                onPressed: _loadProfile,
                style: AppStyles.elevatedButtonStyle,
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: AppStyles.paddingL,
                      vertical: AppStyles.paddingM),
                  child: Text('Retry', style: AppStyles.buttonText),
                ),
              ),
            ),
          ]),
        ),
      );

  Widget _buildBody() => SingleChildScrollView(
        padding: const EdgeInsets.all(AppStyles.paddingL),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProfileHeaderCard(profile: _profile!),
          const SizedBox(height: AppStyles.gapXXL),
          
          ProfileSection(
            title: 'Personal Information',
            isEditing: _isEditing,
            fields: [
              ProfileFieldData(
                  label: 'Full Name',
                  controller: _fullNameCtrl,
                  icon: Icons.person_outline),
              ProfileFieldData(
                  label: 'Phone Number',
                  controller: _phoneCtrl,
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone),
            ],
          ),
          const SizedBox(height: AppStyles.gapXXL),
          
          ProfileSection(
            title: 'University Details',
            isEditing: _isEditing,
            fields: [
              ProfileFieldData(
                  label: 'University Name',
                  controller: _universityCtrl,
                  icon: Icons.account_balance_outlined),
              ProfileFieldData(
                  label: 'College / Faculty',
                  controller: _collegeCtrl,
                  icon: Icons.school_outlined),
              ProfileFieldData(
                  label: 'Department',
                  controller: _departmentCtrl,
                  icon: Icons.category_outlined),
              ProfileFieldData(
                  label: 'Job Title / Rank',
                  controller: _jobTitleCtrl,
                  icon: Icons.badge_outlined),
              ProfileFieldData(
                  label: 'Office Number',
                  controller: _officeCtrl,
                  icon: Icons.door_back_door_outlined),
            ],
          ),
          const SizedBox(height: AppStyles.gapXXL),

          // 👉 NEW: Notification Preference Section (Raw UI Bypass)
          const Text(
            'Weekly Overview Delivery',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppStyles.primary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: AppStyles.cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Delivery Day', style: TextStyle(fontWeight: FontWeight.w600, color: AppStyles.darkGray)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedDay,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: _days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: _isEditing ? (val) => setState(() => _selectedDay = val!) : null,
                ),
                const SizedBox(height: 16),
                const Text('Delivery Time', style: TextStyle(fontWeight: FontWeight.w600, color: AppStyles.darkGray)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _isEditing ? () async {
                    final time = await showTimePicker(context: context, initialTime: _selectedTime);
                    if (time != null) setState(() => _selectedTime = time);
                  } : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppStyles.borderLight),
                      borderRadius: BorderRadius.circular(4)
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_selectedTime.format(context), style: const TextStyle(fontSize: 16)),
                        const Icon(Icons.access_time_rounded, color: AppStyles.primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppStyles.gapHuge),
        ]),
      );
}