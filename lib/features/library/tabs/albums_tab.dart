import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../data/repositories/library_repository.dart';
import '../../../playback/playback_controller.dart';
import '../../../shared/models/album.dart';
import '../../../shared/providers/library_providers.dart';
import '../../../shared/widgets/album_tile.dart';
import '../album_detail_screen.dart';

class AlbumsTab extends ConsumerStatefulWidget {
  const AlbumsTab({super.key});

  @override
  ConsumerState<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends ConsumerState<AlbumsTab> {
  GridDensity get _density {
    final s = ref
        .read(sharedPreferencesProvider)
        .getString(PrefsKeys.albumsViewDensity);
    return GridDensity.values.firstWhere(
      (d) => d.name == s,
      orElse: () => GridDensity.roomy,
    );
  }

  Future<void> _toggleDensity() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final next = _density == GridDensity.roomy
        ? GridDensity.compact
        : GridDensity.roomy;
    await prefs.setString(PrefsKeys.albumsViewDensity, next.name);
    setState(() {});
  }

  Future<void> _quickActions(BuildContext context, AlbumKey key) async {
    final tracks =
        await ref.read(libraryRepositoryProvider).tracksInAlbum(key);
    if (tracks.isEmpty || !context.mounted) return;
    final pb = ref.read(playbackControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(key.album,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${tracks.length} songs'),
              dense: true,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Play'),
              onTap: () {
                Navigator.pop(ctx);
                pb.playFromList(tracks, 0, shuffle: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shuffle),
              title: const Text('Shuffle'),
              onTap: () {
                Navigator.pop(ctx);
                pb.playFromList(tracks, 0, shuffle: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_play_next),
              title: const Text('Play next'),
              onTap: () async {
                Navigator.pop(ctx);
                await pb.playAllNext(tracks);
                messenger.showSnackBar(SnackBar(
                    content: Text('Playing ${tracks.length} songs next')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_to_queue),
              title: const Text('Add to queue'),
              onTap: () async {
                Navigator.pop(ctx);
                await pb.addAllToQueue(tracks);
                messenger.showSnackBar(SnackBar(
                    content: Text('Queued ${tracks.length} songs')));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(albumsProvider);
    final compact = _density == GridDensity.compact;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            await ref.read(libraryRepositoryProvider).rescan();
            ref.invalidate(albumsProvider);
            ref.invalidate(allTracksProvider);
          },
          child: albums.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                ListView(children: [Center(child: Text('Error: $e'))]),
            data: (list) {
              if (list.isEmpty) {
                return ListView(children: const [
                  SizedBox(height: 100),
                  Center(child: Text('No albums')),
                ]);
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 60),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: compact ? 110 : 180,
                  mainAxisSpacing: compact ? 8 : 12,
                  crossAxisSpacing: compact ? 8 : 12,
                  childAspectRatio: compact ? 0.95 : 0.78,
                ),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final album = list[i];
                  return GestureDetector(
                    onLongPress: () => _quickActions(context, album.key),
                    child: AlbumTile(
                      album: album,
                      showLabels: !compact,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AlbumDetailScreen(albumKey: album.key),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Material(
            elevation: 2,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: compact ? 'Switch to roomy' : 'Switch to compact',
              icon: Icon(compact ? Icons.grid_view : Icons.apps),
              onPressed: _toggleDensity,
            ),
          ),
        ),
      ],
    );
  }
}
