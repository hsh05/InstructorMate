import 'package:flutter/material.dart';
import 'package:instructor_mate/models/instructor_model.dart';
import 'package:instructor_mate/app_styles.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;
  bool _isSaving = false;

  // Demo data - Replace with actual logged-in user data
  late Instructor _instructor = Instructor(
    id: 'inst_001',
    name: 'Dr. Sarah Johnson',
    email: 'sarah.johnson@university.edu',
    phone: '+1 (555) 123-4567',
    department: 'Computer Science',
    officeLocation: 'Engineering Building, Room 301',
    officeHours: 'Mon-Wed 2:00-4:00 PM',
    bio: 'Professor of Computer Science with 15 years of experience in software engineering and algorithms. Passionate about teaching and mentoring students.',
  );

  // Controllers for editing
  late final _nameCtrl = TextEditingController(text: _instructor.name);
  late final _phoneCtrl = TextEditingController(text: _instructor.phone);
  late final _deptCtrl = TextEditingController(text: _instructor.department);
  late final _officeCtrl = TextEditingController(text: _instructor.officeLocation);
  late final _hoursCtrl = TextEditingController(text: _instructor.officeHours);
  late final _bioCtrl = TextEditingController(text: _instructor.bio);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _deptCtrl.dispose();
    _officeCtrl.dispose();
    _hoursCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _toggleEdit() => setState(() => _isEditing = !_isEditing);

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);

    // Simulate API call
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _instructor = _instructor.copyWith(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        department: _deptCtrl.text.trim(),
        officeLocation: _officeCtrl.text.trim(),
        officeHours: _hoursCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
      );
      _isEditing = false;
      _isSaving = false;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Profile updated successfully!',
        style: AppStyles.bodyMedium.copyWith(color: AppStyles.white),
      ),
      backgroundColor: AppStyles.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppStyles.radiusM)),
    ));
  }

  void _cancelEdit() {
    setState(() {
      _nameCtrl.text = _instructor.name;
      _phoneCtrl.text = _instructor.phone ?? '';
      _deptCtrl.text = _instructor.department ?? '';
      _officeCtrl.text = _instructor.officeLocation ?? '';
      _hoursCtrl.text = _instructor.officeHours ?? '';
      _bioCtrl.text = _instructor.bio ?? '';
      _isEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppStyles.lightGray,
    appBar: AppBar(
      elevation: 0,
      backgroundColor: AppStyles.primaryPurple,
      title: const Text('My Profile', style: TextStyle(color: AppStyles.white, fontWeight: FontWeight.bold)),
      centerTitle: true,
      actions: [
        if (!_isEditing)
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: AppStyles.white),
            onPressed: _toggleEdit,
            tooltip: 'Edit Profile',
          ),
      ],
    ),
    body: SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(),
          _buildContent(),
        ],
      ),
    ),
  );

  Widget _buildHeader() => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: AppStyles.primaryPurple,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppStyles.radiusXL)),
    ),
    padding: EdgeInsets.fromLTRB(
      AppStyles.paddingL,
      AppStyles.paddingM,
      AppStyles.paddingL,
      AppStyles.paddingXL,
    ),
    child: Column(
      children: [
        // Avatar
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppStyles.white,
            shape: BoxShape.circle,
            boxShadow: AppStyles.shadowMedium,
          ),
          child: Center(
            child: Text(
              _instructor.initials,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: AppStyles.primaryPurple,
              ),
            ),
          ),
        ),
        SizedBox(height: AppStyles.spacingM),

        // Name
        if (_isEditing)
          Container(
            constraints: const BoxConstraints(maxWidth: 300),
            child: TextFormField(
              controller: _nameCtrl,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppStyles.white,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppStyles.white.withOpacity(0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppStyles.radiusM),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppStyles.paddingM,
                  vertical: AppStyles.paddingS,
                ),
              ),
            ),
          )
        else
          Text(
            _instructor.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppStyles.white,
            ),
            textAlign: TextAlign.center,
          ),

        SizedBox(height: AppStyles.gapXS),

        // Email (non-editable)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.email_rounded, size: 16, color: AppStyles.white.withOpacity(0.9)),
            SizedBox(width: AppStyles.gapXS),
            Text(
              _instructor.email,
              style: TextStyle(
                fontSize: 14,
                color: AppStyles.white.withOpacity(0.9),
              ),
            ),
          ],
        ),

        SizedBox(height: AppStyles.gapS),

        // Role badge
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppStyles.paddingM,
            vertical: AppStyles.paddingXS,
          ),
          decoration: BoxDecoration(
            color: AppStyles.accent,
            borderRadius: BorderRadius.circular(AppStyles.radiusXL),
          ),
          child: Text(
            _instructor.role,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppStyles.white,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildContent() => Padding(
    padding: AppStyles.paddingLarge,
    child: Column(
      children: [
        _buildSection(
          title: 'Contact Information',
          icon: Icons.contact_phone_rounded,
          children: [
            _buildField(
              label: 'Phone',
              icon: Icons.phone_rounded,
              controller: _phoneCtrl,
              value: _instructor.phone,
            ),
            SizedBox(height: AppStyles.spacingM),
            _buildField(
              label: 'Department',
              icon: Icons.business_rounded,
              controller: _deptCtrl,
              value: _instructor.department,
            ),
          ],
        ),

        SizedBox(height: AppStyles.spacingL),

        _buildSection(
          title: 'Office Details',
          icon: Icons.location_on_rounded,
          children: [
            _buildField(
              label: 'Office Location',
              icon: Icons.room_rounded,
              controller: _officeCtrl,
              value: _instructor.officeLocation,
              maxLines: 2,
            ),
            SizedBox(height: AppStyles.spacingM),
            _buildField(
              label: 'Office Hours',
              icon: Icons.access_time_rounded,
              controller: _hoursCtrl,
              value: _instructor.officeHours,
              maxLines: 2,
            ),
          ],
        ),

        SizedBox(height: AppStyles.spacingL),

        _buildSection(
          title: 'About',
          icon: Icons.info_rounded,
          children: [
            _buildField(
              label: 'Bio',
              icon: Icons.article_rounded,
              controller: _bioCtrl,
              value: _instructor.bio,
              maxLines: 5,
            ),
          ],
        ),

        if (_isEditing) ...[
          SizedBox(height: AppStyles.spacingXL),
          _buildActionButtons(),
        ],
      ],
    ),
  );

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Container(
    decoration: BoxDecoration(
      color: AppStyles.white,
      borderRadius: BorderRadius.circular(AppStyles.radiusL),
      boxShadow: AppStyles.shadowLight,
    ),
    padding: AppStyles.paddingLarge,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(AppStyles.paddingS),
              decoration: BoxDecoration(
                color: AppStyles.primaryPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppStyles.radiusS),
              ),
              child: Icon(icon, size: AppStyles.iconM, color: AppStyles.primaryPurple),
            ),
            SizedBox(width: AppStyles.gapM),
            Text(title, style: AppStyles.headingSmall),
          ],
        ),
        SizedBox(height: AppStyles.spacingL),
        ...children,
      ],
    ),
  );

  Widget _buildField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    String? value,
    int maxLines = 1,
  }) {
    if (_isEditing) {
      return TextFormField(
        controller: controller,
        maxLines: maxLines,
        style: AppStyles.bodyMedium,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppStyles.labelText,
          prefixIcon: Icon(icon, color: AppStyles.primaryPurple, size: AppStyles.iconM),
          filled: true,
          fillColor: AppStyles.lightGray,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppStyles.radiusM),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppStyles.radiusM),
            borderSide: const BorderSide(color: AppStyles.primaryPurple, width: 2),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppStyles.iconM, color: AppStyles.darkGray),
        SizedBox(width: AppStyles.gapM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppStyles.bodySmall.copyWith(
                  color: AppStyles.darkGray,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: AppStyles.gapXS),
              Text(
                value ?? 'Not set',
                style: AppStyles.bodyMedium.copyWith(
                  color: value != null ? AppStyles.textPrimary : AppStyles.darkGray,
                  fontStyle: value != null ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _isSaving ? null : _cancelEdit,
          icon: const Icon(Icons.close_rounded),
          label: const Text('Cancel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppStyles.darkGray,
            side: BorderSide(color: AppStyles.darkGray),
            padding: EdgeInsets.symmetric(vertical: AppStyles.paddingM),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppStyles.radiusM),
            ),
          ),
        ),
      ),
      SizedBox(width: AppStyles.gapM),
      Expanded(
        child: Container(
          decoration: AppStyles.buttonDecoration,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveProfile,
            style: AppStyles.elevatedButtonStyle,
            icon: _isSaving
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppStyles.white),
                  ),
                )
              : const Icon(Icons.check_rounded),
            label: Text(
              _isSaving ? 'Saving...' : 'Save',
              style: AppStyles.buttonText.copyWith(fontSize: 16),
            ),
          ),
        ),
      ),
    ],
  );
}