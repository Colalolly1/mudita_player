import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/track_tile.dart';
import '../../shared/providers/library_providers.dart';
import '../../playback/playback_controller.dart';
import 'tabs/smart_tab.dart';

class SmartPlaylistScreen extends ConsumerWidget {
  final SmartKind kind;
  final String title;
  const SmartPlaylistScreen({
    super.key,
    required this.kind,
    required this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(smartPlaylistProvider(kind));
    final isDailyMix = kind == SmartKind.dailyMix;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (isDailyMix)
            IconButton(
              icon: const Icon(Icons.shuffle),
              tooltip: 'Reshuffle mix',
              onPressed: () {
                ref.read(dailyMixRefreshProvider.notifier).state++;
              },
            ),
          if (kind == SmartKind.missing)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Remove all missing from library',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Remove missing files?'),
                    content: const Text(
                        'Drops every entry whose file is no longer on the phone. '
                        'They stop appearing in Songs, albums and playlists. '
                        'Nothing on disk is touched.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                final n = await ref
                    .read(libraryRepositoryProvider)
                    .pruneMissingFiles();
                ref.invalidate(allTracksProvider);
                ref.invalidate(albumsProvider);
                ref.invalidate(artistsProvider);
                ref.invalidate(foldersProvider);
                ref.invalidate(smartPlaylistProvider(kind));
                messenger.showSnackBar(
                  SnackBar(content: Text('Removed $n missing entries')),
                );
              },
            ),
          tracksAsync.maybeWhen(
            data: (tracks) => tracks.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.play_arrow),
                    tooltip: 'Play all',
                    onPressed: () => ref
                        .read(playbackControllerProvider.notifier)
                        .playFromList(tracks, 0),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tracks) {
          if (tracks.isEmpty) return const Center(child: Text('Empty'));
          return RefreshIndicator(
            onRefresh: () async {
              if (isDailyMix) {
                ref.read(dailyMixRefreshProvider.notifier).state++;
              } else {
                ref.invalidate(smartPlaylistProvider(kind));
              }
            },
            child: ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (ctx, i) => TrackTile(
                track: tracks[i],
                onTap: () => ref
                    .read(playbackControllerProvider.notifier)
                    .playFromList(tracks, i),
              ),
            ),
          );
        },
      ),
    );
  }
}
