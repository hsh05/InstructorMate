import 'package:flutter/material.dart';
import '../app_styles.dart';
import '../models/instructor_model.dart';

class ProfileHeaderCard extends StatelessWidget {
  final Instructor profile;
  const ProfileHeaderCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          vertical: AppStyles.paddingXL, horizontal: AppStyles.paddingL),
      decoration: BoxDecoration(
        gradient: AppStyles.backgroundGradient,
        borderRadius: AppStyles.borderRadiusXL,
        boxShadow: AppStyles.shadowButton,
      ),
      child: Column(children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: AppStyles.white.withOpacity(0.2),
          // 👉 THE FIX: Using the computed initials property from our new model!
          child: Text(
            profile.initials, 
            style: AppStyles.headingLarge,
          ),
        ),
        const SizedBox(height: AppStyles.gapM),
        
        // 👉 THE FIX: Replaced fullName with name
        Text(profile.name,
            style: AppStyles.headingSmall.copyWith(color: AppStyles.white)),
            
        const SizedBox(height: AppStyles.gapXS),
        Text(profile.email, style: AppStyles.subtitleWhite),
        
        if (profile.jobTitle != null && profile.jobTitle!.isNotEmpty) ...[
          const SizedBox(height: AppStyles.gapS),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppStyles.paddingM, vertical: AppStyles.paddingXS),
            decoration: BoxDecoration(
              color: AppStyles.white.withOpacity(0.15),
              borderRadius: AppStyles.borderRadiusL,
            ),
            child: Text(profile.jobTitle!, style: AppStyles.subtitleWhite),
          ),
        ],
      ]),
    );
  }
}