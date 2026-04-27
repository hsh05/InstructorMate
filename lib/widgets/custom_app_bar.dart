// lib/widgets/custom_app_bar.dart

import 'package:flutter/material.dart';
import '../app_styles.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBackButton;

  const CustomAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppStyles.white,
      foregroundColor: AppStyles.primary,
      elevation: 0,
      centerTitle: true, // Centers the logo + text combo
      automaticallyImplyLeading: showBackButton,
      
      title: Row(
        mainAxisSize: MainAxisSize.min, // Keeps the row tight in the center
        children: [
          // Your Logo
          Image.asset(
            'assets/images/logo.png', 
            height: 28,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 12), // Spacing between logo and text
          
          // Screen Title
          Text(
            title,
            style: AppStyles.headingSmall.copyWith(color: AppStyles.primary),
          ),
        ],
      ),
      actions: actions,
    );
  }

  // Required by Flutter when creating custom AppBars
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}