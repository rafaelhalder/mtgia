import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ManaLoom Theme: "Arcane Weaver" Color Palette
/// Inspired by weaving mana threads with technology
class AppTheme {
  // Brand palette (Arcane-Tech)
  static const Color backgroundAbyss = Color(
    0xFF0A0E14,
  ); // Preto azulado profundo
  static const Color surfaceSlate = Color(0xFF1E293B); // Cinza ardósia (cards)
  static const Color surfaceSlate2 = Color(0xFF0F172A); // Superfície secundária
  static const Color manaViolet = Color(0xFF8B5CF6); // Primary
  static const Color loomCyan = Color(0xFF06B6D4); // Secondary
  static const Color mythicGold = Color(0xFFF59E0B); // Accent

  static const Color textPrimary = Color(0xFFF1F5F9); // Branco suave
  static const Color textSecondary = Color(0xFF94A3B8); // Cinza claro
  static const Color outlineMuted = Color(0xFF334155);

  // MTG language palette (WUBRG + C) for UI badges/identity.
  static const Color manaW = Color(0xFFF0F2C0);
  static const Color manaU = Color(0xFFB3CEEA);
  static const Color manaB = Color(0xFF2B2B2B);
  static const Color manaR = Color(0xFFE07A5F);
  static const Color manaG = Color(0xFF81B29A);
  static const Color manaC = Color(0xFFB8C0CC);

  static const Map<String, Color> wubrg = {
    'W': manaW,
    'U': manaU,
    'B': manaB,
    'R': manaR,
    'G': manaG,
    'C': manaC,
  };

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
      backgroundColor: surfaceSlate,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: surfaceSlate,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: manaViolet,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceSlate,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
