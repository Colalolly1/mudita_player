import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static ThemeData light(
    Color accent, {
    bool eink = false,
    bool largeUi = false,
    String? fontFamily,
  }) {
    if (eink) return _einkLight(largeUi: largeUi, fontFamily: fontFamily);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      surface: Colors.white,
      surfaceContainer: const Color(0xFFF7F7F7),
      surfaceContainerHigh: const Color(0xFFF0F0F0),
      surfaceContainerHighest: const Color(0xFFE8E8E8),
      onSurface: const Color(0xFF111111),
      onSurfaceVariant: const Color(0xFF555555),
      outline: const Color(0xFFD0D0D0),
      outlineVariant: const Color(0xFFE5E5E5),
    );
    return _build(scheme, accent,
        isDark: false, amoled: false, largeUi: largeUi, fontFamily: fontFamily);
  }

  static ThemeData dark(
    Color accent, {
    bool amoled = false,
    bool eink = false,
    bool largeUi = false,
    String? fontFamily,
  }) {
    if (eink) return _einkDark(largeUi: largeUi, fontFamily: fontFamily);
    final bg = amoled ? Colors.black : const Color(0xFF0E0E0E);
    final surface1 = amoled ? Colors.black : const Color(0xFF161616);
    final surface2 = amoled ? const Color(0xFF0A0A0A) : const Color(0xFF1C1C1C);
    final surface3 = amoled ? const Color(0xFF111111) : const Color(0xFF222222);

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      surface: bg,
      surfaceContainer: surface1,
      surfaceContainerHigh: surface2,
      surfaceContainerHighest: surface3,
      onSurface: const Color(0xFFEDEDED),
      onSurfaceVariant: const Color(0xFFA0A0A0),
      outline: const Color(0xFF333333),
      outlineVariant: const Color(0xFF222222),
    );
    return _build(scheme, accent,
        isDark: true, amoled: amoled, largeUi: largeUi, fontFamily: fontFamily);
  }

  /// E-ink mode: pure black/white with no animations or accent color.
  static ThemeData _einkLight({required bool largeUi, String? fontFamily}) {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Colors.black,
      onPrimary: Colors.white,
      secondary: Colors.black,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: Colors.black,
      onSurfaceVariant: Colors.black,
      outline: Colors.black,
      outlineVariant: Colors.black54,
      error: Colors.black,
      onError: Colors.white,
      surfaceContainer: Colors.white,
      surfaceContainerHigh: Colors.white,
      surfaceContainerHighest: Colors.white,
    );
    return _build(scheme, Colors.black,
        isDark: false,
        amoled: false,
        eink: true,
        largeUi: largeUi,
        fontFamily: fontFamily);
  }

  static ThemeData _einkDark({required bool largeUi, String? fontFamily}) {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Colors.white,
      onPrimary: Colors.black,
      secondary: Colors.white,
      onSecondary: Colors.black,
      surface: Colors.black,
      onSurface: Colors.white,
      onSurfaceVariant: Colors.white,
      outline: Colors.white,
      outlineVariant: Colors.white54,
      error: Colors.white,
      onError: Colors.black,
      surfaceContainer: Colors.black,
      surfaceContainerHigh: Colors.black,
      surfaceContainerHighest: Colors.black,
    );
    return _build(scheme, Colors.white,
        isDark: true,
        amoled: true,
        eink: true,
        largeUi: largeUi,
        fontFamily: fontFamily);
  }

  static ThemeData _build(
    ColorScheme scheme,
    Color accent, {
    required bool isDark,
    required bool amoled,
    bool eink = false,
    bool largeUi = false,
    String? fontFamily,
  }) {
    final scale = largeUi ? 1.18 : 1.0;
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      pageTransitionsTheme: eink
          ? const PageTransitionsTheme(builders: {
              TargetPlatform.android: _NoAnimPageTransitionsBuilder(),
            })
          : const PageTransitionsTheme(builders: {
              TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            }),
      canvasColor: scheme.surface,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 0.5,
        space: 0.5,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: scheme.surface,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: scheme.surface,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20 * scale,
          fontWeight: FontWeight.w500,
          fontFamily: fontFamily,
          letterSpacing: -0.2,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: accent,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
        ),
        indicatorSize: TabBarIndicatorSize.label,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: accent,
        unselectedItemColor: scheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 8,
        dense: false,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: scheme.outlineVariant,
        thumbColor: accent,
        trackHeight: 2,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
      ),
      textTheme: _textTheme(scheme, scale, fontFamily),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
      visualDensity: largeUi ? VisualDensity.standard : VisualDensity.compact,
    );
  }

  static TextTheme _textTheme(ColorScheme scheme, double scale, String? font) {
    final on = scheme.onSurface;
    final var_ = scheme.onSurfaceVariant;
    TextStyle s(double size, FontWeight w, Color c, {double? ls, double? h}) =>
        TextStyle(
          color: c,
          fontSize: size * scale,
          fontWeight: w,
          letterSpacing: ls,
          height: h,
          fontFamily: font,
        );
    return TextTheme(
      displayLarge: s(34, FontWeight.w300, on, ls: -0.5),
      displayMedium: s(28, FontWeight.w300, on, ls: -0.3),
      headlineLarge: s(24, FontWeight.w400, on, ls: -0.2),
      headlineMedium: s(20, FontWeight.w500, on, ls: -0.1),
      titleLarge: s(17, FontWeight.w500, on),
      titleMedium: s(15, FontWeight.w500, on),
      titleSmall: s(13, FontWeight.w500, on),
      bodyLarge: s(15, FontWeight.w400, on, h: 1.4),
      bodyMedium: s(14, FontWeight.w400, on, h: 1.4),
      bodySmall: s(12, FontWeight.w400, var_, h: 1.4),
      labelLarge: s(14, FontWeight.w500, on),
      labelMedium: s(12, FontWeight.w400, var_, ls: 0.2),
      labelSmall: s(11, FontWeight.w400, var_, ls: 0.3),
    );
  }
}

class _NoAnimPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

class AccentPalette {
  static const List<Color> presets = [
    Color(0xFFE5E5E5),
    Color(0xFFFFFFFF),
    Color(0xFFFF6B35),
    Color(0xFFFFB627),
    Color(0xFF7FB069),
    Color(0xFF4ECDC4),
    Color(0xFF6C9EFF),
    Color(0xFFB388FF),
    Color(0xFFFF6E91),
    Color(0xFFD64545),
  ];

  static const Color defaultAccent = Color(0xFFE5E5E5);
}
