import 'dart:io';

import 'package:audiotags/audiotags.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../art_loader/art_loader.dart';

/// What one folder scan found.
class FolderScan {
  /// Audio files found and kept in the library.
  final int count;

  /// The canonical folders that were listed to the end. Rows anywhere else
  /// were not checked by this scan, so a prune has to leave them alone.
  final List<String> listedRoots;

  /// False if the folder, or any of its roots, couldn't be listed: not
  /// there (SD card not mounted, folder renamed) or the listing failed.
  final bool listed;

  /// Paths added to the library by this scan, for spotting moved files.
  final Set<String> inserted;

  const FolderScan({
    required this.count,
    required this.listedRoots,
    required this.listed,
    required this.inserted,
  });
}

/// Pure-Dart filesystem scanner. Walks a folder recursively, reads tags via
/// the `audiotags` package (no native MediaStore plugin needed).
class LibraryScanner {
  final ArtLoader _artLoader;

  LibraryScanner(this._artLoader);

  static const _audioExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.ogg',
    '.opus',
    '.wav',
    '.aac',
    '.wma',
  };

  Future<FolderScan> scanFolder(String folderUri, AppDatabase db) async {
    // Pre-scan cleanup: drop any rows pointing into /sdcard/ (a symlink to
    // /storage/emulated/0/) so we never end up with two paths for one file.
    try {
      await db.customStatement(
        "DELETE FROM tracks WHERE uri LIKE '/sdcard/%'",
      );
    } catch (_) {}

    // Strip any historical scheme prefixes; we only do filesystem walks now.
    String path = folderUri;
    if (path.startsWith('file://')) path = path.substring(7);
    if (path.startsWith('mediastore://') || path.startsWith('content://')) {
      // Best-effort defaults if the entry came from an old MediaStore add.
      const defaults = [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/sdcard/Music',
        '/sdcard/Download',
      ];
      final result = _ScanProgress();
      var anyExisted = false;
      var allListed = true;
      for (final d in defaults) {
        final dir = Directory(d);
        if (!await _exists(dir)) continue;
        anyExisted = true;
        if (!await _scanFilesystem(dir, db, result)) allListed = false;
      }
      return result.done(listed: anyExisted && allListed);
    }

    final result = _ScanProgress();
    final dir = Directory(path);
    if (!await _exists(dir)) return result.done(listed: false);
    final listed = await _scanFilesystem(dir, db, result);
    return result.done(listed: listed);
  }

  Future<bool> _exists(Directory dir) async {
    try {
      return await dir.exists();
    } catch (_) {
      return false;
    }
  }

  /// Resolve `/sdcard/...` to `/storage/emulated/0/...` so every file has one
  /// canonical path. Without this, scanning both roots would double-insert.
  String _canonicalize(String path) {
    if (path.startsWith('/sdcard/')) {
      return '/storage/emulated/0/${path.substring(8)}';
    }
    if (path == '/sdcard') return '/storage/emulated/0';
    return path;
  }

  /// Scans [dir] into the library. Returns true only if the whole folder
  /// was listed; a listing error stops the walk and returns false.
  Future<bool> _scanFilesystem(
    Directory dir,
    AppDatabase db,
    _ScanProgress result,
  ) async {
    try {
      await _walk(dir, db, result);
      result.listedRoots.add(p.normalize(_canonicalize(dir.path)));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _walk(
    Directory dir,
    AppDatabase db,
    _ScanProgress result,
  ) async {
    final cacheDir = await getApplicationDocumentsDirectory();
    final artDir = Directory(p.join(cacheDir.path, 'art'));
    if (!await artDir.exists()) await artDir.create(recursive: true);

    // What the library already has, by path, so files that haven't changed
    // since the last scan can be skipped without opening them.
    final all = await db.allTracks();
    final known = {for (final t in all) t.uri: t};
    // And by song, so a second copy of a song already in the library isn't
    // added only for dedupe to remove it again on every scan.
    final bySong = <String, List<(String, int)>>{};
    for (final t in all) {
      final key = sameSongKey(t.title, t.artist, t.album, t.trackNumber);
      if (key == null) continue;
      bySong.putIfAbsent(key, () => []).add((t.uri, t.durationMs));
    }
    final folderCovers = <String, String?>{};

    final stream = dir.list(recursive: true, followLinks: false);
    await for (final entity in stream) {
      try {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!_audioExtensions.contains(ext)) continue;

        final canon = _canonicalize(entity.path);
        FileStat? stat;
        try {
          stat = await entity.stat();
        } catch (_) {}

        final old = known[canon];
        if (old != null &&
            stat != null &&
            old.fileSize == stat.size &&
            old.dateModified == stat.modified.millisecondsSinceEpoch) {
          // Unchanged. Only look for a folder cover if the row has no art,
          // e.g. because All files access was granted since the last scan.
          if (old.artUri.isEmpty) {
            final folder = p.dirname(entity.path);
            if (!folderCovers.containsKey(folder)) {
              folderCovers[folder] =
                  await _artLoader.folderCoverFor(entity.path);
            }
            final cover = folderCovers[folder];
            if (cover != null) await db.setTrackArt(old.id, cover);
          }
          result.count++;
          continue;
        }

        Tag? tag;
        try {
          tag = await AudioTags.read(entity.path);
        } catch (_) {}
        // A known file that can't be read right now keeps its row as it is,
        // rather than having its title and artist blanked.
        if (old != null && tag == null) {
          result.count++;
          continue;
        }

        final title = (tag?.title?.isNotEmpty ?? false)
            ? tag!.title!
            : p.basenameWithoutExtension(entity.path);
        final artist = tag?.trackArtist ?? '';
        final album = tag?.album ?? '';
        final trackNumber = tag?.trackNumber ?? 0;
        final durationMs = (tag?.duration ?? 0) * 1000;
        final songKey = sameSongKey(title, artist, album, trackNumber);
        if (old == null && songKey != null) {
          // A copy of a song the library already has, at another path that
          // still exists: leave it out. (If the other file is gone, this is
          // a move; it goes in, and the prune carries the old row over.)
          var copy = false;
          final same = bySong[songKey] ?? const <(String, int)>[];
          for (final (uri, ms) in same) {
            if ((ms - durationMs).abs() > 1000) continue;
            if (await _fileExists(uri)) {
              copy = true;
              break;
            }
          }
          if (copy) continue;
        }

        // A known row keeps the art it has, including a cover picked in the
        // app; only rows without art get it from the folder or the file.
        final keepArt = old != null && old.artUri.isNotEmpty;
        String artUri = '';
        if (!keepArt) {
          try {
            final art =
                await _artLoader.loadFor(entity.path, artDir, tag: tag);
            if (art != null) artUri = art;
          } catch (_) {}
        }

        final companion = TracksCompanion.insert(
          uri: canon,
          filename: p.basename(canon),
          folderUri: p.dirname(canon),
          folderPath: p.dirname(canon),
          title: title,
          artist: Value(artist),
          albumArtist: Value(tag?.albumArtist ?? ''),
          album: Value(album),
          genre: Value(tag?.genre ?? ''),
          year: Value(tag?.year ?? 0),
          trackNumber: Value(trackNumber),
          discNumber: Value(tag?.discNumber ?? 0),
          durationMs: Value(durationMs),
          fileSize: Value(stat?.size ?? 0),
          format: Value(ext.replaceFirst('.', '').toUpperCase()),
          artUri: keepArt ? const Value.absent() : Value(artUri),
          dateAdded: Value(stat?.changed.millisecondsSinceEpoch ?? 0),
          dateModified: Value(stat?.modified.millisecondsSinceEpoch ?? 0),
        );
        await db.upsertTrack(companion);
        if (old == null) {
          result.inserted.add(canon);
          if (songKey != null) {
            bySong.putIfAbsent(songKey, () => []).add((canon, durationMs));
          }
        }
        result.count++;
      } catch (_) {
        // Skip any single-file failure rather than aborting the whole scan.
        continue;
      }
    }
  }

  /// content:// rows can't be checked, so they count as present.
  Future<bool> _fileExists(String uri) async {
    if (uri.startsWith('content://')) return true;
    final path = uri.startsWith('file://') ? uri.substring(7) : uri;
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }
}

class _ScanProgress {
  int count = 0;
  final listedRoots = <String>[];
  final inserted = <String>{};

  FolderScan done({required bool listed}) => FolderScan(
        count: count,
        listedRoots: listedRoots,
        listed: listed,
        inserted: inserted,
      );
}

final libraryScannerProvider = Provider<LibraryScanner>((ref) {
  return LibraryScanner(ref.watch(artLoaderProvider));
});
