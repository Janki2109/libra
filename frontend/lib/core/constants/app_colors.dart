import 'package:flutter/material.dart';

class AppColors {
  // ─── Primary ─────────────────────────────
  static const Color primary = Color(0xFF1A1A2E);
  static const Color primaryDark = Color(0xFF0F0F1A);
  static const Color primaryLight = Color(0xFF16213E);

  // ─── Gold/Accent ─────────────────────────
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldLight = Color(0xFFFFD700);
  static const Color goldDark = Color(0xFFB8860B);

  // ─── Purple ──────────────────────────────
  static const Color purple = Color(0xFF9B59B6);

  // ─── Background (Dark - default) ─────────
  static const Color bg = Color(0xFF0A0A14);
  static const Color bgCard = Color(0xFF12121E);
  static const Color bgCard2 = Color(0xFF1A1A2E);
  static const Color surface = Color(0xFF1E1E30);
  static const Color surfaceLight = Color(0xFF252540);

  // ─── Text ────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0C8);
  static const Color textMuted = Color(0xFF6B6B85);
  static const Color textGold = Color(0xFFD4AF37);

  // ─── Status ──────────────────────────────
  static const Color success = Color(0xFF00C896);
  static const Color error = Color(0xFFFF4757);
  static const Color warning = Color(0xFFFFB347);
  static const Color info = Color(0xFF4A90D9);
  static const Color online = Color(0xFF00C896);
  static const Color offline = Color(0xFF6B6B85);
  static const Color busy = Color(0xFFFF4757);
  static const Color away = Color(0xFFFFB347);

  // ─── Border ──────────────────────────────
  static const Color border = Color(0xFF2A2A40);
  static const Color borderGold = Color(0x33D4AF37);
  static const Color borderLight = Color(0xFF3A3A55);

  // ─── Gradients ───────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFD4AF37), Color(0xFFFFD700), Color(0xFFB8860B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bgGradient = LinearGradient(
    colors: [Color(0xFF0A0A14), Color(0xFF12121E), Color(0xFF1A1A2E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF00C896), Color(0xFF00A878)],
  );
  static const LinearGradient errorGradient = LinearGradient(
    colors: [Color(0xFFFF4757), Color(0xFFCC3344)],
  );
  static const LinearGradient infoGradient = LinearGradient(
    colors: [Color(0xFF4A90D9), Color(0xFF2E6DB4)],
  );
  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFFFFB347), Color(0xFFFF8C00)],
  );
  static const LinearGradient purpleGradient = LinearGradient(
    colors: [Color(0xFF9B59B6), Color(0xFF8E44AD)],
  );
  static const LinearGradient primaryGrad = LinearGradient(
    colors: [Color(0xFF4A90D9), Color(0xFF2E6DB4)],
  );
  static const LinearGradient emeraldGrad = LinearGradient(
    colors: [Color(0xFF00C896), Color(0xFF00A878)],
  );
  static const LinearGradient orangeGrad = LinearGradient(
    colors: [Color(0xFFFFB347), Color(0xFFFF8C00)],
  );

  // ─── DYNAMIC COLORS (theme-aware) ────────
  static Color bgOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0A0A14)
          : const Color(0xFFF5F5F5);

  static Color bgCardOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF12121E)
          : Colors.white;

  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1E30)
          : const Color(0xFFF3F4F6);

  static Color textPrimaryOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : const Color(0xFF111827);

  static Color textMutedOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF6B6B85)
          : const Color(0xFF9CA3AF);

  static Color borderOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2A2A40)
          : const Color(0xFFE5E7EB);

  static Color primaryDarkOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F0F1A)
          : const Color(0xFFFFFFFF);

  static LinearGradient bgGradientOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const LinearGradient(
              colors: [Color(0xFF0A0A14), Color(0xFF12121E), Color(0xFF1A1A2E)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            )
          : const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFF5F5F5), Color(0xFFEEEEEE)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            );
}
