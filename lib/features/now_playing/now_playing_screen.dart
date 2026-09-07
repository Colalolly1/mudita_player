import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_controller.dart';
import '../../data/database/app_database.dart';
import '../../playback/playback_controller.dart';
import '../../shared/models/album.dart';
import '../../shared/widgets/add_to_playlist_sheet.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/providers/library_providers.dart';
import '../library/album_detail_screen.dart';
import '../library/artist_detail_screen.dart';
import '../lyrics_view/lyrics_screen.dart';

void _openAlbum(BuildContext context, Track t) {
  if (t.album.isEmpty) return;
  final aa = t.albumArtist.isEmpty ? t.artist : t.albumArtist;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AlbumDetailScreen(albumKey: AlbumKey(t.album, aa)),
    ),
  );
}

void _openArtist(BuildContext context, Track t) {
  final artist = t.albumArtist.isEmpty ? t.artist : t.albumArtist;
  if (artist.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ArtistDetailScreen(artist: artist),
    ),
  );
}

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  bool? _minimalOverride;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackControllerProvider);
    final theme = ref.watch(themeControllerProvider);
    final prefs = ref.watch(sharedPreferencesProvider);
    final swipeEnabled = prefs.getBool(PrefsKeys.swipeGesturesEnabled) ?? true;
    final t = state.current;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nothing playing')),
      );
    }

    final minimal = _minimalOverride ?? theme.hideCoverArt;
    final scheme = Theme.of(context).colorScheme;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final ctrl = ref.read(playbackControllerProvider.notifier);

    Widget body = isPortrait
        ? _PortraitLayout(minimal: minimal)
        : _LandscapeLayout(minimal: minimal);

    if (swipeEnabled) {
      body = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) {
            ctrl.next();
          } else if (v > 200) {
            ctrl.previous();
          }
        },
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) {
            // swipe up — open queue
            context.push('/queue');
          } else if (v > 200) {
            // swipe down — collapse now-playing
            Navigator.of(context).maybePop();
          }
        },
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          tooltip: 'Back to library',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/library');
            }
          },
        ),
        actions: [
          IconButton(
            icon: Icon(
                minimal ? Icons.album_outlined : Icons.text_fields_outlined),
            onPressed: () =>
                setState(() => _minimalOverride = !minimal),
            tooltip: minimal ? 'Show artwork' : 'Minimal mode',
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Speed / pitch',
            onPressed: () => _showSpeedPitch(context),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music),
            onPressed: () => context.push('/queue'),
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  void _showSpeedPitch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => const _SpeedPitchSheet(),
    );
  }
}

class _SpeedPitchSheet extends ConsumerStatefulWidget {
  const _SpeedPitchSheet();
  @override
  ConsumerState<_SpeedPitchSheet> createState() => _SpeedPitchSheetState();
}

class _SpeedPitchSheetState extends ConsumerState<_SpeedPitchSheet> {
  late double _speed;
  late double _pitch;

  @override
  void initState() {
    super.initState();
    final c = ref.read(playbackControllerProvider.notifier);
    _speed = c.speed;
    _pitch = c.pitch;
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.read(playbackControllerProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Speed: ${_speed.toStringAsFixed(2)}x',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              min: 0.5,
              max: 2.0,
              divisions: 30,
              value: _speed,
              onChanged: (v) => setState(() => _speed = v),
              onChangeEnd: (v) async => c.setSpeed(v),
            ),
            const SizedBox(height: 12),
            Text('Pitch: ${_pitch.toStringAsFixed(2)}x',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              min: 0.5,
              max: 2.0,
              divisions: 30,
              value: _pitch,
              onChanged: (v) => setState(() => _pitch = v),
              onChangeEnd: (v) async => c.setPitch(v),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await c.setSpeed(1.0);
                  await c.setPitch(1.0);
                  setState(() {
                    _speed = 1.0;
                    _pitch = 1.0;
                  });
                },
                child: const Text('Reset'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortraitLayout extends ConsumerWidget {
  final bool minimal;
  const _PortraitLayout({required this.minimal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final t = state.current!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          if (!minimal)
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: GestureDetector(
                    onTap: () => _openAlbum(context, t),
                    child: CoverArt(
                      artUri: t.artUri.isEmpty ? null : t.artUri,
                      size: double.infinity,
                      radius: 6,
                    ),
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(height: 24),
          _TitleBlock(),
          const SizedBox(height: 16),
          _SeekBar(),
          const SizedBox(height: 8),
          _Controls(),
          const SizedBox(height: 12),
          _SecondaryControls(),
          _UpNextLine(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// One-line "Up next" preview under the controls; taps through to the queue.
class _UpNextLine extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final nextIdx = state.index + 1;
    if (nextIdx >= state.queue.length) return const SizedBox.shrink();
    final next = state.queue[nextIdx];
    final queued = ref
        .read(playbackControllerProvider.notifier)
        .pendingQueueIds
        .contains(next.id);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => context.push('/queue'),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(queued ? Icons.playlist_add_check : Icons.queue_music,
                size: 14, color: muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Up next: ${next.title}'
                '${next.artist.isEmpty ? '' : ' — ${next.artist}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandscapeLayout extends ConsumerWidget {
  final bool minimal;
  const _LandscapeLayout({required this.minimal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final t = state.current!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          if (!minimal)
            Expanded(
              flex: 2,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: GestureDetector(
                    onTap: () => _openAlbum(context, t),
                    child: CoverArt(
                      artUri: t.artUri.isEmpty ? null : t.artUri,
                      size: double.infinity,
                      radius: 6,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 24),
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TitleBlock(),
                const SizedBox(height: 24),
                _SeekBar(),
                const SizedBox(height: 12),
                _Controls(),
                const SizedBox(height: 16),
                _SecondaryControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final t = state.current!;
    return Column(
      children: [
        Text(
          t.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        // Tap the artist → open that artist's page.
        if (t.artist.isNotEmpty || t.albumArtist.isNotEmpty)
          InkWell(
            onTap: () => _openArtist(context, t),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                t.albumArtist.isEmpty ? t.artist : t.albumArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        if (t.album.isNotEmpty) ...[
          const SizedBox(height: 2),
          // Tap the album → open that album's page.
          InkWell(
            onTap: () => _openAlbum(context, t),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                t.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SeekBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final pos = state.position;
    final dur = state.duration;
    final maxMs = dur.inMilliseconds <= 0 ? 1 : dur.inMilliseconds;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          ),
          child: Slider(
            min: 0,
            max: maxMs.toDouble(),
            value: pos.inMilliseconds.clamp(0, maxMs).toDouble(),
            onChanged: (v) => ref
                .read(playbackControllerProvider.notifier)
                .seek(Duration(milliseconds: v.toInt())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_format(pos), style: Theme.of(context).textTheme.bodySmall),
              Text(_format(dur), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Controls extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final ctrl = ref.read(playbackControllerProvider.notifier);
    final accent = Theme.of(context).colorScheme.primary;
    final on = Theme.of(context).colorScheme.onSurface;
    final lockedAlbum = ctrl.albumOnly;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lockedAlbum)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.album_outlined, size: 14, color: on.withAlpha(180)),
                const SizedBox(width: 6),
                Text(
                  'Album-only mode — committed listening',
                  style: TextStyle(fontSize: 11, color: on.withAlpha(180)),
                ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              iconSize: 28,
              icon: Icon(
                Icons.shuffle,
                color: state.shuffle == ShuffleMode.on
                    ? accent
                    : on.withAlpha(150),
              ),
              onPressed: lockedAlbum ? null : ctrl.toggleShuffle,
            ),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_previous),
              onPressed: lockedAlbum ? null : ctrl.previous,
            ),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              child: IconButton(
                iconSize: 44,
                padding: const EdgeInsets.all(12),
                icon: Icon(
                  state.playing ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: ctrl.toggle,
              ),
            ),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_next),
              onPressed: lockedAlbum ? null : ctrl.next,
            ),
            IconButton(
              iconSize: 28,
              icon: Icon(
                switch (state.repeat) {
                  RepeatMode.off => Icons.repeat,
                  RepeatMode.all => Icons.repeat,
                  RepeatMode.one => Icons.repeat_one,
                },
                color: state.repeat == RepeatMode.off
                    ? on.withAlpha(150)
                    : accent,
              ),
              onPressed: lockedAlbum ? null : ctrl.cycleRepeat,
            ),
          ],
        ),
      ],
    );
  }
}

class _SecondaryControls extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final t = state.current!;
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final filled = i < t.rating;
            return IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              constraints: const BoxConstraints(),
              icon: Icon(
                filled ? Icons.star : Icons.star_border,
                size: 18,
                color: filled ? accent : null,
              ),
              onPressed: () async {
                final next = t.rating == i + 1 ? 0 : i + 1;
                await ref.read(libraryRepositoryProvider).setRating(t.id, next);
                ref.invalidate(allTracksProvider);
              },
            );
          }),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(t.favorite ? Icons.favorite : Icons.favorite_border,
                  color: t.favorite ? accent : null),
              onPressed: () async {
                await ref
                    .read(libraryRepositoryProvider)
                    .setFavorite(t.id, !t.favorite);
                ref.invalidate(allTracksProvider);
              },
            ),
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Add to playlist',
              onPressed: () => showAddToPlaylistSheet(context, ref, t),
            ),
            IconButton(
              icon: const Icon(Icons.lyrics_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => LyricsScreen(track: t)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
