import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ManaLoom Theme: "Calm Abyss" Palette
/// Neutral dark UI — card artwork is the main visual focus.
///
/// DESIGN RULES:
///   1. Single primary accent (violet). No cyan.
///   2. Gradients only for hero sections and primary buttons.
///   3. Surface hierarchy: backgroundAbyss < surfaceSlate < surfaceElevated.
///
/// COLOR BUDGET (24 tokens):
///   10 brand/layout + 5 semantic + 6 WUBRG + 1 hint + 2 format extras = 24
///   Qualquer cor fora deste arquivo é violação.
///
/// RADIUS SCALE: radiusXs(4) / radiusSm(8) / radiusMd(12) / radiusLg(16) / radiusXl(20)
/// FONT SCALE:   fontXs(10) / fontSm(12) / fontMd(14) / fontLg(16) / fontXl(18) / fontXxl(20) / fontDisplay(32)
class AppTheme {
  // ── Brand palette (layout) ──────────────────────────────────
  static const Color backgroundAbyss = Color(0xFF0B0F1A);
  static const Color surfaceSlate = Color(0xFF141B2D);
  static const Color surfaceElevated = Color(0xFF1C2438);
  static const Color manaViolet = Color(0xFF7C3AED);    // Primary
  static const Color primarySoft = Color(0xFFA78BFA);    // Primary soft
  static const Color mythicGold = Color(0xFFF59E0B);     // Accent / Tertiary

  static const Color textPrimary = Color(0xFFE5E7EB);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textHint = Color(0xFF6B7280);       // Hints, placeholders
  static const Color outlineMuted = Color(0xFF2A3552);

  // ── Deprecated aliases (backward compat) ────────────────────
  @Deprecated('Use primarySoft instead')
  static const Color loomCyan = primarySoft;
  @Deprecated('Use surfaceElevated instead')
  static const Color surfaceSlate2 = surfaceElevated;

  // ── Semantic (feedback) ─────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color disabled = Color(0xFF6B7280);

  // ── Gradients ───────────────────────────────────────────────
  // Gradients reserved for hero sections and primary buttons only.
  // Cards/lists use flat surfaceSlate or surfaceElevated.
  static const LinearGradient scaffoldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundAbyss, Color(0xFF0D1224), Color(0xFF0B0F1A)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A0A2E), surfaceSlate, backgroundAbyss],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [manaViolet, Color(0xFF6D28D9)],
  );

  /// Intentionally flat — no visible gradient on cards/list items.
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [surfaceSlate, surfaceSlate],
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

  // ── Format accent colors (deck card frames) ───────────────
  static const Color formatCommander = mythicGold;
  static const Color formatStandard = primarySoft;
  static const Color formatModern = manaViolet;
  static const Color formatPioneer = Color(0xFF34D399);  // Emerald green
  static const Color formatLegacy = Color(0xFFEC4899);   // Rose pink
  static const Color formatVintage = warning;            // reuses warning orange
  static const Color formatPauper = textSecondary;

  // ── Helpers derivados (sem cores novas) ────────────────────

  /// Cor de condição (NM/LP/MP/HP/DMG) — usa palette existente.
  static Color conditionColor(String condition) {
    switch (condition.toUpperCase()) {
      case 'NM': return success;
      case 'LP': return primarySoft;
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
      secondary: primarySoft,
      tertiary: mythicGold,
      surface: surfaceSlate,
      surfaceContainerHighest: surfaceElevated,
      outline: outlineMuted,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textPrimary,
    ),
    scaffoldBackgroundColor: backgroundAbyss,
    textTheme: _buildTextTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: surfaceElevated,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: true,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: const Border(
        bottom: BorderSide(color: outlineMuted, width: 0.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceSlate,
      elevation: 0,
      shadowColor: Colors.transparent,
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
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primarySoft,
        side: const BorderSide(color: outlineMuted, width: 1),
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
      backgroundColor: surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: const BorderSide(color: outlineMuted, width: 0.5),
      ),
      elevation: 8,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceElevated,
      indicatorColor: manaViolet.withValues(alpha: 0.15),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSm),
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
      selectedColor: manaViolet.withValues(alpha: 0.15),
      labelStyle: const TextStyle(fontSize: fontSm, color: textPrimary),
      side: const BorderSide(color: outlineMuted, width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXs)),
    ),
    dividerTheme: const DividerThemeData(
      color: outlineMuted,
      thickness: 0.5,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
      ),
    ),
  );
}
