import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audiotags/audiotags.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../scanner/library_scanner.dart';
import '../../shared/models/album.dart';

class LibraryRepository {
  final AppDatabase db;
  final LibraryScanner scanner;

  LibraryRepository(this.db, this.scanner);

  // Tag and cover writes to the music files that failed, as short messages.
  // The app shows them; before, these failures were swallowed.
  final _writeErrors = StreamController<String>.broadcast();
  Stream<String> get writeErrors => _writeErrors.stream;

  void dispose() => _writeErrors.close();

  Future<List<Track>> allTracks() => db.allTracks();
  Stream<List<Track>> watchAllTracks() => db.watchAllTracks();

  Future<List<AlbumSummary>> albums() async {
    final tracks = await db.allTracks();
    final map = <AlbumKey, List<Track>>{};
    for (final t in tracks) {
      if (t.album.isEmpty) continue;
      final aa = t.albumArtist.isEmpty ? t.artist : t.albumArtist;
      map.putIfAbsent(AlbumKey(t.album, aa), () => []).add(t);
    }
    final result = map.entries.map((e) {
      final tt = e.value..sort((a, b) {
          final d = a.discNumber.compareTo(b.discNumber);
          if (d != 0) return d;
          return a.trackNumber.compareTo(b.trackNumber);
        });
      final art = tt.firstWhere(
        (t) => t.artUri.isNotEmpty,
        orElse: () => tt.first,
      );
      return AlbumSummary(
        album: e.key.album,
        albumArtist: e.key.albumArtist,
        year: tt.first.year,
        trackCount: tt.length,
        artUri: art.artUri.isEmpty ? null : art.artUri,
        tracks: tt,
      );
    }).toList()
      ..sort((a, b) {
        final aa = a.albumArtist.toLowerCase();
        final bb = b.albumArtist.toLowerCase();
        final c = aa.compareTo(bb);
        if (c != 0) return c;
        if (a.year != b.year && a.year != 0 && b.year != 0) {
          return a.year.compareTo(b.year);
        }
        return a.album.toLowerCase().compareTo(b.album.toLowerCase());
      });
    return result;
  }

  Future<List<ArtistSummary>> artists() async {
    final tracks = await db.allTracks();
    final byArtist = <String, List<Track>>{};
    for (final t in tracks) {
      final key = t.albumArtist.isEmpty ? t.artist : t.albumArtist;
      if (key.isEmpty) continue;
      byArtist.putIfAbsent(key, () => []).add(t);
    }
    final result = byArtist.entries.map((e) {
      final albums = e.value.map((t) => t.album).where((a) => a.isNotEmpty).toSet();
      final art = e.value.firstWhere(
        (t) => t.artUri.isNotEmpty,
        orElse: () => e.value.first,
      );
      return ArtistSummary(
        name: e.key,
        albumCount: albums.length,
        trackCount: e.value.length,
        artUri: art.artUri.isEmpty ? null : art.artUri,
      );
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<List<FolderSummary>> folders() async {
    final tracks = await db.allTracks();
    final byFolder = <String, List<Track>>{};
    for (final t in tracks) {
      byFolder.putIfAbsent(t.folderUri, () => []).add(t);
    }
    return byFolder.entries.map((e) {
      final first = e.value.first;
      return FolderSummary(
        uri: e.key,
        displayPath: first.folderPath,
        trackCount: e.value.length,
      );
    }).toList()
      ..sort((a, b) => a.displayPath.toLowerCase().compareTo(b.displayPath.toLowerCase()));
  }

  Future<List<Track>> tracksInAlbum(AlbumKey k) =>
      db.tracksInAlbum(k.album, k.albumArtist);
  Future<List<Track>> tracksByArtist(String artist) =>
      db.tracksByArtist(artist);
  Future<List<Track>> tracksInFolder(String folderUri) =>
      db.tracksInFolder(folderUri);

  Future<int> createPlaylist(String name) => db.createPlaylist(name);
  Future<void> renamePlaylist(int id, String name) => db.renamePlaylist(id, name);
  Future<void> deletePlaylist(int id) => db.deletePlaylist(id);
  Future<List<Playlist>> getPlaylists() => db.select(db.playlists).get();
  Future<List<Track>> getPlaylistTracks(int id) => db.tracksInPlaylist(id);
  Future<void> addToPlaylist(int playlistId, int trackId) =>
      db.addToPlaylist(playlistId, trackId);

  Future<void> setFavorite(int trackId, bool fav) =>
      db.setFavorite(trackId, fav);
  Future<void> recordPlay(int trackId) => db.recordPlay(trackId);
  Future<void> recordSkip(int trackId) => db.recordSkip(trackId);
  Future<void> setRating(int trackId, int rating) =>
      db.setRating(trackId, rating);
  Future<List<Track>> recentlyPlayed({int limit = 200}) =>
      db.recentlyPlayed(limit: limit);
  Future<List<Track>> highlyRated({int min = 4}) => db.highlyRated(min: min);

  /// Apply image bytes as the cover for every track in the album.
  ///
  /// Two layers:
  ///  1. A cached copy in the app's PRIVATE dir + artUri in the DB — instant
  ///     UI update, invisible to the phone's gallery.
  ///  2. The picture is EMBEDDED into each audio file's own tag, so the art
  ///     travels with the music: it survives rescans and clear-and-rescan,
  ///     shows in any other player, and no loose photo needs to live on the
  ///     phone. Stale cached covers for this album are deleted first.
  Future<String> setAlbumArtFromBytes(
    AlbumKey key,
    List<int> bytes, {
    String ext = '.jpg',
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'album_art'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = '${key.album}_${key.albumArtist}'
        .replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');

    // Drop older cached covers for this album (any extension), including
    // copies in the legacy fetched-art dir, so changes don't pile up files.
    for (final d in [dir, Directory(p.join(docs.path, 'album_art_fetched'))]) {
      try {
        if (!await d.exists()) continue;
        await for (final f in d.list()) {
          if (f is File &&
              p.basenameWithoutExtension(f.path) == safe) {
            await f.delete();
          }
        }
      } catch (_) {}
    }

    final destPath = p.join(dir.path, '$safe$ext');
    final f = File(destPath);
    await f.writeAsBytes(bytes);
    final uri = 'file://$destPath';
    await db.setAlbumArt(key.album, key.albumArtist, uri);

    // Best-effort: write the cover into the files themselves.
    await _embedArtIntoAlbumFiles(key, bytes, ext);
    return uri;
  }

  /// Move a track into [album]: retags the file (album / album-artist /
  /// track number, preserving everything else including embedded art) and
  /// updates the library DB. Used by the album "Manage songs" screen.
  Future<void> assignTrackToAlbum(
    Track t, {
    required String album,
    required String albumArtist,
    int? trackNumber,
  }) =>
      _retagAlbumFields(t,
          album: album, albumArtist: albumArtist, trackNumber: trackNumber);

  /// Detach a track from its album — it stays in the library as a single.
  Future<void> removeTrackFromAlbum(Track t) =>
      _retagAlbumFields(t, album: '', albumArtist: '', trackNumber: 0);

  Future<void> _retagAlbumFields(
    Track t, {
    required String album,
    required String albumArtist,
    int? trackNumber,
  }) async {
    // Best-effort write into the file's own tag so the change is permanent
    // and survives rescans. content:// URIs can't be rewritten — DB only.
    try {
      String path = t.uri;
      if (path.startsWith('file://')) path = path.substring(7);
      if (!path.startsWith('content://')) {
        Tag? existing;
        try {
          existing = await AudioTags.read(path);
        } catch (_) {}
        final tag = Tag(
          title: existing?.title ?? t.title,
          trackArtist:
              existing?.trackArtist ?? (t.artist.isEmpty ? null : t.artist),
          album: album.isEmpty ? null : album,
          albumArtist: albumArtist.isEmpty ? null : albumArtist,
          genre: existing?.genre,
          year: existing?.year,
          trackNumber: trackNumber ?? existing?.trackNumber,
          trackTotal: existing?.trackTotal,
          discNumber: existing?.discNumber,
          discTotal: existing?.discTotal,
          duration: existing?.duration,
          pictures: existing?.pictures ?? const [],
        );
        await AudioTags.write(path, tag);
      }
    } catch (_) {
      _writeErrors.add("Saved in the library only. The file couldn't be "
          'changed; allow all files access in Settings.');
    }

    final companion = trackNumber == null
        ? TracksCompanion(
            album: Value(album),
            albumArtist: Value(albumArtist),
          )
        : TracksCompanion(
            album: Value(album),
            albumArtist: Value(albumArtist),
            trackNumber: Value(trackNumber),
          );
    await (db.update(db.tracks)..where((tt) => tt.id.equals(t.id)))
        .write(companion);
  }

  /// Write [bytes] as the front-cover picture in every track of the album.
  /// Files that can't be written are skipped and reported in [writeErrors].
  Future<void> _embedArtIntoAlbumFiles(
    AlbumKey key,
    List<int> bytes,
    String ext,
  ) async {
    final tracks = await db.tracksInAlbum(key.album, key.albumArtist);
    final mime = ext == '.png' ? MimeType.png : MimeType.jpeg;
    final picture = Picture(
      pictureType: PictureType.coverFront,
      mimeType: mime,
      bytes: Uint8List.fromList(bytes),
    );
    var failed = 0;
    for (final t in tracks) {
      try {
        String path = t.uri;
        if (path.startsWith('file://')) path = path.substring(7);
        if (path.startsWith('content://')) continue; // can't rewrite via SAF
        // A read error lands in the catch below: writing after a failed read
        // would blank the title and artist. (null just means no tag yet.)
        final existing = await AudioTags.read(path);
        final tag = Tag(
          title: existing?.title,
          trackArtist: existing?.trackArtist,
          album: existing?.album,
          albumArtist: existing?.albumArtist,
          genre: existing?.genre,
          year: existing?.year,
          trackNumber: existing?.trackNumber,
          trackTotal: existing?.trackTotal,
          discNumber: existing?.discNumber,
          discTotal: existing?.discTotal,
          duration: existing?.duration,
          pictures: [picture],
        );
        await AudioTags.write(path, tag);
      } catch (_) {
        failed++;
      }
    }
    if (failed > 0) {
      final files = failed == 1 ? '1 file' : '$failed files';
      _writeErrors.add("Cover saved in the app, but couldn't be written into "
          '$files. Allow all files access in Settings.');
    }
  }

  /// Backwards-compat wrapper if any caller still passes a File.
  Future<String> setAlbumArtFromFile(AlbumKey key, File source) async {
    final bytes = await source.readAsBytes();
    final ext = p.extension(source.path).toLowerCase().isEmpty
        ? '.jpg'
        : p.extension(source.path).toLowerCase();
    return setAlbumArtFromBytes(key, bytes, ext: ext);
  }

  Future<void> exportPlaylistM3U(int playlistId) async {
    final pl = await (db.select(db.playlists)..where((p) => p.id.equals(playlistId)))
        .getSingle();
    final tracks = await db.tracksInPlaylist(playlistId);
    final lines = <String>['#EXTM3U'];
    for (final t in tracks) {
      lines.add('#EXTINF:${(t.durationMs / 1000).round()},${t.artist} - ${t.title}');
      lines.add(t.uri);
    }
    final dir = await getExternalStorageDirectory();
    final dest = dir ?? await getApplicationDocumentsDirectory();
    final file = File(p.join(dest.path, '${pl.name}.m3u'));
    await file.writeAsString(lines.join('\n'));
  }

  Future<void> rescan() async {
    final folders = await db.getMusicFolders();
    for (final f in folders) {
      await scanner.scanFolder(f.uri, db);
    }
    await _pruneThenDedupe();
  }

  /// Drop rows whose file is gone, then dedupe. The order matters: after a
  /// folder moves, its old rows (lower ids) are still there, so deduping
  /// first kept the old rows and deleted the new ones, and the prune then
  /// removed the old ones too, losing the songs from the library.
  Future<void> _pruneThenDedupe() async {
    try {
      await pruneMissingFiles();
    } catch (_) {}
    // Dedupe so users never see two rows for the same song, whether the
    // cause is symlinks, duplicate files on disk, or rows from older builds.
    try {
      await db.dedupeTracks();
    } catch (_) {}
  }

  /// Remove library rows whose audio file no longer exists on disk.
  /// Returns how many were removed. content:// rows can't be checked and
  /// are left alone.
  Future<int> pruneMissingFiles() async {
    final all = await db.allTracks();
    final gone = <int>[];
    var checked = 0;
    for (final t in all) {
      final uri = t.uri;
      if (uri.startsWith('content://')) continue;
      final path = uri.startsWith('file://') ? uri.substring(7) : uri;
      checked++;
      try {
        if (!await File(path).exists()) gone.add(t.id);
      } catch (_) {}
    }
    // Every file missing means storage or permission trouble, not a deleted
    // library. Keep the rows (and their plays and playlists).
    if (checked > 0 && gone.length == checked) return 0;
    await db.deleteTracksByIds(gone);
    return gone.length;
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) =>
      db.removeTrackFromPlaylist(playlistId, trackId);
  Future<int> countPlaylistTracks(int playlistId) =>
      db.countPlaylistTracks(playlistId);

  Future<void> clearAndRescan() async {
    await db.wipeAllTracks();
    await rescan();
  }

  /// Deletes the track's file from disk AND removes it from the library DB.
  /// Returns true if both succeed, false otherwise (e.g. permission denied).
  Future<bool> deleteTrackFromDisk(Track t) async {
    bool fileGone = false;
    try {
      String path = t.uri;
      if (path.startsWith('file://')) path = path.substring(7);
      if (path.startsWith('content://')) {
        // Can't easily delete content:// URIs without SAF prompts; skip file
        // delete and just remove the DB row.
        fileGone = false;
      } else {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
          fileGone = true;
        } else {
          fileGone = true; // already gone
        }
      }
    } catch (_) {
      fileGone = false;
    }
    try {
      await db.deleteTrackByUri(t.uri);
    } catch (_) {}
    return fileGone;
  }

  /// Deletes every track in the album from disk + DB.
  /// Returns (deletedCount, failedCount).
  Future<(int, int)> deleteAlbumFromDisk(AlbumKey key) async {
    final tracks = await db.tracksInAlbum(key.album, key.albumArtist);
    int ok = 0;
    int failed = 0;
    for (final t in tracks) {
      final r = await deleteTrackFromDisk(t);
      if (r) {
        ok++;
      } else {
        failed++;
      }
    }
    return (ok, failed);
  }

  Future<void> addMusicFolder(String uri, String displayName) async {
    await db.addMusicFolder(uri, displayName);
    await scanner.scanFolder(uri, db);
    await _pruneThenDedupe();
  }

  Future<void> removeMusicFolder(String uri) => db.removeMusicFolder(uri);
  Future<List<MusicFolder>> getMusicFolders() => db.getMusicFolders();
}

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final repo = LibraryRepository(
    ref.watch(databaseProvider),
    ref.watch(libraryScannerProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});
