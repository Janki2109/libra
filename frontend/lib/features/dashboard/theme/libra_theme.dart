import 'package:flutter/material.dart';

/// Shared design tokens for the Lawyer panel's premium light theme —
/// deep navy/purple branding with gold accents, per the reference design.
/// Every lawyer screen should import this instead of declaring its own
/// local color constants, so the whole panel reads as one product.
class LibraTheme {
  LibraTheme._();

  // ─── Brand ───────────────────────────────
  static const Color navy = Color(0xFF150E3D);
  static const Color navyDeep = Color(0xFF0B0726);
  static const Color purple = Color(0xFF3D2C8D);
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldLight = Color(0xFFF0CC6C);

  // ─── Supporting palette ──────────────────
  static const Color softBlue = Color(0xFF4A90D9);
  static const Color softGreen = Color(0xFF2E8B57);
  static const Color softOrange = Color(0xFFE07A3F);
  static const Color softLavender = Color(0xFF8B6FD6);
  static const Color softRed = Color(0xFFD9534F);

  // ─── Surfaces ────────────────────────────
  static const Color bg = Color(0xFFF6F5FB);
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF0EEF9);
  static const Color border = Color(0xFFE6E3F4);

  // ─── Text ────────────────────────────────
  static const Color textPrimary = Color(0xFF1B1533);
  static const Color textMuted = Color(0xFF7B7594);

  static const LinearGradient heroGradient = LinearGradient(
    colors: [navyDeep, navy, purple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFC79A2C), gold, goldLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxShadow cardShadow = BoxShadow(
    color: navy.withValues(alpha: 0.06),
    blurRadius: 16,
    offset: const Offset(0, 4),
  );

  static BorderRadius radiusLg = BorderRadius.circular(20);
  static BorderRadius radiusMd = BorderRadius.circular(16);
  static BorderRadius radiusSm = BorderRadius.circular(12);
}
