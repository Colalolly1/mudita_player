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

/// A wall of covers, edge to edge. The cover is the label; the name and
/// artist are one tap away. Long-press for play, shuffle, queue.
class AlbumsTab extends ConsumerStatefulWidget {
  const AlbumsTab({super.key});

  @override
  ConsumerState<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends ConsumerState<AlbumsTab> {
  /// The density setting still applies: roomy is three across, compact four.
  int get _columns {
    final s = ref
        .read(sharedPreferencesProvider)
        .getString(PrefsKeys.albumsViewDensity);
    return s == GridDensity.compact.name ? 4 : 3;
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
              subtitle: Text('${key.albumArtist} · ${tracks.length} songs',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              dense: true,
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('Play'),
              onTap: () {
                Navigator.pop(ctx);
                pb.playFromList(tracks, 0, shuffle: false);
              },
            ),
            ListTile(
              title: const Text('Shuffle'),
              onTap: () {
                Navigator.pop(ctx);
                pb.playFromList(tracks, 0, shuffle: true);
              },
            ),
            ListTile(
              title: const Text('Play next'),
              onTap: () async {
                Navigator.pop(ctx);
                await pb.playAllNext(tracks);
                messenger.showSnackBar(SnackBar(
                    content: Text('Playing ${tracks.length} songs next')));
              },
            ),
            ListTile(
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

    return RefreshIndicator(
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
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final album = list[i];
              return GestureDetector(
                onLongPress: () => _quickActions(context, album.key),
                child: AlbumTile(
                  album: album,
                  showLabels: false,
                  radius: 0,
                  padding: EdgeInsets.zero,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumDetailScreen(albumKey: album.key),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
