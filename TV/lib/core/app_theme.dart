import 'package:flutter/material.dart';

/// Paleta e identidad visual de NexusStream.
abstract final class AppColors {
  static const background = Color(0xFF141519);
  static const navy = Color(0xFF1B1C21);
  static const surface = Color(0xFF1F2026);
  static const surfaceElevated = Color(0xFF27282F);
  static const surfaceHighlight = Color(0xFF2F3038);

  /// Acento principal (píldora activa, botones, foco). Se puede cambiar desde
  /// Ajustes › Apariencia; todos los widgets leen este valor al reconstruirse.
  static Color _accent = const Color(0xFFFFFFFF);

  static Color get accent => _accent;

  static void setAccent(Color value) {
    _accent = value;
  }

  /// Alias histórico del acento.
  static Color get cyan => _accent;

  /// Color del contenido (texto/icono) sobre el acento, con contraste legible.
  static Color get onAccent => _accent.computeLuminance() > 0.55
      ? const Color(0xFF101114)
      : Colors.white;

  static const blue = Color(0xFF5B8DEF);
  static const violet = Color(0xFF8B5CF6);
  static const magenta = Color(0xFFC084FC);

  static const textPrimary = Color(0xFFF5F5F7);
  static const textMuted = Color(0xFF9EA1A8);
  static const textFaint = Color(0xFF6F727B);

  static const success = Color(0xFF4ADE80);
  static const warning = Color(0xFFFBBF24);
  static const danger = Color(0xFFF87171);

  static const border = Color(0x14FFFFFF);
  static const borderStrong = Color(0x26FFFFFF);

  static LinearGradient get brandGradient => LinearGradient(
    colors: [_accent, Color.lerp(_accent, Colors.black, 0.24)!],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get brandGradientHorizontal => LinearGradient(
    colors: [_accent, Color.lerp(_accent, Colors.black, 0.24)!],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const cardGradient = LinearGradient(
    colors: [Color(0xFF26272D), Color(0xFF1B1C21)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const heroGradient = LinearGradient(
    colors: [Color(0xFF232429), Color(0xFF1B1C21), Color(0xFF141519)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Degrandes suaves para las fichas de categorías (mock: Action, Fantasy…).
  static const categoryTileGradients = <Gradient>[
    LinearGradient(
      colors: [Color(0xFF7A3B2E), Color(0xFF2A2326)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF4A4E57), Color(0xFF26272D)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF2F6B5F), Color(0xFF232429)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF6A46B8), Color(0xFF25252C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF8A6A2C), Color(0xFF2C2520)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF2F4B8C), Color(0xFF1E2026)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF7A2E52), Color(0xFF26242A)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ];

  static Color glow([double alpha = 0.30]) =>
      Colors.white.withValues(alpha: alpha);

  /// Degradado suave y estable para una categoría según su nombre.
  static Gradient categoryGradient(String name) {
    var hash = 0;
    for (final rune in name.toLowerCase().runes) {
      hash = (hash * 31 + rune) & 0x7fffffff;
    }
    return categoryTileGradients[hash % categoryTileGradients.length];
  }
}

abstract final class AppTheme {
  static ThemeData? _cached;
  static Color? _cachedAccent;

  /// Tema vigente, reutilizado mientras no cambie el color de énfasis.
  static ThemeData themed() {
    if (_cached == null || _cachedAccent != AppColors.accent) {
      _cachedAccent = AppColors.accent;
      _cached = dark();
    }
    return _cached!;
  }

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.violet,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: const Color(0xFF1A0505),
      outline: AppColors.borderStrong,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: AppColors.borderStrong),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.cyan,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface.withValues(alpha: 0.9),
        hintStyle: const TextStyle(
          color: AppColors.textFaint,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.accent, width: 1.6),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHighlight,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.surfaceHighlight,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 450),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          AppColors.textFaint.withValues(alpha: 0.45),
        ),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.cyan,
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      focusColor: AppColors.cyan.withValues(alpha: 0.18),
      hoverColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.04),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      displayLarge: const TextStyle(
        fontSize: 44,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.4,
        height: 1.08,
        color: AppColors.textPrimary,
      ),
      displaySmall: const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
        height: 1.1,
        color: AppColors.textPrimary,
      ),
      headlineLarge: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        height: 1.15,
        color: AppColors.textPrimary,
      ),
      headlineMedium: const TextStyle(
        fontSize: 23,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: AppColors.textPrimary,
      ),
      titleLarge: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: AppColors.textPrimary,
      ),
      titleMedium: const TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleSmall: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        height: 1.45,
        color: AppColors.textPrimary,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        height: 1.45,
        color: AppColors.textMuted,
      ),
      bodySmall: const TextStyle(
        fontSize: 12,
        height: 1.4,
        color: AppColors.textMuted,
      ),
      labelLarge: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: AppColors.textPrimary,
      ),
      labelMedium: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: AppColors.textMuted,
      ),
      labelSmall: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: AppColors.textMuted,
      ),
    );
  }
}
