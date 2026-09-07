import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_controller.dart';
import '../database/app_database.dart';

/// Exports user data (favorites, play counts, last-played, playlists, prefs)
/// to a JSON file. Track files themselves are not included — restore relies
/// on the device having the same library scanned, and matches by URI.
class BackupService {
  final AppDatabase db;
  final SharedPreferences prefs;

  BackupService(this.db, this.prefs);

  static const int formatVersion = 1;

  Future<File> exportToFile() async {
    final tracks = await db.allTracks();
    final playlists = await db.select(db.playlists).get();
    final playlistTracks = <Map<String, dynamic>>[];
    for (final pl in playlists) {
      final entries = await (db.select(db.playlistTracks)
            ..where((t) => t.playlistId.equals(pl.id))
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get();
      for (final e in entries) {
        final track = tracks.firstWhere(
          (t) => t.id == e.trackId,
          orElse: () => tracks.isEmpty ? _emptyTrack() : tracks.first,
        );
        playlistTracks.add({
          'playlist_name': pl.name,
          'track_uri': track.uri,
          'position': e.position,
        });
      }
    }

    final data = {
      'format_version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'tracks_state': [
        for (final t in tracks)
          {
            'uri': t.uri,
            'favorite': t.favorite,
            'play_count': t.playCount,
            'last_played_at': t.lastPlayedAt,
          }
      ],
      'playlists': [
        for (final pl in playlists)
          {
            'name': pl.name,
            'created_at': pl.createdAt,
            'modified_at': pl.modifiedAt,
          }
      ],
      'playlist_tracks': playlistTracks,
      'preferences': {
        PrefsKeys.themeMode: prefs.getInt(PrefsKeys.themeMode),
        PrefsKeys.useAmoled: prefs.getBool(PrefsKeys.useAmoled),
        PrefsKeys.accentColor: prefs.getInt(PrefsKeys.accentColor),
        PrefsKeys.skipSilence: prefs.getBool(PrefsKeys.skipSilence),
        PrefsKeys.autoPauseHeadphone:
            prefs.getBool(PrefsKeys.autoPauseHeadphone),
        PrefsKeys.hwKeyDoubleTap: prefs.getString(PrefsKeys.hwKeyDoubleTap),
        PrefsKeys.hwKeyLongPress: prefs.getString(PrefsKeys.hwKeyLongPress),
      },
    };

    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File(p.join(dir.path, 'mudita_backup_$stamp.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }

  Future<RestoreResult> restoreFromFile(File file) async {
    final raw = await file.readAsString();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final v = data['format_version'] as int? ?? 0;
    if (v > formatVersion) {
      throw 'Backup is from a newer version of the app';
    }

    final tracks = await db.allTracks();
    final byUri = {for (final t in tracks) t.uri: t};
    int matched = 0;
    int missed = 0;

    final tracksState = data['tracks_state'] as List? ?? [];
    for (final entry in tracksState) {
      final m = entry as Map<String, dynamic>;
      final uri = m['uri'] as String?;
      if (uri == null) continue;
      final t = byUri[uri];
      if (t == null) {
        missed++;
        continue;
      }
      matched++;
      await (db.update(db.tracks)..where((tt) => tt.id.equals(t.id))).write(
        TracksCompanion(
          favorite: Value((m['favorite'] as bool?) ?? false),
          playCount: Value((m['play_count'] as int?) ?? 0),
          lastPlayedAt: Value((m['last_played_at'] as int?) ?? 0),
        ),
      );
    }

    final playlistMap = <String, int>{};
    final pls = data['playlists'] as List? ?? [];
    for (final entry in pls) {
      final m = entry as Map<String, dynamic>;
      final name = m['name'] as String?;
      if (name == null) continue;
      final id = await db.createPlaylist(name);
      playlistMap[name] = id;
    }

    final playlistTracks = data['playlist_tracks'] as List? ?? [];
    for (final entry in playlistTracks) {
      final m = entry as Map<String, dynamic>;
      final plName = m['playlist_name'] as String?;
      final trackUri = m['track_uri'] as String?;
      if (plName == null || trackUri == null) continue;
      final plId = playlistMap[plName];
      final track = byUri[trackUri];
      if (plId == null || track == null) continue;
      await db.addToPlaylist(plId, track.id);
    }

    final p = data['preferences'] as Map<String, dynamic>? ?? {};
    for (final entry in p.entries) {
      final k = entry.key;
      final v = entry.value;
      if (v == null) continue;
      if (v is bool) await prefs.setBool(k, v);
      if (v is int) await prefs.setInt(k, v);
      if (v is String) await prefs.setString(k, v);
    }

    return RestoreResult(matched: matched, missed: missed);
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

class RestoreResult {
  final int matched;
  final int missed;
  RestoreResult({required this.matched, required this.missed});
}

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    ref.watch(databaseProvider),
    ref.watch(sharedPreferencesProvider),
  );
});
