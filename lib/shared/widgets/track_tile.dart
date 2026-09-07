import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_controller.dart';
import '../../data/database/app_database.dart';
import '../../features/tag_editor/tag_editor_screen.dart';
import '../providers/library_providers.dart';
import '../../playback/playback_controller.dart';
import 'add_to_playlist_sheet.dart';
import 'cover_art.dart';

class TrackTile extends ConsumerWidget {
  final Track track;
  final VoidCallback? onTap;
  final bool showAlbum;
  final bool hideArt;

  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.showAlbum = true,
    this.hideArt = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(playbackControllerProvider).current;
    final isPlaying = current?.id == track.id;
    final accent = Theme.of(context).colorScheme.primary;
    final globalHide = ref.watch(themeControllerProvider).hideCoverArt;
    final showArt = !(hideArt || globalHide);

    final subtitle = [
      if (track.artist.isNotEmpty) track.artist,
      if (showAlbum && track.album.isNotEmpty) track.album,
    ].join(' • ');

    return ListTile(
      leading: !showArt
          ? null
          : CoverArt(
              artUri: track.artUri.isEmpty ? null : track.artUri,
              size: 44,
            ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: isPlaying ? accent : null,
        ),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (track.rating > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  track.rating,
                  (_) => Icon(Icons.star, size: 12, color: accent),
                ),
              ),
            ),
          if (track.favorite) Icon(Icons.favorite, size: 14, color: accent),
        ],
      ),
      onTap: onTap,
      onLongPress: () => _showActions(context, ref),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.queue_play_next),
              title: const Text('Play next'),
              onTap: () {
                ref.read(playbackControllerProvider.notifier).playNext(track);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_to_queue),
              title: const Text('Add to queue'),
              onTap: () {
                ref.read(playbackControllerProvider.notifier).addToQueue(track);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: Icon(
                  track.favorite ? Icons.favorite : Icons.favorite_border),
              title: Text(track.favorite ? 'Unfavorite' : 'Favorite'),
              onTap: () async {
                await ref
                    .read(libraryRepositoryProvider)
                    .setFavorite(track.id, !track.favorite);
                ref.invalidate(allTracksProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Rating'),
              trailing: _StarBar(
                value: track.rating,
                onChanged: (v) async {
                  await ref
                      .read(libraryRepositoryProvider)
                      .setRating(track.id, v);
                  ref.invalidate(allTracksProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Add to playlist'),
              onTap: () async {
                Navigator.pop(ctx);
                await showAddToPlaylistSheet(context, ref, track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit tags'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TagEditorScreen(tracks: [track]),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: Colors.redAccent),
              title: const Text('Delete from device',
                  style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('Permanent — removes the file from disk'),
              onTap: () async {
                Navigator.pop(ctx);
                await _confirmAndDelete(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this song?'),
        content: Text(
            'This permanently deletes "${track.title}" from your device. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await ref
        .read(libraryRepositoryProvider)
        .deleteTrackFromDisk(track);
    ref.invalidate(allTracksProvider);
    ref.invalidate(albumsProvider);
    ref.invalidate(artistsProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Deleted "${track.title}"'
            : 'Removed from library; file deletion blocked by system'),
      ),
    );
  }

}

class _StarBar extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _StarBar({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < value;
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: Icon(filled ? Icons.star : Icons.star_border, size: 18),
          onPressed: () => onChanged(value == i + 1 ? 0 : i + 1),
        );
      }),
    );
  }
}
