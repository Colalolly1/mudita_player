import 'dart:io';

import 'package:audiotags/audiotags.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../art_loader/art_loader.dart';

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

  Future<int> scanFolder(String folderUri, AppDatabase db) async {
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
      int total = 0;
      for (final d in defaults) {
        final dir = Directory(d);
        if (await dir.exists()) {
          total += await _scanFilesystem(dir, db);
        }
      }
      return total;
    }

    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    return _scanFilesystem(dir, db);
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

  Future<int> _scanFilesystem(Directory dir, AppDatabase db) async {
    final cacheDir = await getApplicationDocumentsDirectory();
    final artDir = Directory(p.join(cacheDir.path, 'art'));
    if (!await artDir.exists()) await artDir.create(recursive: true);

    int count = 0;
    final stream = dir.list(recursive: true, followLinks: false);
    await for (final entity in stream) {
      try {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!_audioExtensions.contains(ext)) continue;

        Tag? tag;
        try {
          tag = await AudioTags.read(entity.path);
        } catch (_) {}
        FileStat? stat;
        try {
          stat = await entity.stat();
        } catch (_) {}

        String artUri = '';
        try {
          final art = await _artLoader.loadFor(entity.path, artDir, tag: tag);
          if (art != null) artUri = art;
        } catch (_) {}

        final canon = _canonicalize(entity.path);
        final companion = TracksCompanion.insert(
          uri: canon,
          filename: p.basename(canon),
          folderUri: p.dirname(canon),
          folderPath: p.dirname(canon),
          title: (tag?.title?.isNotEmpty ?? false)
              ? tag!.title!
              : p.basenameWithoutExtension(entity.path),
          artist: Value(tag?.trackArtist ?? ''),
          albumArtist: Value(tag?.albumArtist ?? ''),
          album: Value(tag?.album ?? ''),
          genre: Value(tag?.genre ?? ''),
          year: Value(tag?.year ?? 0),
          trackNumber: Value(tag?.trackNumber ?? 0),
          discNumber: Value(tag?.discNumber ?? 0),
          durationMs: Value(((tag?.duration ?? 0)) * 1000),
          fileSize: Value(stat?.size ?? 0),
          format: Value(ext.replaceFirst('.', '').toUpperCase()),
          artUri: Value(artUri),
          dateAdded: Value(stat?.changed.millisecondsSinceEpoch ?? 0),
          dateModified: Value(stat?.modified.millisecondsSinceEpoch ?? 0),
        );
        await db.upsertTrack(companion);
        count++;
      } catch (_) {
        // Skip any single-file failure rather than aborting the whole scan.
        continue;
      }
    }
    return count;
  }
}

final libraryScannerProvider = Provider<LibraryScanner>((ref) {
  return LibraryScanner(ref.watch(artLoaderProvider));
});
