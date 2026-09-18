import 'package:flutter/material.dart';

/// Centralized color palette for the Kifiya Agent Terminal.
/// Modern light-mode banking design inspired by Revolut, Wise, Nubank.
abstract final class AppColors {
  // ── Background & Surface ──────────────────────────────────────────
  static const Color background = Color(0xFFF8FAFC);       // Slate 50
  static const Color surface = Color(0xFFFFFFFF);           // Pure white
  static const Color surfaceDim = Color(0xFFF1F5F9);       // Slate 100
  static const Color surfaceContainer = Color(0xFFE2E8F0); // Slate 200

  // ── Primary (Teal → Cyan gradient) ────────────────────────────
  static const Color primary = Color(0xFF0D9488);           // Teal 600
  static const Color primaryDark = Color(0xFF0F766E);       // Teal 700
  static const Color primaryLight = Color(0xFFF0FDFA);      // Teal 50
  static const Color primaryMuted = Color(0xFF99F6E4);      // Teal 200
  static const Color onPrimary = Color(0xFFFFFFFF);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF0D9488), Color(0xFF0891B2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradientSubtle = LinearGradient(
    colors: [Color(0xFFF0FDFA), Color(0xFFECFEFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Secondary (Sky Blue) ──────────────────────────────────────────
  static const Color secondary = Color(0xFF0EA5E9);         // Sky 500
  static const Color secondaryLight = Color(0xFFF0F9FF);    // Sky 50
  static const Color onSecondary = Color(0xFFFFFFFF);

  // ── Semantic Colors ───────────────────────────────────────────────
  static const Color success = Color(0xFF10B981);            // Emerald 500
  static const Color successLight = Color(0xFFECFDF5);       // Emerald 50
  static const Color successDark = Color(0xFF059669);         // Emerald 600

  static const Color warning = Color(0xFFF59E0B);            // Amber 500
  static const Color warningLight = Color(0xFFFFFBEB);       // Amber 50
  static const Color warningDark = Color(0xFFD97706);         // Amber 600

  static const Color error = Color(0xFFEF4444);              // Red 500
  static const Color errorLight = Color(0xFFFEF2F2);         // Red 50
  static const Color errorDark = Color(0xFFDC2626);           // Red 600

  // ── Text ──────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0F172A);        // Slate 900
  static const Color textSecondary = Color(0xFF64748B);      // Slate 500
  static const Color textMuted = Color(0xFF94A3B8);          // Slate 400
  static const Color textOnDark = Color(0xFFFFFFFF);
  static const Color textOnDarkMuted = Color(0xFFCBD5E1);   // Slate 300

  // ── Borders & Dividers ────────────────────────────────────────────
  static const Color border = Color(0xFFE2E8F0);            // Slate 200
  static const Color borderSubtle = Color(0xFFF1F5F9);      // Slate 100
  static const Color borderFocused = Color(0xFF0D9488);      // Primary

  // ── Shadows ───────────────────────────────────────────────────────
  static const Color shadowLight = Color(0x0A0F172A);       // 4% slate 900
  static const Color shadowMedium = Color(0x140F172A);      // 8% slate 900
  static const Color shadowHeavy = Color(0x1F0F172A);       // 12% slate 900

  // ── Card category accents ─────────────────────────────────────────
  static const Color accentEmerald = Color(0xFF10B981);
  static const Color accentSky = Color(0xFF0EA5E9);
  static const Color accentViolet = Color(0xFF8B5CF6);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentRose = Color(0xFFF43F5E);

  // ── Gradients for workflow cards ──────────────────────────────────
  static const LinearGradient emeraldGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF34D399)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient skyGradient = LinearGradient(
    colors: [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient violetGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient amberGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Standard card decoration ──────────────────────────────────────
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: border, width: 1),
    boxShadow: const [
      BoxShadow(
        color: shadowLight,
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration get cardDecorationElevated => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: border, width: 1),
    boxShadow: const [
      BoxShadow(
        color: shadowMedium,
        blurRadius: 24,
        offset: Offset(0, 8),
      ),
    ],
  );
}
