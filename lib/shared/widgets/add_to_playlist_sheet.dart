import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../providers/library_providers.dart';

/// Bottom sheet listing every playlist; tap one to add [track] to it, or
/// create a new playlist on the spot. Shared by the song long-press menu and
/// the now-playing screen so both behave identically.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final repo = ref.read(libraryRepositoryProvider);
  final playlists = await repo.getPlaylists();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            title: Text(
              'Add "${track.title}" to…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(ctx).textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          if (playlists.isEmpty)
            const ListTile(
              dense: true,
              title: Text('No playlists yet — create one below'),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in playlists)
                  ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: Text(p.name),
                    onTap: () async {
                      await repo.addToPlaylist(p.id, track.id);
                      ref.invalidate(playlistTracksProvider(p.id));
                      if (ctx.mounted) Navigator.pop(ctx);
                      messenger.showSnackBar(
                        SnackBar(content: Text('Added to ${p.name}')),
                      );
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New playlist'),
            onTap: () async {
              Navigator.pop(ctx);
              if (!context.mounted) return;
              final controller = TextEditingController();
              final name = await showDialog<String>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('New playlist'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Name'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(d, controller.text.trim()),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              );
              if (name == null || name.isEmpty) return;
              final pid = await repo.createPlaylist(name);
              await repo.addToPlaylist(pid, track.id);
              ref.invalidate(playlistsProvider);
              ref.invalidate(playlistTracksProvider(pid));
              messenger.showSnackBar(
                SnackBar(content: Text('Created "$name" and added song')),
              );
            },
          ),
        ],
      ),
    ),
  );
}
