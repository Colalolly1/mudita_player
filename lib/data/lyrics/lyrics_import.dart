import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';

/// Walks a folder tree looking for `.lrc` files, then matches each to an
/// existing track in the library by **basename**. If a match is found we
/// store the lrc file path in the track's `syncedLyricsPath` column so the
/// lyrics loader can find it on next playback.
class LyricsImporter {
  final AppDatabase db;
  LyricsImporter(this.db);

  Future<LyricsImportResult> importFromFolder(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return const LyricsImportResult(scanned: 0, matched: 0, missed: 0);
    }
    final lrcs = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          p.extension(entity.path).toLowerCase() == '.lrc') {
        lrcs.add(entity);
      }
    }

    if (lrcs.isEmpty) {
      return LyricsImportResult(scanned: 0, matched: 0, missed: 0);
    }

    final tracks = await db.allTracks();
    final byBase = <String, List<Track>>{};
    for (final t in tracks) {
      final base = p.basenameWithoutExtension(t.filename).toLowerCase();
      byBase.putIfAbsent(base, () => []).add(t);
    }

    int matched = 0;
    int missed = 0;
    for (final lrc in lrcs) {
      final base = p.basenameWithoutExtension(lrc.path).toLowerCase();
      final candidates = byBase[base];
      if (candidates == null || candidates.isEmpty) {
        missed++;
        continue;
      }
      for (final t in candidates) {
        await (db.update(db.tracks)..where((tt) => tt.id.equals(t.id))).write(
          TracksCompanion(syncedLyricsPath: Value(lrc.path)),
        );
      }
      matched++;
    }

    return LyricsImportResult(
      scanned: lrcs.length,
      matched: matched,
      missed: missed,
    );
  }
}

class LyricsImportResult {
  final int scanned;
  final int matched;
  final int missed;
  const LyricsImportResult({
    required this.scanned,
    required this.matched,
    required this.missed,
  });
}

final lyricsImporterProvider = Provider<LyricsImporter>((ref) {
  return LyricsImporter(ref.watch(databaseProvider));
});
