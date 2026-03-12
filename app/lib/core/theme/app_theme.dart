import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ManaLoom Theme: "Arcane Weaver" Color Palette
/// Inspired by weaving mana threads with technology
///
/// COLOR BUDGET (22 tokens — regra dos ~20):
///   10 brand/layout + 5 semantic + 6 WUBRG + 1 hint = 22
///   Qualquer cor fora deste arquivo é violação.
///
/// RADIUS SCALE: radiusXs(4) / radiusSm(8) / radiusMd(12) / radiusLg(16) / radiusXl(20)
/// FONT SCALE:   fontXs(10) / fontSm(12) / fontMd(14) / fontLg(16) / fontXl(18) / fontXxl(20) / fontDisplay(32)
class AppTheme {
  // ── Brand palette (layout) ──────────────────────────────────
  static const Color backgroundAbyss = Color(0xFF0A0E14);
  static const Color surfaceSlate = Color(0xFF1E293B);
  static const Color surfaceSlate2 = Color(0xFF0F172A);
  static const Color manaViolet = Color(0xFF8B5CF6);   // Primary
  static const Color loomCyan = Color(0xFF06B6D4);     // Secondary
  static const Color mythicGold = Color(0xFFF59E0B);   // Accent / Tertiary

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textHint = Color(0xFF64748B);     // Hints, placeholders
  static const Color outlineMuted = Color(0xFF334155);

  // ── Semantic (feedback) ─────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF97316);
  static const Color disabled = Color(0xFF6B7280);

  // ── Gradients (MTG atmospheric feel) ─────────────────────
  static const LinearGradient scaffoldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundAbyss, Color(0xFF0C1020), Color(0xFF0A0D1A)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A0A2E), Color(0xFF0F172A), backgroundAbyss],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [manaViolet, Color(0xFF6D28D9)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [surfaceSlate, surfaceSlate2],
  );

  static const LinearGradient goldAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [mythicGold, Color(0xFFD97706)],
  );

  // ── Border Radius Scale (5 tokens) ────────────────────────
  static const double radiusXs = 4;    // chips, badges, indicators
  static const double radiusSm = 8;    // buttons, small containers
  static const double radiusMd = 12;   // cards, panels, dialogs
  static const double radiusLg = 16;   // large containers, scanner
  static const double radiusXl = 20;   // pills, bottom sheets

  // ── Font Size Scale (7 tokens) ────────────────────────────
  static const double fontXs = 10;     // badges, chips, mini-labels
  static const double fontSm = 12;     // captions, labels, metadata
  static const double fontMd = 14;     // body text, list items
  static const double fontLg = 16;     // section titles, buttons
  static const double fontXl = 18;     // section headers
  static const double fontXxl = 20;    // screen titles
  static const double fontDisplay = 32; // hero / avatar placeholder

  // ── MTG WUBRG + Colorless ──────────────────────────────────
  static const Color manaW = Color(0xFFF0F2C0);
  static const Color manaU = Color(0xFFB3CEEA);
  static const Color manaB = Color(0xFFA69F9D);  // Visível em gráficos
  static const Color manaR = Color(0xFFEB9F82);
  static const Color manaG = Color(0xFFC4D3CA);
  static const Color manaC = Color(0xFFB8C0CC);

  static const Map<String, Color> wubrg = {
    'W': manaW,
    'U': manaU,
    'B': manaB,
    'R': manaR,
    'G': manaG,
    'C': manaC,
  };

  // ── Helpers derivados (sem cores novas) ────────────────────

  /// Cor de condição (NM/LP/MP/HP/DMG) — usa palette existente.
  static Color conditionColor(String condition) {
    switch (condition.toUpperCase()) {
      case 'NM': return success;
      case 'LP': return loomCyan;
      case 'MP': return mythicGold;
      case 'HP': return warning;
      case 'DMG': return error;
      default: return textSecondary;
    }
  }

  /// Cor de score/synergy (0-100) — usa palette existente.
  static Color scoreColor(int score) {
    if (score >= 80) return success;
    if (score >= 60) return mythicGold;
    return error;
  }

  static Color identityColor(Set<String> identity) {
    if (identity.isEmpty) return manaC;
    final normalized = identity.map((e) => e.toUpperCase()).toSet();
    if (normalized.length == 1) {
      return wubrg[normalized.first] ?? manaC;
    }
    // Multi-color: default to brand violet; callers can render multi-badges.
    return manaViolet;
  }

  static TextTheme _buildTextTheme() {
    final base = GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme,
    ).apply(bodyColor: textPrimary, displayColor: textPrimary);

    TextStyle? display(TextStyle? s) =>
        s == null ? null : GoogleFonts.crimsonPro(textStyle: s);

    return base.copyWith(
      displayLarge: display(base.displayLarge),
      displayMedium: display(base.displayMedium),
      displaySmall: display(base.displaySmall),
      headlineLarge: display(base.headlineLarge),
      headlineMedium: display(base.headlineMedium),
      headlineSmall: display(base.headlineSmall),
      titleLarge: display(base.titleLarge),
      titleMedium: display(base.titleMedium),
      titleSmall: display(base.titleSmall),
    );
  }

  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: manaViolet,
      secondary: loomCyan,
      tertiary: mythicGold,
      surface: surfaceSlate,
      surfaceContainerHighest: surfaceSlate2,
      outline: outlineMuted,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textPrimary,
    ),
    scaffoldBackgroundColor: backgroundAbyss,
    textTheme: _buildTextTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: surfaceSlate2,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: true,
      shadowColor: manaViolet.withValues(alpha: 0.1),
      surfaceTintColor: Colors.transparent,
      shape: const Border(
        bottom: BorderSide(color: outlineMuted, width: 0.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceSlate,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        side: const BorderSide(color: outlineMuted, width: 0.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: manaViolet,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        elevation: 4,
        shadowColor: manaViolet.withValues(alpha: 0.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: manaViolet,
        side: const BorderSide(color: manaViolet, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceSlate,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: outlineMuted, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: outlineMuted, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: manaViolet, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceSlate2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: const BorderSide(color: outlineMuted, width: 0.5),
      ),
      elevation: 12,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceSlate2,
      indicatorColor: manaViolet.withValues(alpha: 0.2),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        side: BorderSide(color: manaViolet.withValues(alpha: 0.3), width: 0.5),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: fontXs,
            fontWeight: FontWeight.w600,
            color: manaViolet,
          );
        }
        return const TextStyle(fontSize: fontXs, color: textSecondary);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: manaViolet, size: 22);
        }
        return const IconThemeData(color: textSecondary, size: 22);
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceSlate,
      selectedColor: manaViolet.withValues(alpha: 0.2),
      labelStyle: const TextStyle(fontSize: fontSm, color: textPrimary),
      side: const BorderSide(color: outlineMuted, width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXs)),
    ),
    dividerTheme: const DividerThemeData(
      color: outlineMuted,
      thickness: 0.5,
    ),
  );
}
