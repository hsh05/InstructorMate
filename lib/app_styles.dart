import 'package:flutter/material.dart';

// This class holds ALL styling constants for the app
// Using a class with static members follows the "Constants" pattern in OOP
class AppStyles {
  // Private constructor prevents instantiation
  // We don't need to create objects of this class
  AppStyles._();

  // ==================== COLORS ====================
  
  // Primary Colors
  static const Color primaryPurple = Color(0xFF667eea);
  static const Color primaryDeepPurple = Color(0xFF764ba2);
  static const Color primaryPink = Color(0xFFF093fb);
  
  // Neutral Colors
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static final Color lightGray = Colors.grey[50]!;
  static final Color mediumGray = Colors.grey[200]!;
  static final Color darkGray = Colors.grey[600]!;
  
  // Semantic Colors (meaning-based)
  static const Color success = Colors.green;
  static const Color error = Colors.red;
  static const Color warning = Colors.orange;
  
  // ==================== GRADIENTS ====================
  
  // Background gradient
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      primaryPurple,
      primaryDeepPurple,
      primaryPink,
    ],
  );
  
  // Button gradient
  static const LinearGradient buttonGradient = LinearGradient(
    colors: [
      primaryPurple,
      primaryDeepPurple,
    ],
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
  static final TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    color: darkGray,
  );
  
  static final TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    color: darkGray,
  );
  
  static final TextStyle bodySmall = TextStyle(
    fontSize: 12,
    color: mediumGray,
  );
  
  // Special text styles
  static final TextStyle subtitleWhite = TextStyle(
    fontSize: 14,
    color: white.withAlpha((0.9 * 255).round()),
  );
  
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
  
  static final TextStyle labelText = TextStyle(
    color: darkGray,
    fontSize: 16,
  );
  
  // ==================== SPACING ====================
  
  // Padding
  static const double paddingXS = 4.0;
  static const double paddingS = 8.0;
  static const double paddingM = 16.0;
  static const double paddingL = 24.0;
  static const double paddingXL = 32.0;
  static const double paddingXXL = 48.0;
  
  // Gaps (between widgets)
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
  
  // Commonly used BorderRadius objects
  static final BorderRadius borderRadiusS = BorderRadius.circular(radiusS);
  static final BorderRadius borderRadiusM = BorderRadius.circular(radiusM);
  static final BorderRadius borderRadiusL = BorderRadius.circular(radiusL);
  static final BorderRadius borderRadiusXL = BorderRadius.circular(radiusXL);
  
  // ==================== SHADOWS ====================
  
  // Light shadow for subtle elevation
  static final List<BoxShadow> shadowLight = [
    BoxShadow(
      color: const Color.fromRGBO(0, 0, 0, 0.1),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];
  
  // Medium shadow for cards
  static final List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: const Color.fromRGBO(0, 0, 0, 0.1),
      blurRadius: 30,
      offset: const Offset(0, 10),
    ),
  ];
  
  // Strong shadow for important elements
  static final List<BoxShadow> shadowStrong = [
    BoxShadow(
      color: const Color.fromRGBO(0, 0, 0, 0.2),
      blurRadius: 20,
      offset: const Offset(0, 10),
    ),
  ];
  
  // Colored shadow for buttons
  static final List<BoxShadow> shadowButton = [
    BoxShadow(
      color: primaryPurple.withAlpha((0.3 * 255).round()),
      blurRadius: 15,
      offset: const Offset(0, 8),
    ),
  ];
  
  // ==================== DIMENSIONS ====================
  
  // Icon sizes
  static const double iconS = 20.0;
  static const double iconM = 24.0;
  static const double iconL = 32.0;
  static const double iconXL = 60.0;
  
  // Button heights
  static const double buttonHeightS = 40.0;
  static const double buttonHeightM = 48.0;
  static const double buttonHeightL = 56.0;
  
  // Input field heights
  static const double inputHeight = 56.0;
  
  // Logo container size
  static const double logoContainerSize = 100.0;
  static const double logoPadding = 20.0;
  
  // ==================== DECORATION HELPERS ====================
  
  // Helper method to create input decoration
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
          color: iconColor.withAlpha((0.1 * 255).round()),
          borderRadius: borderRadiusM,
        ),
        child: Icon(
          icon,
          color: iconColor,
          size: iconM,
        ),
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
        borderSide: BorderSide(color: mediumGray),
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
  
  // Helper method for card decoration
  static final BoxDecoration cardDecoration = BoxDecoration(
    color: white,
    borderRadius: borderRadiusXL,
    boxShadow: shadowMedium,
  );
  
  // Helper method for logo container decoration
  static final BoxDecoration logoDecoration = BoxDecoration(
    color: white,
    shape: BoxShape.circle,
    boxShadow: shadowStrong,
  );
  
  // Helper method for button decoration
  static final BoxDecoration buttonDecoration = BoxDecoration(
    gradient: buttonGradient,
    borderRadius: borderRadiusL,
    boxShadow: shadowButton,
  );
  // EdgeInsets wrappers for padding
static final EdgeInsets paddingMedium = EdgeInsets.all(paddingM);
static final EdgeInsets paddingLarge = EdgeInsets.all(paddingL);

// Spacing constants for SizedBox
static const double spacingS = gapS;
static const double spacingM = gapM;
static const double spacingL = gapL;
static const double spacingXL = gapXL;
static const double spacingHuge = gapHuge;

// Icon sizes
static const double iconSizeMedium = iconM;
static const double iconSizeLarge = iconXL;

// Gradient decoration for Container backgrounds
static final BoxDecoration backgroundGradientDecoration = BoxDecoration(
  gradient: backgroundGradient,
);

// Button height
static const double buttonHeight = buttonHeightL;

// ElevatedButton style
static final ButtonStyle elevatedButtonStyle = ElevatedButton.styleFrom(
  backgroundColor: Colors.transparent,
  shadowColor: Colors.transparent,
  shape: RoundedRectangleBorder(borderRadius: borderRadiusL),
);

// Loading indicator constants
static const double loadingIndicatorSize = 24.0;
static const double loadingIndicatorStrokeWidth = 3.0;
}