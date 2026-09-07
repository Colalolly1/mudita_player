class AppConstants {
  static const String appName = 'Mudita Player';

  static const Duration shortAnim = Duration(milliseconds: 120);
  static const Duration mediumAnim = Duration(milliseconds: 200);

  static const double miniPlayerHeight = 64;
  static const double bottomNavHeight = 56;

  static const int searchDebounceMs = 200;
  static const int recentlyAddedDays = 30;
  static const int forgottenMinDays = 180;
  static const int mostPlayedLimit = 50;
  static const int historyLimit = 200;

  /// User counts as a "skip" if they advance past this fraction of the track.
  static const double skipThresholdFraction = 0.20;
}

class PrefsKeys {
  static const String themeMode = 'theme_mode';
  static const String useAmoled = 'use_amoled';
  static const String accentColor = 'accent_color';
  static const String fontFamily = 'font_family';
  static const String musicFolderUris = 'music_folder_uris';
  static const String lastTrackId = 'last_track_id';
  static const String lastPositionMs = 'last_position_ms';
  static const String lastQueueIds = 'last_queue_ids';
  static const String shuffleMode = 'shuffle_mode';
  static const String repeatMode = 'repeat_mode';
  static const String skipSilence = 'skip_silence';
  static const String gaplessPlayback = 'gapless_playback';
  static const String replayGainMode = 'replay_gain_mode';
  static const String libraryTabOrder = 'library_tab_order';
  static const String visibleTabs = 'visible_tabs';
  static const String hwKeyDoubleTap = 'hw_key_double_tap';
  static const String hwKeyLongPress = 'hw_key_long_press';
  static const String autoPauseHeadphone = 'auto_pause_headphone';
  static const String sleepTimerLastDuration = 'sleep_timer_last_duration';

  // Speed / pitch
  static const String playbackSpeed = 'playback_speed';
  static const String playbackPitch = 'playback_pitch';

  // Fades
  static const String autoFadePause = 'auto_fade_pause';
  static const String crossfadeMs = 'crossfade_ms';
  static const String sleepFadeOut = 'sleep_fade_out';

  // Theme
  static const String einkMode = 'eink_mode';
  static const String largeUi = 'large_ui';
  static const String albumDerivedAccent = 'album_derived_accent';
  static const String hideCoverArt = 'hide_cover_art';

  // Now playing
  static const String swipeGesturesEnabled = 'swipe_gestures_enabled';

  // Lyrics
  static const String karaokeMode = 'karaoke_mode';

  // Library view density
  static const String albumsViewDensity = 'albums_view_density';

  // Whether we've shown the one-time battery-optimization prompt.
  static const String askedBatteryExemption = 'asked_battery_exemption';

  // Album-only mode: forces linear playback, disables shuffle/skip, stops at
  // end of album. For committed, full-album listening.
  static const String albumOnlyMode = 'album_only_mode';
}

/// Two-state toggle: roomy (default, large tiles + labels) or compact
/// (smaller tiles, more per row).
enum GridDensity { roomy, compact }

enum LibraryTab {
  artists,
  albums,
  songs,
  folders,
  playlists,
  smartPlaylists,
}

enum AppThemeMode { system, light, dark }

enum RepeatMode { off, all, one }

enum ShuffleMode { off, on }
