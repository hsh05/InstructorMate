import 'package:flutter/material.dart';
import 'package:instructor_mate/app_styles.dart';
import 'package:instructor_mate/models/instructor_profile.dart';
import 'package:instructor_mate/services/profile_service.dart';
import 'package:instructor_mate/widgets/profile_header_card.dart';
import 'package:instructor_mate/widgets/profile_section.dart';

class ProfileScreen extends StatefulWidget {
  final String userId; // UUID
  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  InstructorProfile? _profile;
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

  void _syncControllers(InstructorProfile p) {
    _fullNameCtrl = TextEditingController(text: p.fullName);
    _phoneCtrl = TextEditingController(text: p.phoneNumber ?? '');
    _universityCtrl = TextEditingController(text: p.universityName ?? '');
    _collegeCtrl = TextEditingController(text: p.college ?? '');
    _departmentCtrl = TextEditingController(text: p.department ?? '');
    _jobTitleCtrl = TextEditingController(text: p.jobTitle ?? '');
    _officeCtrl = TextEditingController(text: p.officeNumber ?? '');
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ProfileService.getProfile(widget.userId);
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
      final updated = await ProfileService.updateProfile(widget.userId, {
        'full_name': _fullNameCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'university_name': _universityCtrl.text.trim(),
        'college': _collegeCtrl.text.trim(),
        'department': _departmentCtrl.text.trim(),
        'job_title': _jobTitleCtrl.text.trim(),
        'office_number': _officeCtrl.text.trim(),
      });
      setState(() {
        _profile = updated;
        _isEditing = false;
        _isSaving = false;
      });
      _showSnackbar('Profile updated successfully', AppStyles.success);
    } catch (e) {
      setState(() => _isSaving = false);
      _showSnackbar('Failed to save: $e', AppStyles.error);
    }
  }

  void _cancelEdit() {
    _syncControllers(_profile!);
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
        foregroundColor: AppStyles.primaryPurple,
        elevation: 0,
        actions: [
          if (!_isLoading && _error == null)
            _isEditing ? _buildEditActions() : _buildEditButton(),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppStyles.primaryPurple))
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildEditButton() => IconButton(
        icon: const Icon(Icons.edit_outlined),
        color: AppStyles.primaryPurple,
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
                    color: AppStyles.primaryPurple,
                  ),
                )
              : Text('Save',
                  style: AppStyles.bodyMedium.copyWith(
                      color: AppStyles.primaryPurple,
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
          const SizedBox(height: AppStyles.gapHuge),
        ]),
      );
}