import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/cover_fetch/musicbrainz_cover.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/library_repository.dart';
import '../../shared/models/album.dart';
import 'album_songs_manager_screen.dart';
import 'cover_search_screen.dart';
import '../../shared/widgets/track_tile.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/providers/library_providers.dart';
import '../../playback/playback_controller.dart';
import '../tag_editor/tag_editor_screen.dart';

class AlbumDetailScreen extends ConsumerWidget {
  final AlbumKey albumKey;
  const AlbumDetailScreen({super.key, required this.albumKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(albumTracksProvider(albumKey));
    return Scaffold(
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tracks) {
          final firstArt = tracks.firstWhere(
            (t) => t.artUri.isNotEmpty,
            orElse: () => tracks.isEmpty ? _emptyTrack() : tracks.first,
          );
          final totalDur = tracks.fold<int>(0, (a, t) => a + t.durationMs);
          final mins = (totalDur / 60000).round();
          final hasArt = firstArt.artUri.isNotEmpty;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                actions: [
                  IconButton(
                    tooltip: 'Search iTunes for cover',
                    icon: const Icon(Icons.search),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            CoverSearchScreen(albumKey: albumKey),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Pick image from gallery',
                    icon: Icon(hasArt
                        ? Icons.image_outlined
                        : Icons.add_photo_alternate_outlined),
                    onPressed: () => _pickCover(context, ref),
                  ),
                  IconButton(
                    tooltip: 'Paste image URL',
                    icon: const Icon(Icons.link),
                    onPressed: () => _pasteUrl(context, ref),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) async {
                      if (v == 'edit_album') {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TagEditorScreen(tracks: tracks),
                        ));
                      } else if (v == 'auto_fetch') {
                        await _autoFetchCover(context, ref);
                      } else if (v == 'manage_songs') {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              AlbumSongsManagerScreen(albumKey: albumKey),
                        ));
                      } else if (v == 'delete_album') {
                        await _confirmDeleteAlbum(context, ref, tracks.length);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'auto_fetch',
                        child: Text('Auto-fetch from iTunes'),
                      ),
                      PopupMenuItem(
                        value: 'edit_album',
                        child: Text('Edit album info (all songs)'),
                      ),
                      PopupMenuItem(
                        value: 'manage_songs',
                        child: Text('Manage songs…'),
                      ),
                      PopupMenuItem(
                        value: 'delete_album',
                        child: Text(
                          'Delete album (permanent)',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      CoverArt(
                        artUri: hasArt ? firstArt.artUri : null,
                        size: double.infinity,
                      ),
                      if (!hasArt)
                        Center(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor:
                                  Colors.black.withValues(alpha: 0.4),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _pickCover(context, ref),
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: const Text('Add cover'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Text(albumKey.album,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(albumKey.albumArtist,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${tracks.length} tracks • $mins min',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () => ref
                              .read(playbackControllerProvider.notifier)
                              .playFromList(tracks, 0, shuffle: false),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () => ref
                              .read(playbackControllerProvider.notifier)
                              .playFromList(tracks, 0, shuffle: true),
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Shuffle'),
                        ),
                      ],
                    ),
                  ]),
                ),
              ),
              SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (ctx, i) => TrackTile(
                  track: tracks[i],
                  showAlbum: false,
                  // Tapping a track in an album plays the album in its shown
                  // order from that point — never shuffled.
                  onTap: () => ref
                      .read(playbackControllerProvider.notifier)
                      .playFromList(tracks, i, shuffle: false),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteAlbum(
      BuildContext context, WidgetRef ref, int count) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entire album?'),
        content: Text(
            'This permanently deletes all $count songs in "${albumKey.album}" from your device. This cannot be undone.'),
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
    final (ok, failed) = await ref
        .read(libraryRepositoryProvider)
        .deleteAlbumFromDisk(albumKey);
    ref.invalidate(albumsProvider);
    ref.invalidate(allTracksProvider);
    ref.invalidate(artistsProvider);
    ref.invalidate(albumTracksProvider(albumKey));
    messenger.showSnackBar(
      SnackBar(
        content: Text(failed == 0
            ? 'Deleted $ok songs'
            : 'Deleted $ok; $failed could not be removed from disk'),
      ),
    );
    if (navigator.canPop()) navigator.pop();
  }

  Future<void> _pasteUrl(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste image URL'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    if (!url.startsWith('http')) {
      messenger.showSnackBar(
        const SnackBar(content: Text('URL must start with http or https')),
      );
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Downloading…')));
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text('Download failed: HTTP ${res.statusCode}')),
        );
        return;
      }
      String ext = '.jpg';
      final lower = url.toLowerCase();
      if (lower.contains('.png')) ext = '.png';
      if (lower.contains('.webp')) ext = '.webp';
      await ref
          .read(libraryRepositoryProvider)
          .setAlbumArtFromBytes(albumKey, res.bodyBytes, ext: ext);
      ref.invalidate(albumTracksProvider(albumKey));
      ref.invalidate(albumsProvider);
      ref.invalidate(allTracksProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Cover updated')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _autoFetchCover(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Searching iTunes…')),
    );
    final result = await ref
        .read(musicBrainzCoverProvider)
        .fetchForAlbumDetailed(albumKey);
    ref.invalidate(albumTracksProvider(albumKey));
    ref.invalidate(albumsProvider);
    ref.invalidate(allTracksProvider);
    messenger.clearSnackBars();
    if (result.uri != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Cover fetched (${result.reason})')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(result.reason),
          action: SnackBarAction(
            label: 'PICK MANUAL',
            onPressed: () => _pickCover(context, ref),
          ),
        ),
      );
    }
  }

  Future<void> _pickCover(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // load bytes — content:// paths often fail otherwise
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;

      List<int>? bytes = picked.bytes;
      // Fall back to reading from path if bytes weren't loaded for some reason
      if (bytes == null && picked.path != null) {
        try {
          bytes = await File(picked.path!).readAsBytes();
        } catch (_) {}
      }
      if (bytes == null || bytes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not read the picked image')),
        );
        return;
      }

      String ext = '.jpg';
      final name = picked.name.toLowerCase();
      if (name.endsWith('.png')) {
        ext = '.png';
      } else if (name.endsWith('.webp')) {
        ext = '.webp';
      } else if (name.endsWith('.jpeg') || name.endsWith('.jpg')) {
        ext = '.jpg';
      }

      await ref
          .read(libraryRepositoryProvider)
          .setAlbumArtFromBytes(albumKey, bytes, ext: ext);
      ref.invalidate(albumTracksProvider(albumKey));
      ref.invalidate(albumsProvider);
      ref.invalidate(allTracksProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Cover updated')),
      );
    } catch (e, st) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
      debugPrint('Cover pick failed: $e\n$st');
    }
  }

  Track _emptyTrack() => Track(
        id: 0,
        uri: '',
        filename: '',
        folderUri: '',
        folderPath: '',
        title: '',
        artist: '',
        albumArtist: '',
        album: '',
        genre: '',
        year: 0,
        trackNumber: 0,
        discNumber: 0,
        durationMs: 0,
        bitrate: 0,
        sampleRate: 0,
        fileSize: 0,
        format: '',
        artUri: '',
        dateAdded: 0,
        dateModified: 0,
        lastPlayedAt: 0,
        playCount: 0,
        favorite: false,
        rating: 0,
        skipCount: 0,
        lyrics: '',
        syncedLyricsPath: '',
      );
}
