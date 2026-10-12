import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'app_theme.dart';

class ThemeSettings {
  final AppThemeMode mode;
  final bool useAmoled;
  final Color accent;
  final bool einkMode;
  final bool largeUi;
  final bool albumDerivedAccent;
  final bool hideCoverArt;
  final String? fontFamily;

  const ThemeSettings({
    required this.mode,
    required this.useAmoled,
    required this.accent,
    this.einkMode = false,
    this.largeUi = false,
    this.albumDerivedAccent = false,
    this.hideCoverArt = false,
    this.fontFamily,
  });

  ThemeSettings copyWith({
    AppThemeMode? mode,
    bool? useAmoled,
    Color? accent,
    bool? einkMode,
    bool? largeUi,
    bool? albumDerivedAccent,
    bool? hideCoverArt,
    String? fontFamily,
    bool clearFont = false,
  }) {
    return ThemeSettings(
      mode: mode ?? this.mode,
      useAmoled: useAmoled ?? this.useAmoled,
      accent: accent ?? this.accent,
      einkMode: einkMode ?? this.einkMode,
      largeUi: largeUi ?? this.largeUi,
      albumDerivedAccent: albumDerivedAccent ?? this.albumDerivedAccent,
      hideCoverArt: hideCoverArt ?? this.hideCoverArt,
      fontFamily: clearFont ? null : (fontFamily ?? this.fontFamily),
    );
  }

  ThemeMode get materialMode => switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };
}

class ThemeController extends StateNotifier<ThemeSettings> {
  ThemeController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static ThemeSettings _load(SharedPreferences prefs) {
    final modeIdx = prefs.getInt(PrefsKeys.themeMode) ?? 0;
    final amoled = prefs.getBool(PrefsKeys.useAmoled) ?? false;
    final accentInt = prefs.getInt(PrefsKeys.accentColor) ??
        AccentPalette.defaultAccent.toARGB32();
    // New installs start in e-ink mode. An empty prefs file means this is the
    // first launch; existing installs keep the mode they had. The choice is
    // saved straight away so the next launch reads it back.
    var eink = prefs.getBool(PrefsKeys.einkMode);
    if (eink == null) {
      eink = prefs.getKeys().isEmpty;
      prefs.setBool(PrefsKeys.einkMode, eink);
    }
    return ThemeSettings(
      mode: AppThemeMode.values[
          modeIdx.clamp(0, AppThemeMode.values.length - 1)],
      useAmoled: amoled,
      accent: Color(accentInt),
      einkMode: eink,
      largeUi: prefs.getBool(PrefsKeys.largeUi) ?? false,
      albumDerivedAccent: prefs.getBool(PrefsKeys.albumDerivedAccent) ?? false,
      hideCoverArt: prefs.getBool(PrefsKeys.hideCoverArt) ?? false,
      fontFamily: prefs.getString(PrefsKeys.fontFamily),
    );
  }

  Future<void> setMode(AppThemeMode mode) async {
    state = state.copyWith(mode: mode);
    await _prefs.setInt(PrefsKeys.themeMode, mode.index);
  }

  Future<void> setAmoled(bool value) async {
    state = state.copyWith(useAmoled: value);
    await _prefs.setBool(PrefsKeys.useAmoled, value);
  }

  Future<void> setAccent(Color color) async {
    state = state.copyWith(accent: color);
    await _prefs.setInt(PrefsKeys.accentColor, color.toARGB32());
  }

  Future<void> setEinkMode(bool value) async {
    state = state.copyWith(einkMode: value);
    await _prefs.setBool(PrefsKeys.einkMode, value);
  }

  Future<void> setLargeUi(bool value) async {
    state = state.copyWith(largeUi: value);
    await _prefs.setBool(PrefsKeys.largeUi, value);
  }

  Future<void> setAlbumDerivedAccent(bool value) async {
    state = state.copyWith(albumDerivedAccent: value);
    await _prefs.setBool(PrefsKeys.albumDerivedAccent, value);
  }

  Future<void> setHideCoverArt(bool value) async {
    state = state.copyWith(hideCoverArt: value);
    await _prefs.setBool(PrefsKeys.hideCoverArt, value);
  }

  Future<void> setFontFamily(String? family) async {
    state = state.copyWith(fontFamily: family, clearFont: family == null);
    if (family == null) {
      await _prefs.remove(PrefsKeys.fontFamily);
    } else {
      await _prefs.setString(PrefsKeys.fontFamily, family);
    }
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in main()');
});

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeSettings>((ref) {
  return ThemeController(ref.watch(sharedPreferencesProvider));
});

ThemeData lightThemeFor(ThemeSettings settings) =>
    AppTheme.light(settings.accent, eink: settings.einkMode, largeUi: settings.largeUi, fontFamily: settings.fontFamily);

ThemeData darkThemeFor(ThemeSettings settings) => AppTheme.dark(
      settings.accent,
      amoled: settings.useAmoled,
      eink: settings.einkMode,
      largeUi: settings.largeUi,
      fontFamily: settings.fontFamily,
    );
