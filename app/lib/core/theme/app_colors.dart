import 'package:flutter/material.dart';

/// Premium design tokens shared across the app.
class AppColors {
  AppColors._();

  static const Color indigo = Color(0xFF6366F1);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color emerald = Color(0xFF10B981);

  static const Color lightBackground = Color(0xFFF4F6FF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFEEF1FF);

  static const Color darkBackground = Color(0xFF0C0E14);
  static const Color darkSurface = Color(0xFF161822);
  static const Color darkSurfaceVariant = Color(0xFF1E2130);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigo, violet],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, indigo],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4338CA), Color(0xFF7C3AED), Color(0xFF06B6D4)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient detectionBoxGradient = LinearGradient(
    colors: [cyan, violet, indigo],
  );

  static Color detectionBoxColor(double confidence) {
    if (confidence >= 0.75) return emerald;
    if (confidence >= 0.5) return cyan;
    return const Color(0xFFF59E0B);
  }
}
