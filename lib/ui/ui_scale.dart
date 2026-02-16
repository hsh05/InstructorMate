// lib/ui/ui_scale.dart
import 'dart:math' as math;

/// Small helper to keep spacing/typography consistent across breakpoints.
class UiScale {
  UiScale(this.w, this.h);

  final double w;
  final double h;

  // --- breakpoints ---
  bool get isMobile => w < 600;
  bool get isTablet => w >= 600 && w < 1024;
  bool get isDesktop => w >= 1024;

  // --- base scaling ---
  double get _s {
    final shortest = math.min(w, h);
    final t = (shortest / 430).clamp(0.92, 1.18);
    return t.toDouble();
  }

  double px(double v) => (v * _s);

  // --- common layout ---
  double get pagePad => px(isDesktop ? 20 : (isTablet ? 14 : 12));
  double get topPad => px(isDesktop ? 14 : 10);

  double get cardRadius => px(isDesktop ? 22 : 18);
  double get innerRadius => px(16);

  // --- typography ---
  double get title => px(isMobile ? 20 : 22);
  double get body => px(isMobile ? 13.8 : 14.5);
  double get hint => px(13);

  // --- icons ---
  double get icon => px(20);
  double get smallIcon => px(16);

  // --- chips ---
  double get chip => px(12.5);

  // --- message bubbles ---
  double get bubbleRadius => px(18);
  double get bubblePadH => px(14);
  double get bubblePadV => px(12);

  double bubbleMaxWidth(double available, {required bool isUser}) {
    final fraction = isDesktop ? 0.60 : (isTablet ? 0.74 : 0.86);
    final maxW = available * fraction;
    return maxW.clamp(px(220), px(620));
  }

  // --- stepper ---
  double get stepDot => px(18);
}
