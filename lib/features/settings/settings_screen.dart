import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../data/backup/backup_service.dart';
import '../../data/cover_fetch/musicbrainz_cover.dart';
import '../../data/lyrics/lyrics_import.dart';
import '../../playback/hardware_keys.dart';
import '../../playback/media_session_bridge.dart';
import '../../playback/playback_controller.dart';
import '../stats/listening_stats_screen.dart';
import '../../shared/providers/library_providers.dart';
import 'sleep_timer_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _fontOptions = <String?, String>{
    null: 'System default',
    'Roboto': 'Roboto',
    'sans-serif-light': 'Sans Light',
    'sans-serif-medium': 'Sans Medium',
    'serif': 'Serif',
    'monospace': 'Monospace',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    final themeCtrl = ref.read(themeControllerProvider.notifier);
    final folders = ref.watch(musicFoldersProvider);
    final prefs = ref.watch(sharedPreferencesProvider);
    final hwKeys = ref.watch(hardwareKeysProvider);
    final pb = ref.watch(playbackControllerProvider.notifier);

    void rebuild() => (context as Element).markNeedsBuild();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          ListTile(
            title: const Text('Theme'),
            subtitle: Text(switch (theme.mode) {
              AppThemeMode.system => 'Follow system',
              AppThemeMode.light => 'Light',
              AppThemeMode.dark => 'Dark',
            }),
            onTap: () => _pickThemeMode(context, themeCtrl, theme.mode),
          ),
          SwitchListTile(
            title: const Text('AMOLED true black'),
            subtitle: const Text('Pure black for OLED screens'),
            value: theme.useAmoled,
            onChanged: (v) => themeCtrl.setAmoled(v),
          ),
          SwitchListTile(
            title: const Text('E-ink mode'),
            subtitle: const Text(
                'High-contrast monochrome, no animations or accent color'),
            value: theme.einkMode,
            onChanged: (v) => themeCtrl.setEinkMode(v),
          ),
          SwitchListTile(
            title: const Text('Large UI'),
            subtitle: const Text('Bigger text & taller tap targets'),
            value: theme.largeUi,
            onChanged: (v) => themeCtrl.setLargeUi(v),
          ),
          SwitchListTile(
            title: const Text('Hide cover art'),
            subtitle: const Text('Distraction-free list-only view'),
            value: theme.hideCoverArt,
            onChanged: (v) => themeCtrl.setHideCoverArt(v),
          ),
          SwitchListTile(
            title: const Text('Album-derived accent'),
            subtitle: const Text(
                "Sample a color from the playing track's cover and use it as the accent"),
            value: theme.albumDerivedAccent,
            onChanged: (v) => themeCtrl.setAlbumDerivedAccent(v),
          ),
          ListTile(
            title: const Text('Accent color'),
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: theme.accent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            onTap: () => _pickAccent(context, themeCtrl, theme.accent),
          ),
          ListTile(
            title: const Text('Font'),
            subtitle: Text(_fontOptions[theme.fontFamily] ?? 'System default'),
            onTap: () => _pickFont(context, themeCtrl, theme.fontFamily),
          ),
          const Divider(height: 1),
          const _SectionHeader('Library'),
          ...folders.when(
            loading: () => [const ListTile(title: Text('Loading folders…'))],
            error: (e, _) => [ListTile(title: Text('Error: $e'))],
            data: (list) => [
              ...list.map((f) => ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(f.displayName),
                    subtitle: Text(
                      f.uri,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        await ref
                            .read(libraryRepositoryProvider)
                            .removeMusicFolder(f.uri);
                        ref.invalidate(musicFoldersProvider);
                        ref.invalidate(allTracksProvider);
                      },
                    ),
                  )),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Add music folder'),
            onTap: () => _addFolder(context, ref),
          ),
          const _AllFilesAccessTile(),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Rescan library'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(
                const SnackBar(content: Text('Scanning…')),
              );
              await ref.read(libraryRepositoryProvider).rescan();
              ref.invalidate(allTracksProvider);
              ref.invalidate(musicFoldersProvider);
              ref.invalidate(albumsProvider);
              ref.invalidate(artistsProvider);
              ref.invalidate(foldersProvider);
              messenger.showSnackBar(
                const SnackBar(content: Text('Scan complete')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear & rescan'),
            subtitle: const Text(
                'Wipe all indexed tracks then scan from scratch (fixes duplicates)'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear and rescan?'),
                  content: const Text(
                      'This wipes the track index (favorites, ratings and play counts will be reset), then re-scans your music. Your music files are not touched.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Clear & rescan'),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('Clearing & rescanning…')),
              );
              await ref.read(libraryRepositoryProvider).clearAndRescan();
              ref.invalidate(allTracksProvider);
              ref.invalidate(albumsProvider);
              ref.invalidate(artistsProvider);
              ref.invalidate(foldersProvider);
              messenger.showSnackBar(
                const SnackBar(content: Text('Done')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Auto-download missing album art'),
            subtitle: const Text('Fetches covers from iTunes / MusicBrainz'),
            onTap: () => _fetchCovers(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.network_check),
            title: const Text('Test cover-fetch connection'),
            subtitle: const Text(
                'Confirms the phone can reach iTunes from this app'),
            onTap: () => _testCoverConnection(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.lyrics_outlined),
            title: const Text('Import lyrics from folder'),
            subtitle: const Text('Match .lrc files to your library by filename'),
            onTap: () => _importLyrics(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Listening stats'),
            subtitle: const Text(
                'Total listen time, top artists, albums, and tracks'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ListeningStatsScreen(),
              ),
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader('Playback'),
          SwitchListTile(
            secondary: const Icon(Icons.fast_forward_outlined),
            title: const Text('Skip silence'),
            subtitle: const Text('Trim silent parts at start and end'),
            value: prefs.getBool(PrefsKeys.skipSilence) ?? false,
            onChanged: (v) async {
              await pb.setSkipSilence(v);
              rebuild();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.headphones_outlined),
            title: const Text('Pause when headphones unplug'),
            value: prefs.getBool(PrefsKeys.autoPauseHeadphone) ?? true,
            onChanged: (v) async {
              await prefs.setBool(PrefsKeys.autoPauseHeadphone, v);
              rebuild();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.tune),
            title: const Text('Auto-fade on pause'),
            subtitle: const Text('Smooth 300ms fade-out instead of hard cut'),
            value: prefs.getBool(PrefsKeys.autoFadePause) ?? false,
            onChanged: (v) async {
              await prefs.setBool(PrefsKeys.autoFadePause, v);
              rebuild();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.merge_outlined),
            title: const Text('Gapless playback'),
            subtitle: const Text(
                'Sample-accurate transitions between tracks (essential for albums that flow)'),
            value: prefs.getBool(PrefsKeys.gaplessPlayback) ?? true,
            onChanged: (v) async {
              await prefs.setBool(PrefsKeys.gaplessPlayback, v);
              rebuild();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.album_outlined),
            title: const Text('Album-only mode'),
            subtitle: const Text(
                'Lock the player to whole-album listening — no shuffle, no skipping. Commit to the album.'),
            value: pb.albumOnly,
            onChanged: (v) async {
              await pb.setAlbumOnly(v);
              rebuild();
            },
          ),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Sleep timer'),
            onTap: () => showModalBottomSheet(
              context: context,
              builder: (_) => const SleepTimerSheet(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver),
            title: const Text('Background reliability'),
            subtitle: const Text(
                'Stop the system killing playback in the background (fixes volume keys controlling ringtone when out of the app)'),
            onTap: () => _requestBatteryExemption(context, ref),
          ),
          const Divider(height: 1),
          const _SectionHeader('Now playing'),
          SwitchListTile(
            secondary: const Icon(Icons.swipe),
            title: const Text('Swipe gestures'),
            subtitle: const Text(
                'Left/right = next/prev • Up = queue • Down = collapse'),
            value: prefs.getBool(PrefsKeys.swipeGesturesEnabled) ?? true,
            onChanged: (v) async {
              await prefs.setBool(PrefsKeys.swipeGesturesEnabled, v);
              rebuild();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.subtitles_outlined),
            title: const Text('Karaoke lyrics by default'),
            subtitle: const Text('Larger text, focused on the active line'),
            value: prefs.getBool(PrefsKeys.karaokeMode) ?? false,
            onChanged: (v) async {
              await prefs.setBool(PrefsKeys.karaokeMode, v);
              rebuild();
            },
          ),
          const Divider(height: 1),
          const _SectionHeader('Hardware keys'),
          ListTile(
            leading: const Icon(Icons.keyboard_double_arrow_up),
            title: const Text('Double-tap volume'),
            subtitle: Text(hwKeys.doubleTap.label),
            onTap: () => _pickHwAction(
              context,
              'Double-tap volume',
              hwKeys.doubleTap,
              (a) async {
                await hwKeys.setDoubleTap(a);
                rebuild();
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Long-press volume'),
            subtitle: Text(hwKeys.longPress.label),
            onTap: () => _pickHwAction(
              context,
              'Long-press volume',
              hwKeys.longPress,
              (a) async {
                await hwKeys.setLongPress(a);
                rebuild();
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Single press still adjusts volume. Long-press is held >0.6s. '
              'Double-tap is two presses within 0.35s.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const Divider(height: 1),
          const _SectionHeader('Backup'),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Export library data'),
            subtitle: const Text(
                'Saves favorites, ratings, play counts, playlists, settings'),
            onTap: () => _exportBackup(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Restore from backup'),
            onTap: () => _importBackup(context, ref),
          ),
          const Divider(height: 1),
          const _SectionHeader('About'),
          const ListTile(
            title: Text('Mudita Player'),
            subtitle: Text('Minimalist music for Mudita Kompakt'),
          ),
        ],
      ),
    );
  }

  void _pickThemeMode(
    BuildContext context,
    ThemeController ctrl,
    AppThemeMode current,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppThemeMode.values.map((m) {
            return RadioListTile<AppThemeMode>(
              value: m,
              groupValue: current,
              title: Text(switch (m) {
                AppThemeMode.system => 'Follow system',
                AppThemeMode.light => 'Light',
                AppThemeMode.dark => 'Dark',
              }),
              onChanged: (v) {
                if (v != null) ctrl.setMode(v);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _pickAccent(BuildContext context, ThemeController ctrl, Color current) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accent color'),
        contentPadding: const EdgeInsets.all(16),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: AccentPalette.presets.map((c) {
                  return GestureDetector(
                    onTap: () {
                      ctrl.setAccent(c);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == current
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.outline,
                          width: c == current ? 2 : 1,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              ColorPicker(
                pickerColor: current,
                enableAlpha: false,
                hexInputBar: true,
                pickerAreaHeightPercent: 0.5,
                onColorChanged: ctrl.setAccent,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _pickFont(
    BuildContext context,
    ThemeController ctrl,
    String? current,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _fontOptions.entries.map((e) {
            return RadioListTile<String?>(
              value: e.key,
              groupValue: current,
              title: Text(
                e.value,
                style: TextStyle(fontFamily: e.key),
              ),
              onChanged: (v) {
                ctrl.setFontFamily(v);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _pickHwAction(
    BuildContext context,
    String title,
    HwKeyAction current,
    Future<void> Function(HwKeyAction) onPick,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: HwKeyAction.values.map((a) {
            return RadioListTile<HwKeyAction>(
              value: a,
              groupValue: current,
              title: Text(a.label),
              onChanged: (v) async {
                if (v != null) await onPick(v);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _addFolder(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    if (Platform.isAndroid) {
      final audio = await Permission.audio.request();
      final storage = await Permission.storage.request();
      if (!audio.isGranted && !storage.isGranted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Permission denied')),
        );
        return;
      }
    }

    messenger.showSnackBar(
      const SnackBar(content: Text('Scanning device for music…')),
    );

    await ref
        .read(libraryRepositoryProvider)
        .addMusicFolder('mediastore://audio', 'Device music');
    ref.invalidate(musicFoldersProvider);
    ref.invalidate(allTracksProvider);

    messenger.showSnackBar(
      const SnackBar(content: Text('Library updated')),
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ref.read(backupServiceProvider).exportToFile();
      messenger.showSnackBar(
        SnackBar(content: Text('Backup saved: ${file.path}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;
      final res = await ref
          .read(backupServiceProvider)
          .restoreFromFile(File(path));
      ref.invalidate(allTracksProvider);
      ref.invalidate(albumsProvider);
      ref.invalidate(artistsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              'Restored ${res.matched} tracks (${res.missed} missing files)'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }

  Future<void> _requestBatteryExemption(
      BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final bridge = ref.read(mediaSessionBridgeProvider);
    final already = await bridge.isBatteryExempt();
    if (already) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Already exempt — background playback is allowed')),
      );
      return;
    }
    await bridge.requestBatteryExemption();
  }

  Future<void> _testCoverConnection(
      BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Testing…')));
    final err = await ref.read(musicBrainzCoverProvider).selfTest();
    messenger.clearSnackBars();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(err == null ? 'Connection OK' : 'Connection failed'),
        content: Text(
          err == null
              ? 'iTunes is reachable. If "Auto-download" still finds 0 covers, your music files probably have empty or weird Album / Artist tags. Open an album and use the cloud-download icon to test on a single album with detailed error reporting.'
              : err,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchCovers(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final fetcher = ref.read(musicBrainzCoverProvider);
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fetch album covers'),
        content: const Text(
          '"Only missing" skips albums that already have a cover.\n\n'
          '"Force-fetch all" replaces every cover, including ones that look '
          "filled but are actually broken (file deleted, etc).",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'missing'),
            child: const Text('Only missing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'force'),
            child: const Text('Force-fetch all'),
          ),
        ],
      ),
    );
    if (mode == null) return;
    final overwrite = mode == 'force';
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Fetching covers — leave the app open if you can'),
      ),
    );
    final result = await fetcher.fetchAllMissing(
      overwriteExisting: overwrite,
      onProgress: (album, done, total, error) {
        if (done % 3 == 0 || done == total) {
          messenger.clearSnackBars();
          messenger.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 2),
              content: Text(error == null
                  ? '✓ $done/$total — $album'
                  : '✗ $done/$total — $album'),
            ),
          );
        }
      },
    );
    ref.invalidate(albumsProvider);
    ref.invalidate(allTracksProvider);
    messenger.clearSnackBars();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(result.total == 0
            ? 'All albums already have art'
            : 'Done — ${result.filled} / ${result.total} found'),
        content: Text(
          result.total == 0
              ? 'Nothing to do.'
              : 'Filled: ${result.filled}\nNot found: ${result.failed}\n\n'
                  'For albums that didn\'t match, the most common reasons are: '
                  'empty or weird album/artist tags in the file, an obscure '
                  'release iTunes doesn\'t carry, or the album is named in a '
                  'way that doesn\'t match Apple\'s catalog. '
                  'Open the album and tap the cloud-download icon to retry '
                  'with the exact reason shown, or the image icon to pick a '
                  'cover manually.\n\n'
                  '${result.lastError ?? ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _importLyrics(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Importing lyrics…')),
    );
    final result =
        await ref.read(lyricsImporterProvider).importFromFolder(dir);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
            'Found ${result.scanned} .lrc files, matched ${result.matched}, '
            '${result.missed} unmatched'),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

/// Shown only while All files access is missing. Without it, Android 11 and
/// later hide the cover images in music folders and refuse tag and cover
/// writes to the music files.
class _AllFilesAccessTile extends ConsumerStatefulWidget {
  const _AllFilesAccessTile();

  @override
  ConsumerState<_AllFilesAccessTile> createState() =>
      _AllFilesAccessTileState();
}

class _AllFilesAccessTileState extends ConsumerState<_AllFilesAccessTile>
    with WidgetsBindingObserver {
  bool _needed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the system settings page, where it may have been allowed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!Platform.isAndroid) return;
    try {
      final status = await Permission.manageExternalStorage.status;
      final needed = !status.isGranted && !status.isRestricted;
      if (mounted && needed != _needed) setState(() => _needed = needed);
    } catch (_) {}
  }

  Future<void> _request() async {
    try {
      final status = await Permission.manageExternalStorage.request();
      if (!mounted || !status.isGranted) return;
      setState(() => _needed = false);
      // Folder covers that were hidden until now come in with a rescan.
      ref.read(libraryRepositoryProvider).rescan().catchError((_) {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_needed) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.folder_open_outlined),
      title: const Text('Allow all files access'),
      subtitle: const Text(
          'Needed for cover images in music folders, and to save tags and covers into the files'),
      onTap: _request,
    );
  }
}
