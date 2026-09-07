import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../shared/models/album.dart';
import '../../shared/providers/library_providers.dart';
import '../../shared/widgets/cover_art.dart';

/// Quiet utility screen (reached via the album's overflow menu) for moving
/// songs in and out of an album. "Remove" detaches the song from the album
/// (it stays in the library as a single); "Add" retags a library song into
/// this album. Both write the file's own tags, so changes are permanent.
class AlbumSongsManagerScreen extends ConsumerStatefulWidget {
  final AlbumKey albumKey;
  const AlbumSongsManagerScreen({super.key, required this.albumKey});

  @override
  ConsumerState<AlbumSongsManagerScreen> createState() =>
      _AlbumSongsManagerScreenState();
}

class _AlbumSongsManagerScreenState
    extends ConsumerState<AlbumSongsManagerScreen> {
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(albumTracksProvider(widget.albumKey));
    ref.invalidate(albumsProvider);
    ref.invalidate(allTracksProvider);
    ref.invalidate(artistsProvider);
  }

  Future<void> _remove(Track t) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(libraryRepositoryProvider).removeTrackFromAlbum(t);
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed "${t.title}" from album')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(Track t, List<Track> current) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var maxNo = 0;
      for (final c in current) {
        if (c.trackNumber > maxNo) maxNo = c.trackNumber;
      }
      await ref.read(libraryRepositoryProvider).assignTrackToAlbum(
            t,
            album: widget.albumKey.album,
            albumArtist: widget.albumKey.albumArtist,
            trackNumber: maxNo + 1,
          );
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "${t.title}" to album')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentAsync = ref.watch(albumTracksProvider(widget.albumKey));
    final allAsync = ref.watch(allTracksProvider);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.albumKey.album,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: currentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (current) {
          final currentIds = current.map((t) => t.id).toSet();
          final q = _search.text.trim().toLowerCase();
          final candidates = allAsync.maybeWhen(
            data: (all) => all
                .where((t) => !currentIds.contains(t.id))
                .where((t) =>
                    q.isEmpty ||
                    t.title.toLowerCase().contains(q) ||
                    t.artist.toLowerCase().contains(q) ||
                    t.album.toLowerCase().contains(q))
                .take(60)
                .toList(),
            orElse: () => const <Track>[],
          );

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'IN THIS ALBUM (${current.length})',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                      ),
                ),
              ),
              if (current.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No songs', style: TextStyle(color: muted)),
                ),
              ...current.map((t) => ListTile(
                    dense: true,
                    leading: CoverArt(
                      artUri: t.artUri.isEmpty ? null : t.artUri,
                      size: 36,
                    ),
                    title: Text(t.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(t.artist,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Remove from album',
                      onPressed: _busy ? null : () => _remove(t),
                    ),
                  )),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'ADD FROM LIBRARY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search your songs',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...candidates.map((t) => ListTile(
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
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Add to this album',
                      onPressed: _busy ? null : () => _add(t, current),
                    ),
                  )),
              const SizedBox(height: 48),
            ],
          );
        },
      ),
    );
  }
}
