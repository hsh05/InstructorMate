// lib/config/app_colors.dart
//
// Single source of truth for every colour and radius used across the app.
// Previously every file re-declared its own _primary, _red, _ink … constants.
// Now one import replaces all of them.

import 'package:flutter/material.dart';

class AppColors {
  // ── Brand ─────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF7C5CBF);
  static const Color primarySoft = Color(0xFFEDE8FF);
  static const Color primaryDark = Color(0xFF5A3DA0);

  // ── Accent / status ───────────────────────────────────────────────────────
  static const Color accent = Color(0xFF00B896);
  static const Color accentSoft = Color(0xFFE0FAF5);
  static const Color warn = Color(0xFFE8900A);
  static const Color warnSoft = Color(0xFFFFF4E0);
  static const Color red = Color(0xFFD93025);

  // ── Neutrals ──────────────────────────────────────────────────────────────
  static const Color bg = Color(0xFFF5F2FF);
  static const Color bgTop = Color(0xFFEDE8FF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF3F0FF);
  static const Color border = Color(0xFFE8E3F8);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color ink = Color(0xFF2D2640);
  static const Color inkMid = Color(0xFF6B6480);
  static const Color inkLight = Color(0xFFABA6C0);
  static const Color textSecondary = Color(0xFF7B748F);

  // ── Shared border radii ───────────────────────────────────────────────────
  static const BorderRadius r8 = BorderRadius.all(Radius.circular(8));
  static const BorderRadius r10 = BorderRadius.all(Radius.circular(10));
  static const BorderRadius r12 = BorderRadius.all(Radius.circular(12));
  static const BorderRadius r14 = BorderRadius.all(Radius.circular(14));
  static const BorderRadius r16 = BorderRadius.all(Radius.circular(16));
  static const BorderRadius r20 = BorderRadius.all(Radius.circular(20));

  // ── Shared shadows ─────────────────────────────────────────────────────────
  static final List<BoxShadow> shadow = [
    BoxShadow(
      color: primary.withOpacity(0.07),
      blurRadius: 14,
      offset: const Offset(0, 4),
    ),
  ];
  static final List<BoxShadow> shadowSm = [
    BoxShadow(
      color: primary.withOpacity(0.04),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];
}
