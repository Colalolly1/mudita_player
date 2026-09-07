import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/track_tile.dart';
import '../../shared/providers/library_providers.dart';
import '../../playback/playback_controller.dart';
import 'playlist_add_songs_screen.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final int playlistId;
  final String name;
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.name,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(playlistTracksProvider(playlistId));
    // Live name so a rename shows immediately without leaving the screen.
    final liveName = ref.watch(playlistsProvider).maybeWhen(
          data: (list) => list
              .where((p) => p.id == playlistId)
              .map((p) => p.name)
              .firstOrNull,
          orElse: () => null,
        ) ??
        name;
    final pb = ref.read(playbackControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(liveName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Add songs',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlaylistAddSongsScreen(
                  playlistId: playlistId,
                  playlistName: liveName,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final repo = ref.read(libraryRepositoryProvider);
              final messenger = ScaffoldMessenger.of(context);
              if (v == 'rename') {
                final controller = TextEditingController(text: liveName);
                final newName = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Rename'),
                    content: TextField(controller: controller, autofocus: true),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, controller.text.trim()),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
                if (newName != null && newName.isNotEmpty) {
                  await repo.renamePlaylist(playlistId, newName);
                  ref.invalidate(playlistsProvider);
                }
              } else if (v == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete playlist?'),
                    content: const Text(
                        'Only the playlist is removed — your songs stay.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await repo.deletePlaylist(playlistId);
                  ref.invalidate(playlistsProvider);
                  if (context.mounted) Navigator.pop(context);
                }
              } else if (v == 'export') {
                await repo.exportPlaylistM3U(playlistId);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Exported as M3U')),
                );
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'export', child: Text('Export M3U')),
              PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
            ],
          ),
        ],
      ),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tracks) {
          if (tracks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Empty playlist'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlaylistAddSongsScreen(
                          playlistId: playlistId,
                          playlistName: liveName,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add songs'),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    Text(
                      '${tracks.length} songs',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () =>
                          pb.playFromList(tracks, 0, shuffle: false),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Play'),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          pb.playFromList(tracks, 0, shuffle: true),
                      icon: const Icon(Icons.shuffle, size: 18),
                      label: const Text('Shuffle'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (ctx, i) {
                    final t = tracks[i];
                    return Dismissible(
                      key: ValueKey('pl-$playlistId-${t.id}-$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red.withAlpha(40),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.playlist_remove),
                      ),
                      onDismissed: (_) async {
                        await ref
                            .read(libraryRepositoryProvider)
                            .removeTrackFromPlaylist(playlistId, t.id);
                        ref.invalidate(playlistTracksProvider(playlistId));
                      },
                      child: TrackTile(
                        track: t,
                        onTap: () => pb.playFromList(tracks, i),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
