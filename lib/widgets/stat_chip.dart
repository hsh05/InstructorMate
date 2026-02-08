import 'package:flutter/material.dart';
import 'package:instructor_mate/app_styles.dart';

class StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;

  const StatChip({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: AppStyles.paddingS,
      vertical: AppStyles.paddingXS,
    ),
    decoration: BoxDecoration(
      color: AppStyles.lightGray,
      borderRadius: AppStyles.borderRadiusS,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: AppStyles.iconS,
          color: iconColor ?? AppStyles.darkGray,
        ),
        SizedBox(width: AppStyles.gapXS),
        Text(
          label,
          style: AppStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: AppStyles.darkGray,
          ),
        ),
      ],
    ),
  );
}