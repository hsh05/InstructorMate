import 'package:flutter/material.dart';

class AppStyles {
  AppStyles._();

  // ==================== COLORS ====================
  
  // Primary Colors
  static const Color primaryPurple = Color(0xFF7C5CBF);
  static const Color primaryDeepPurple = Color(0xFF7C5CBF);
  static const Color primaryPink = Color(0xFFF093fb);
  static const Color accent = Color(0xFF00B896); // Teal accent for status/actions
  
  // Neutral Colors
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color lightGray = Color(0xFFF5F2FF);      // background
  static const Color mediumGray = Color(0xFFEDE8FF);     // card soft background
  static const Color darkGray = Color(0xFF7B748F);       // secondary text
  static const Color textPrimary = Color(0xFF2D2640);    // primary text on white
  
  // Semantic Colors
  static const Color success = Color(0xFF00B896);  // Teal (matches accent)
  static const Color error = Color(0xFFD93025);
  static const Color warning = Color(0xFFE8900A);
  
  // Border Colors
  static const Color borderLight = Color(0xFFE8E3F8);
  static const Color borderPurple = Color(0xFFBFB0E8);
  
  // Status Badge Colors
  static const Color readyBg = Color(0xFFE0FAF5);
  static const Color readyFg = Color(0xFF007A63);
  static const Color readyDot = Color(0xFF00B896);
  
  static const Color draftBg = Color(0xFFFFF4E0);
  static const Color draftFg = Color(0xFFB36200);
  static const Color draftDot = Color(0xFFE8900A);

  // ==================== GRADIENTS ====================
  
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryPurple, primaryDeepPurple, primaryPink],
  );
  
  // Subtle gradient for workspace backgrounds
  static const LinearGradient backgroundGradientSubtle = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [mediumGray, lightGray],
  );
  
  static const LinearGradient buttonGradient = LinearGradient(
    colors: [primaryPurple, primaryDeepPurple],
  );

  // ==================== TEXT STYLES ====================
  
  // Headings
  static const TextStyle headingLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: white,
    letterSpacing: 1.2,
  );
  
  static const TextStyle headingMedium = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: black,
  );
  
  static const TextStyle headingSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: black,
  );
  
  // Body text
  static const TextStyle bodyLarge = TextStyle(fontSize: 16, color: darkGray);
  static const TextStyle bodyMedium = TextStyle(fontSize: 14, color: darkGray);
  static const TextStyle bodySmall = TextStyle(fontSize: 12, color: darkGray);
  
  // Text on colored backgrounds
  static const TextStyle subtitleWhite = TextStyle(
    fontSize: 14,
    color: Color(0xE6FFFFFF), // 90% opacity white
  );
  
  // Buttons & Links
  static const TextStyle buttonText = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: white,
    letterSpacing: 1.2,
  );
  
  static const TextStyle linkText = TextStyle(
    color: primaryPurple,
    fontWeight: FontWeight.w600,
  );
  
  static const TextStyle labelText = TextStyle(
    color: darkGray,
    fontSize: 16,
  );
  
  // Card titles (for workspace cards, etc.)
  static const TextStyle cardTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );

  // ==================== SPACING ====================
  
  static const double paddingXS = 4.0;
  static const double paddingS = 8.0;
  static const double paddingM = 16.0;
  static const double paddingL = 24.0;
  static const double paddingXL = 32.0;
  static const double paddingXXL = 48.0;
  
  static const double gapXS = 4.0;
  static const double gapS = 8.0;
  static const double gapM = 12.0;
  static const double gapL = 16.0;
  static const double gapXL = 20.0;
  static const double gapXXL = 24.0;
  static const double gapHuge = 40.0;

  // ==================== BORDER RADIUS ====================
  
  static const double radiusS = 8.0;
  static const double radiusM = 10.0;
  static const double radiusL = 15.0;
  static const double radiusXL = 20.0;
  
  static final BorderRadius borderRadiusS = BorderRadius.circular(radiusS);
  static final BorderRadius borderRadiusM = BorderRadius.circular(radiusM);
  static final BorderRadius borderRadiusL = BorderRadius.circular(radiusL);
  static final BorderRadius borderRadiusXL = BorderRadius.circular(radiusXL);

  // ==================== SHADOWS ====================
  
  static final List<BoxShadow> shadowLight = [
    BoxShadow(
      color: Colors.black.withOpacity(0.1),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];
  
  static final List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: Colors.black.withOpacity(0.1),
      blurRadius: 30,
      offset: const Offset(0, 10),
    ),
  ];
  
  static final List<BoxShadow> shadowStrong = [
    BoxShadow(
      color: Colors.black.withOpacity(0.2),
      blurRadius: 20,
      offset: const Offset(0, 10),
    ),
  ];
  
  static final List<BoxShadow> shadowButton = [
    BoxShadow(
      color: primaryPurple.withOpacity(0.3),
      blurRadius: 15,
      offset: const Offset(0, 8),
    ),
  ];

  // ==================== DIMENSIONS ====================
  
  static const double iconS = 20.0;
  static const double iconM = 24.0;
  static const double iconL = 32.0;
  static const double iconXL = 60.0;
  
  static const double buttonHeightS = 40.0;
  static const double buttonHeightM = 48.0;
  static const double buttonHeightL = 56.0;
  
  static const double inputHeight = 56.0;
  static const double logoContainerSize = 100.0;
  static const double logoPadding = 20.0;

  // ==================== DECORATION HELPERS ====================
  
  static InputDecoration inputDecoration({
    required String labelText,
    required IconData icon,
    required Color iconColor,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: AppStyles.labelText,
      prefixIcon: Container(
        margin: const EdgeInsets.all(paddingS),
        padding: const EdgeInsets.all(paddingS),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: borderRadiusM,
        ),
        child: Icon(icon, color: iconColor, size: iconM),
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: lightGray,
      border: OutlineInputBorder(
        borderRadius: borderRadiusL,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadiusL,
        borderSide: const BorderSide(color: mediumGray),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadiusL,
        borderSide: const BorderSide(color: primaryPurple, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: borderRadiusL,
        borderSide: const BorderSide(color: error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: borderRadiusL,
        borderSide: const BorderSide(color: error, width: 2),
      ),
    );
  }
  
  static final BoxDecoration cardDecoration = BoxDecoration(
    color: white,
    borderRadius: borderRadiusXL,
    boxShadow: shadowMedium,
  );
  
  // Workspace card decoration (lighter shadow, border)
  static final BoxDecoration workspaceCardDecoration = BoxDecoration(
    color: white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: borderLight),
  );
  
  static final BoxDecoration logoDecoration = BoxDecoration(
    color: white,
    shape: BoxShape.circle,
    boxShadow: shadowStrong,
  );
  
  static final BoxDecoration buttonDecoration = BoxDecoration(
    gradient: buttonGradient,
    borderRadius: borderRadiusL,
    boxShadow: shadowButton,
  );
  
  static final BoxDecoration backgroundGradientDecoration = BoxDecoration(
    gradient: backgroundGradient,
  );
  
  static final BoxDecoration backgroundGradientSubtleDecoration = BoxDecoration(
    gradient: backgroundGradientSubtle,
  );

  // ==================== WRAPPERS ====================
  
  static final EdgeInsets paddingMedium = const EdgeInsets.all(paddingM);
  static final EdgeInsets paddingLarge = const EdgeInsets.all(paddingL);
  
  static const double spacingS = gapS;
  static const double spacingM = gapM;
  static const double spacingL = gapL;
  static const double spacingXL = gapXL;
  static const double spacingHuge = gapHuge;
  
  static const double iconSizeMedium = iconM;
  static const double iconSizeLarge = iconXL;
  static const double buttonHeight = buttonHeightL;
  
  static final ButtonStyle elevatedButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.transparent,
    shadowColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: borderRadiusL),
  );
  
  static const double loadingIndicatorSize = 24.0;
  static const double loadingIndicatorStrokeWidth = 3.0;
}