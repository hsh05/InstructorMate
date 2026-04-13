import 'package:flutter/material.dart';
import 'package:instructor_mate/app_styles.dart';

// ─── Data class to describe a single field ────────────────────────────────────
class ProfileFieldData {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType keyboardType;

  const ProfileFieldData({
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });
}

// ─── Section card with title + list of fields ─────────────────────────────────
class ProfileSection extends StatelessWidget {
  final String title;
  final List<ProfileFieldData> fields;
  final bool isEditing;

  const ProfileSection({
    super.key,
    required this.title,
    required this.fields,
    required this.isEditing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: AppStyles.bodySmall.copyWith(
            color: AppStyles.primaryPurple,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: AppStyles.gapM),
        Container(
          decoration: AppStyles.cardDecoration,
          child: Column(
            children: [
              for (int i = 0; i < fields.length; i++) ...[
                _ProfileField(data: fields[i], isEditing: isEditing),
                if (i < fields.length - 1)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: AppStyles.borderLight,
                    indent: AppStyles.paddingL + AppStyles.iconM + AppStyles.paddingM,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Single field row ─────────────────────────────────────────────────────────
class _ProfileField extends StatelessWidget {
  final ProfileFieldData data;
  final bool isEditing;

  const _ProfileField({required this.data, required this.isEditing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppStyles.paddingL, vertical: AppStyles.paddingXS),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(AppStyles.paddingS),
          decoration: BoxDecoration(
            color: AppStyles.primaryPurple.withOpacity(0.08),
            borderRadius: AppStyles.borderRadiusM,
          ),
          child: Icon(data.icon, size: AppStyles.iconM, color: AppStyles.primaryPurple),
        ),
        const SizedBox(width: AppStyles.gapM),
        Expanded(
          child: TextField(
            controller: data.controller,
            enabled: isEditing,
            keyboardType: data.keyboardType,
            style: AppStyles.bodyLarge.copyWith(color: AppStyles.textPrimary),
            decoration: InputDecoration(
              labelText: data.label,
              labelStyle: AppStyles.bodySmall,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: AppStyles.paddingM),
            ),
          ),
        ),
        if (isEditing)
          const Icon(Icons.edit_outlined,
              size: AppStyles.iconS, color: AppStyles.borderPurple),
      ]),
    );
  }
}