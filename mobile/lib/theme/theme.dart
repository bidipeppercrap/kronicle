import 'package:flutter/material.dart';

/// Warm editorial "digital grimoire" identity, shared with the web client
/// (DESIGN.md, Mobile UI Design). Material 3 re-themed: cream "paper" light,
/// deep warm-gray "candlelit study" dark — never pure black. Dynamic color is
/// deliberately NOT used; the palette is fixed so the status-color semantics
/// and the grimoire feel survive any wallpaper.
class KronicleTheme {
  // ——— UI fonts (bundled, no Google requests) ———
  static const ui = 'Inter'; // chrome: nav, forms, cards, metadata
  static const prose = 'Literata'; // rendered Markdown — bookish, long-form
  static const editor = 'iA Writer Quattro'; // drafting + code/slugs

  // ——— Light "paper" ———
  static const _paper = Color(0xFFFBF7EE); // cream/ivory background
  static const _paperSurface = Color(0xFFF4EEE0); // tonal container
  static const _paperSurfaceHigh = Color(0xFFEDE5D3);
  static const _ink = Color(0xFF2A2521); // near-black warm ink
  static const _inkMuted = Color(0xFF6B6258);
  static const _inkFaint = Color(0xFF938979);
  static const _line = Color(0xFFE2D8C5); // hairline warm border
  static const _accent = Color(0xFFB07D33); // muted amber
  static const _accentInk = Color(0xFF8A5E1E); // amber for text/icons on paper

  // ——— Dark "candlelit study" ———
  static const _study = Color(0xFF1C1A16); // deep warm gray, not black
  static const _studySurface = Color(0xFF26231D);
  static const _studySurfaceHigh = Color(0xFF302C24);
  static const _studyInk = Color(0xFFEDE6D8); // soft off-white
  static const _studyInkMuted = Color(0xFFB3A892);
  static const _studyInkFaint = Color(0xFF847A68);
  static const _studyLine = Color(0xFF3A352B);
  static const _studyAccent = Color(0xFFD9A957); // amber accent
  static const _studyAccentInk = Color(0xFFE3B96F);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isLight = b == Brightness.light;
    final bg = isLight ? _paper : _study;
    final surface = isLight ? _paperSurface : _studySurface;
    final surfaceHigh = isLight ? _paperSurfaceHigh : _studySurfaceHigh;
    final ink = isLight ? _ink : _studyInk;
    final inkMuted = isLight ? _inkMuted : _studyInkMuted;
    final inkFaint = isLight ? _inkFaint : _studyInkFaint;
    final line = isLight ? _line : _studyLine;
    final accent = isLight ? _accent : _studyAccent;
    final accentInk = isLight ? _accentInk : _studyAccentInk;

    final scheme = ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: b,
    ).copyWith(
      surface: bg,
      surfaceContainerLowest: bg,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      primary: accent,
      onPrimary: isLight ? _paper : _study,
      outline: inkFaint,
      outlineVariant: line,
    );

    final colors = KronicleColors(
      accentInk: accentInk,
      accentSoft: accent.withValues(alpha: isLight ? 0.12 : 0.18),
      inkMuted: inkMuted,
      inkFaint: inkFaint,
      line: line,
      stub: isLight ? const Color(0xFFB07D33) : const Color(0xFFD9A957),
      draft: isLight ? const Color(0xFF5B6B7B) : const Color(0xFF8FA3B5),
      canon: isLight ? const Color(0xFF4A6B43) : const Color(0xFF8FB585),
      rejected: isLight ? const Color(0xFFA65648) : const Color(0xFFCB8A7E),
    );

    final base = isLight ? ThemeData.light() : ThemeData.dark();
    final textTheme = base.textTheme.apply(
      fontFamily: ui,
      bodyColor: ink,
      displayColor: ink,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      textTheme: textTheme,
      extensions: [colors],
      // ——— Mostly flat, low shadow (DESIGN.md decision 35) ———
      // Static surfaces carry no shadow; separation comes from hairline
      // borders + tonal surface tints. Shadow is reserved for transient
      // overlays (dialogs, menus, the chat panel) below.
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: ink,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontFamily: ui,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: line),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: accent.withValues(alpha: isLight ? 0.16 : 0.24),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontFamily: ui),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: accent,
        foregroundColor: isLight ? _paper : _study,
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: inkFaint, fontFamily: ui),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        labelStyle: textTheme.labelMedium?.copyWith(fontFamily: ui),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 8, // a transient overlay — keep it floating
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isLight ? _ink : _studySurfaceHigh,
        contentTextStyle: TextStyle(
          color: isLight ? _paper : _studyInk,
          fontFamily: ui,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Palette tokens Material's ColorScheme has no slot for: the per-status colors
/// and the warm ink/line shades. Read with `Theme.of(context).extension`.
@immutable
class KronicleColors extends ThemeExtension<KronicleColors> {
  final Color accentInk;
  final Color accentSoft;
  final Color inkMuted;
  final Color inkFaint;
  final Color line;
  final Color stub;
  final Color draft;
  final Color canon;
  final Color rejected;

  const KronicleColors({
    required this.accentInk,
    required this.accentSoft,
    required this.inkMuted,
    required this.inkFaint,
    required this.line,
    required this.stub,
    required this.draft,
    required this.canon,
    required this.rejected,
  });

  Color status(String s) => switch (s) {
        'stub' => stub,
        'draft' => draft,
        'canon' => canon,
        'rejected' => rejected,
        _ => inkMuted,
      };

  static KronicleColors of(BuildContext context) =>
      Theme.of(context).extension<KronicleColors>()!;

  @override
  KronicleColors copyWith({
    Color? accentInk,
    Color? accentSoft,
    Color? inkMuted,
    Color? inkFaint,
    Color? line,
    Color? stub,
    Color? draft,
    Color? canon,
    Color? rejected,
  }) =>
      KronicleColors(
        accentInk: accentInk ?? this.accentInk,
        accentSoft: accentSoft ?? this.accentSoft,
        inkMuted: inkMuted ?? this.inkMuted,
        inkFaint: inkFaint ?? this.inkFaint,
        line: line ?? this.line,
        stub: stub ?? this.stub,
        draft: draft ?? this.draft,
        canon: canon ?? this.canon,
        rejected: rejected ?? this.rejected,
      );

  @override
  KronicleColors lerp(ThemeExtension<KronicleColors>? other, double t) {
    if (other is! KronicleColors) return this;
    return KronicleColors(
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      line: Color.lerp(line, other.line, t)!,
      stub: Color.lerp(stub, other.stub, t)!,
      draft: Color.lerp(draft, other.draft, t)!,
      canon: Color.lerp(canon, other.canon, t)!,
      rejected: Color.lerp(rejected, other.rejected, t)!,
    );
  }
}
