import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// SafeVision high-contrast accessibility theme.
///
/// Design requirements (from architecture docs):
/// * **High contrast** — dark background with high-luminance foreground text.
/// * **Large buttons** — minimum 80 dp height, 24 pt font size.
/// * **Touch targets** — minimum 48 dp per Material accessibility guidelines,
///   but most interactive elements use 80 dp so users with low vision can
///   activate them reliably.
abstract class AppTheme {
  AppTheme._();

  // ── Colour constants ───────────────────────────────────────────────────────

  static const Color _backgroundDark   = Color(0xFF0A0A0A);
  static const Color _surfaceDark      = Color(0xFF1A1A1A);
  static const Color _primary          = Color(0xFF00E5FF); // cyan accent
  static const Color _onPrimary        = Color(0xFF000000);
  static const Color _secondary        = Color(0xFF69FF47); // lime accent
  static const Color _onSurface        = Color(0xFFEEEEEE);
  static const Color _error            = Color(0xFFFF5252);
  static const Color _warningOverlay   = Color(0xFFFF6D00);

  /// Exposed so the painter and overlay widgets can use the same colour.
  static const Color warningColor  = _warningOverlay;
  static const Color primaryColor  = _primary;
  static const Color secondaryColor = _secondary;

  // ── Main theme ─────────────────────────────────────────────────────────────

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      // ── Scaffold & background ──────────────────────────────────────────────
      scaffoldBackgroundColor: _backgroundDark,

      colorScheme: const ColorScheme.dark(
        primary:    _primary,
        onPrimary:  _onPrimary,
        secondary:  _secondary,
        surface:    _surfaceDark,
        error:      _error,
        onSurface:  _onSurface,
        onError:    Colors.white,
      ),

      // ── AppBar ─────────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: _backgroundDark,
        foregroundColor: _onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: _onSurface,
          letterSpacing: 1.2,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),

      // ── Elevated buttons — minimum 80 dp height, 24 pt font ────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: _onPrimary,
          minimumSize: const Size(double.infinity, 80),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // ── Text buttons ───────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primary,
          minimumSize: const Size(80, 80),
          textStyle: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Icon buttons ──────────────────────────────────────────────────────
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(80, 80),
          iconSize: 32,
          foregroundColor: _onSurface,
        ),
      ),

      // ── Typography ─────────────────────────────────────────────────────────
      // All text sizes are scaled up from Material defaults to ensure
      // legibility for users with low vision.
      textTheme: base.textTheme.copyWith(
        displayLarge:   _ts(57, FontWeight.bold),
        displayMedium:  _ts(45, FontWeight.bold),
        displaySmall:   _ts(36, FontWeight.bold),
        headlineLarge:  _ts(32, FontWeight.bold),
        headlineMedium: _ts(28, FontWeight.bold),
        headlineSmall:  _ts(24, FontWeight.bold),
        titleLarge:     _ts(22, FontWeight.w600),
        titleMedium:    _ts(20, FontWeight.w600),
        titleSmall:     _ts(18, FontWeight.w500),
        bodyLarge:      _ts(18, FontWeight.normal),
        bodyMedium:     _ts(16, FontWeight.normal),
        bodySmall:      _ts(14, FontWeight.normal),
        labelLarge:     _ts(24, FontWeight.bold),   // button label
        labelMedium:    _ts(18, FontWeight.w600),
        labelSmall:     _ts(14, FontWeight.w500),
      ).apply(
        bodyColor:    _onSurface,
        displayColor: _onSurface,
      ),

      // ── Slider (confidence threshold, speech rate) ─────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor:   _primary,
        inactiveTrackColor: _primary.withOpacity(0.25),
        thumbColor:         _primary,
        overlayColor:       _primary.withOpacity(0.20),
        trackHeight: 6,
        thumbShape:   const RoundSliderThumbShape(enabledThumbRadius: 14),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 28),
        valueIndicatorColor:   _primary,
        valueIndicatorTextStyle: const TextStyle(
          color: _onPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        showValueIndicator: ShowValueIndicator.always,
      ),

      // ── Switch ─────────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? _primary : Colors.grey,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? _primary.withOpacity(0.5)
              : Colors.grey.withOpacity(0.3),
        ),
      ),

      // ── Cards ──────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: _surfaceDark,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),

      // ── SnackBar ──────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _surfaceDark,
        contentTextStyle: const TextStyle(color: _onSurface, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2A2A2A),
        thickness: 1,
        space: 24,
      ),
    );
  }

  static TextStyle _ts(double size, FontWeight weight) => TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: _onSurface,
        fontFamily: 'Roboto',
      );
}