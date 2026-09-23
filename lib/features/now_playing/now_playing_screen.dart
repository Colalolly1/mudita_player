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

/// The cover is the screen. Under it: title, artist, a hairline seek, three
/// controls, one line of what comes next. Everything else this screen used to
/// show, shuffle, repeat, stars, favourite, playlist, lyrics, speed, lives
/// behind the one word at the bottom.
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
        ? _PortraitLayout(
            minimal: minimal, onMore: () => _showMore(context, minimal))
        : _LandscapeLayout(
            minimal: minimal, onMore: () => _showMore(context, minimal));

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
            context.push('/queue');
          } else if (v > 200) {
            Navigator.of(context).maybePop();
          }
        },
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Row(
                children: [
                  _BarWord('Library', onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      context.go('/library');
                    }
                  }),
                  const Spacer(),
                  _BarWord('Queue', onTap: () => context.push('/queue')),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  void _showMore(BuildContext context, bool minimal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => _MoreSheet(
        minimal: minimal,
        onToggleMinimal: () => setState(() => _minimalOverride = !minimal),
      ),
    );
  }
}

class _BarWord extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _BarWord(this.text, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _PortraitLayout extends ConsumerWidget {
  final bool minimal;
  final VoidCallback onMore;
  const _PortraitLayout({required this.minimal, required this.onMore});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final t = state.current!;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (!minimal)
          GestureDetector(
            onTap: () => _openAlbum(context, t),
            child: AspectRatio(
              aspectRatio: 1,
              child: CoverArt(
                artUri: t.artUri.isEmpty ? null : t.artUri,
                size: double.infinity,
                radius: 0,
              ),
            ),
          )
        else
          const Spacer(),
        Expanded(
          child: Column(
            children: [
              const SizedBox(height: 20),
              _TitleBlock(),
              const SizedBox(height: 18),
              _SeekBar(),
              const SizedBox(height: 14),
              _Controls(),
              const Spacer(),
              _UpNextLine(),
              const SizedBox(height: 6),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        InkWell(
          onTap: onMore,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text('More',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ],
    );
  }
}

class _LandscapeLayout extends ConsumerWidget {
  final bool minimal;
  final VoidCallback onMore;
  const _LandscapeLayout({required this.minimal, required this.onMore});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final t = state.current!;
    return Padding(
      padding: const EdgeInsets.all(16),
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
                      radius: 0,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 20),
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TitleBlock(),
                const SizedBox(height: 20),
                _SeekBar(),
                const SizedBox(height: 10),
                _Controls(),
                const SizedBox(height: 12),
                TextButton(onPressed: onMore, child: const Text('More')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One-line "Up next" under the controls; taps through to the queue.
class _UpNextLine extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final nextIdx = state.index + 1;
    if (nextIdx >= state.queue.length) return const SizedBox.shrink();
    final next = state.queue[nextIdx];
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => context.push('/queue'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Up next: ${next.title}'
                '${next.artist.isEmpty ? '' : ' — ${next.artist}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final t = state.current!;
    final artist = t.albumArtist.isEmpty ? t.artist : t.albumArtist;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600, height: 1.15),
          ),
          if (artist.isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _openArtist(context, t),
              borderRadius: BorderRadius.circular(4),
              child: Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
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
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: scheme.onSurface,
              inactiveTrackColor: scheme.outlineVariant,
              thumbColor: scheme.onSurface,
              overlayShape: SliderComponentShape.noOverlay,
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
      ),
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Previous, play, next. Nothing else.
class _Controls extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final ctrl = ref.read(playbackControllerProvider.notifier);
    final lockedAlbum = ctrl.albumOnly;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lockedAlbum)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Album only',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: muted)),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Shuffle and repeat sit either side of the transport, filled in
            // when on and muted when off, rather than hidden under More.
            IconButton(
              iconSize: 26,
              icon: const Icon(Icons.shuffle),
              color: state.shuffle == ShuffleMode.on
                  ? Theme.of(context).colorScheme.onSurface
                  : muted,
              onPressed: lockedAlbum ? null : ctrl.toggleShuffle,
              tooltip: 'Shuffle',
            ),
            const SizedBox(width: 10),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_previous),
              onPressed: lockedAlbum ? null : ctrl.previous,
            ),
            const SizedBox(width: 20),
            IconButton(
              iconSize: 56,
              icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
              onPressed: ctrl.toggle,
            ),
            const SizedBox(width: 20),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.skip_next),
              onPressed: lockedAlbum ? null : ctrl.next,
            ),
            const SizedBox(width: 10),
            IconButton(
              iconSize: 26,
              icon: Icon(state.repeat == RepeatMode.one
                  ? Icons.repeat_one
                  : Icons.repeat),
              color: state.repeat == RepeatMode.off
                  ? muted
                  : Theme.of(context).colorScheme.onSurface,
              onPressed: ctrl.cycleRepeat,
              tooltip: 'Repeat',
            ),
          ],
        ),
      ],
    );
  }
}

/// Everything that used to crowd the screen, one tap down. Words, not icons.
class _MoreSheet extends ConsumerWidget {
  final bool minimal;
  final VoidCallback onToggleMinimal;
  const _MoreSheet({required this.minimal, required this.onToggleMinimal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final ctrl = ref.read(playbackControllerProvider.notifier);
    final t = state.current;
    if (t == null) return const SizedBox.shrink();
    final locked = ctrl.albumOnly;
    final repeatText = switch (state.repeat) {
      RepeatMode.off => 'Off',
      RepeatMode.all => 'All',
      RepeatMode.one => 'One',
    };

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _RatingRow(track: t),
            const Divider(height: 1),
            _MoreRow(
              'Favourite',
              value: t.favorite ? 'Yes' : 'No',
              onTap: () async {
                await ref
                    .read(libraryRepositoryProvider)
                    .setFavorite(t.id, !t.favorite);
                ref.invalidate(allTracksProvider);
              },
            ),
            _MoreRow(
              'Shuffle',
              value: state.shuffle == ShuffleMode.on ? 'On' : 'Off',
              enabled: !locked,
              onTap: ctrl.toggleShuffle,
            ),
            _MoreRow(
              'Repeat',
              value: repeatText,
              enabled: !locked,
              onTap: ctrl.cycleRepeat,
            ),
            _MoreRow('Add to playlist', onTap: () {
              Navigator.pop(context);
              showAddToPlaylistSheet(context, ref, t);
            }),
            _MoreRow('Lyrics', onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => LyricsScreen(track: t)),
              );
            }),
            _MoreRow('Speed and pitch', onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                builder: (_) => const _SpeedPitchSheet(),
              );
            }),
            _MoreRow(
              minimal ? 'Show artwork' : 'Hide artwork',
              onTap: () {
                Navigator.pop(context);
                onToggleMinimal();
              },
            ),
            _MoreRow('Stop and clear queue', onTap: () {
              Navigator.pop(context);
              ctrl.stopAndClear();
              Navigator.of(context).maybePop();
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool enabled;
  final VoidCallback onTap;
  const _MoreRow(this.label,
      {this.value, this.enabled = true, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
        );
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        child: Row(
          children: [
            Expanded(child: Text(label, style: style)),
            if (value != null)
              Text(value!,
                  style: style?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _RatingRow extends ConsumerWidget {
  final Track track;
  const _RatingRow({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(
              child: Text('Rating',
                  style: Theme.of(context).textTheme.bodyLarge)),
          ...List.generate(5, (i) {
            final filled = i < track.rating;
            return IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              constraints: const BoxConstraints(),
              icon: Icon(filled ? Icons.star : Icons.star_border,
                  size: 22, color: on),
              onPressed: () async {
                final next = track.rating == i + 1 ? 0 : i + 1;
                await ref
                    .read(libraryRepositoryProvider)
                    .setRating(track.id, next);
                ref.invalidate(allTracksProvider);
              },
            );
          }),
        ],
      ),
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
            Text('Speed ${_speed.toStringAsFixed(2)}x',
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
            Text('Pitch ${_pitch.toStringAsFixed(2)}x',
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
