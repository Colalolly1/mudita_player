import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/widgets/cover_art.dart';

/// Search the whole library and tap + to drop songs into a playlist.
/// Songs already in the playlist show a check instead of a +.
class PlaylistAddSongsScreen extends ConsumerStatefulWidget {
  final int playlistId;
  final String playlistName;
  const PlaylistAddSongsScreen({
    super.key,
    required this.playlistId,
    required this.playlistName,
  });

  @override
  ConsumerState<PlaylistAddSongsScreen> createState() =>
      _PlaylistAddSongsScreenState();
}

class _PlaylistAddSongsScreenState
    extends ConsumerState<PlaylistAddSongsScreen> {
  final _search = TextEditingController();
  int _added = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add(Track t) async {
    await ref
        .read(libraryRepositoryProvider)
        .addToPlaylist(widget.playlistId, t.id);
    ref.invalidate(playlistTracksProvider(widget.playlistId));
    setState(() => _added++);
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allTracksProvider);
    final inPlaylist = ref
            .watch(playlistTracksProvider(widget.playlistId))
            .maybeWhen(
              data: (ts) => ts.map((t) => t.id).toSet(),
              orElse: () => <int>{},
            );
    final q = _search.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: Text('Add to ${widget.playlistName}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_added > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text('+$_added',
                    style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search songs, artists, albums',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Expanded(
            child: allAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                final list = all
                    .where((t) =>
                        q.isEmpty ||
                        t.title.toLowerCase().contains(q) ||
                        t.artist.toLowerCase().contains(q) ||
                        t.album.toLowerCase().contains(q))
                    .toList()
                  ..sort((a, b) => a.title
                      .toLowerCase()
                      .compareTo(b.title.toLowerCase()));
                if (list.isEmpty) {
                  return const Center(child: Text('No matches'));
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final t = list[i];
                    final already = inPlaylist.contains(t.id);
                    return ListTile(
                      dense: true,
                      leading: CoverArt(
                        artUri: t.artUri.isEmpty ? null : t.artUri,
                        size: 36,
                      ),
                      title: Text(t.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [t.artist, t.album]
                            .where((s) => s.isNotEmpty)
                            .join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: already
                          ? Icon(Icons.check,
                              color: Theme.of(context).colorScheme.primary)
                          : IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => _add(t),
                            ),
                      onTap: already ? null : () => _add(t),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
