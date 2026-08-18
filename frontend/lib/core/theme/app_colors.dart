import 'package:flutter/material.dart';

class AppColors {
  // Brand accent - light blue only
  static const Color accent = Color(0xFF3B82F6);
  static const Color accentDark = Color(0xFF1D4ED8);
  static const Color accentLight = Color(0xFF60A5FA);
  static const Color accentSoft = Color(0xFFEFF6FF);

  static const Color black = Color(0xFF0A0A0A);
  static const Color white = Color(0xFFFFFFFF);

  // Surfaces
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF7F8FA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderStrong = Color(0xFFD1D5DB);

  // Text
  static const Color textPrimary = Color(0xFF0A0A0A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);

  // Status
  static const Color success = Color(0xFF16A34A);
  static const Color error = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);

  // EMG channel palette (8 channels, blue-monochrome ramp for a clean
  // scientific look). Tuned for legibility on a white chart background -
  // the lightest shade in the original ramp (0xFF93C5FD) was nearly
  // invisible there, so it's swapped for a darker navy instead.
  static const List<Color> emgChannels = [
    Color(0xFF1D4ED8),
    Color(0xFF2563EB),
    Color(0xFF3B82F6),
    Color(0xFF60A5FA),
    Color(0xFF1E3A8A),
    Color(0xFF0EA5E9),
    Color(0xFF0284C7),
    Color(0xFF075985),
  ];
}
