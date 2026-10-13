import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:sqlite3/sqlite3.dart';

part 'app_database.g.dart';

class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uri => text().unique()();
  TextColumn get filename => text()();
  TextColumn get folderUri => text()();
  TextColumn get folderPath => text()();
  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant(''))();
  TextColumn get albumArtist => text().withDefault(const Constant(''))();
  TextColumn get album => text().withDefault(const Constant(''))();
  TextColumn get genre => text().withDefault(const Constant(''))();
  IntColumn get year => integer().withDefault(const Constant(0))();
  IntColumn get trackNumber => integer().withDefault(const Constant(0))();
  IntColumn get discNumber => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get bitrate => integer().withDefault(const Constant(0))();
  IntColumn get sampleRate => integer().withDefault(const Constant(0))();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  TextColumn get format => text().withDefault(const Constant(''))();
  TextColumn get artUri => text().withDefault(const Constant(''))();
  IntColumn get dateAdded => integer().withDefault(const Constant(0))();
  IntColumn get dateModified => integer().withDefault(const Constant(0))();
  IntColumn get lastPlayedAt => integer().withDefault(const Constant(0))();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  IntColumn get rating => integer().withDefault(const Constant(0))();
  IntColumn get skipCount => integer().withDefault(const Constant(0))();
  TextColumn get lyrics => text().withDefault(const Constant(''))();
  TextColumn get syncedLyricsPath => text().withDefault(const Constant(''))();
}

class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get createdAt => integer()();
  IntColumn get modifiedAt => integer()();
}

class PlaylistTracks extends Table {
  IntColumn get playlistId => integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get trackId => integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  @override
  Set<Column> get primaryKey => {playlistId, trackId, position};
}

class MusicFolders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uri => text().unique()();
  TextColumn get displayName => text()();
  IntColumn get addedAt => integer()();
}

class TopAggregate {
  final String name;
  final String? subtitle;
  final int plays;
  final Duration listenTime;
  const TopAggregate({
    required this.name,
    this.subtitle,
    required this.plays,
    required this.listenTime,
  });
}

class LibrarySummary {
  final int totalTracks;
  final int playedTracks;
  final int favorites;
  const LibrarySummary({
    required this.totalTracks,
    required this.playedTracks,
    required this.favorites,
  });
}

/// What makes two rows the same song, for dedupe and for the scanner.
/// Null for rows with no artist and no album: their title is often just the
/// file name ("01", "Track 1"), so different songs looked equal.
String? sameSongKey(
  String title,
  String artist,
  String album,
  int trackNumber,
) {
  final a = artist.trim().toLowerCase();
  final b = album.trim().toLowerCase();
  if (a.isEmpty && b.isEmpty) return null;
  return '${title.trim().toLowerCase()}\u0000$a\u0000$b\u0000$trackNumber';
}

@DriftDatabase(tables: [Tracks, Playlists, PlaylistTracks, MusicFolders])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(tracks, tracks.rating);
            await m.addColumn(tracks, tracks.skipCount);
          }
        },
      );

  Future<List<Track>> allTracks() => select(tracks).get();
  Stream<List<Track>> watchAllTracks() => select(tracks).watch();

  /// Insert a track, or update the row that already has its uri. Keyed on
  /// uri, not id: a rescan has no id, so the old upsert threw on every known
  /// file. The existing row keeps its id (and with it playlists, favourites
  /// and play counts) and its date added.
  Future<int> upsertTrack(TracksCompanion entry) async {
    return await into(tracks).insert(
      entry,
      onConflict: DoUpdate(
        (_) => entry.copyWith(dateAdded: const Value.absent()),
        target: [tracks.uri],
      ),
    );
  }

  Future<void> setTrackArt(int id, String artUri) async {
    await (update(tracks)..where((t) => t.id.equals(id)))
        .write(TracksCompanion(artUri: Value(artUri)));
  }

  Future<void> deleteTrackByUri(String uri) async {
    await (delete(tracks)..where((t) => t.uri.equals(uri))).go();
  }

  Future<List<Track>> searchTracks(String q) async {
    final like = '%$q%';
    return await (select(tracks)
          ..where((t) =>
              t.title.like(like) |
              t.artist.like(like) |
              t.album.like(like) |
              t.albumArtist.like(like))
          ..orderBy([(t) => OrderingTerm.asc(t.title)]))
        .get();
  }

  Future<List<Track>> tracksInAlbum(String album, String albumArtist) async {
    return await (select(tracks)
          ..where((t) =>
              t.album.equals(album) &
              (t.albumArtist.equals(albumArtist) | t.artist.equals(albumArtist)))
          ..orderBy([
            (t) => OrderingTerm.asc(t.discNumber),
            (t) => OrderingTerm.asc(t.trackNumber),
            // Fall back to filename when track numbers are missing (0) —
            // filenames usually start with "01 - ", "02 - " etc.
            (t) => OrderingTerm.asc(t.filename),
            (t) => OrderingTerm.asc(t.title),
          ]))
        .get();
  }

  Future<List<Track>> tracksByArtist(String artist) async {
    return await (select(tracks)
          ..where((t) => t.artist.equals(artist) | t.albumArtist.equals(artist))
          ..orderBy([
            (t) => OrderingTerm.asc(t.album),
            (t) => OrderingTerm.asc(t.discNumber),
            (t) => OrderingTerm.asc(t.trackNumber),
          ]))
        .get();
  }

  Future<List<Track>> tracksInFolder(String folderUri) async {
    return await (select(tracks)
          ..where((t) => t.folderUri.equals(folderUri))
          ..orderBy([(t) => OrderingTerm.asc(t.filename)]))
        .get();
  }

  Future<List<Track>> recentlyAdded({int days = 30}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;
    return await (select(tracks)
          ..where((t) => t.dateAdded.isBiggerThanValue(cutoff))
          ..orderBy([(t) => OrderingTerm.desc(t.dateAdded)]))
        .get();
  }

  Future<List<Track>> neverPlayed() async {
    return await (select(tracks)
          ..where((t) => t.playCount.equals(0))
          ..orderBy([(t) => OrderingTerm.asc(t.title)]))
        .get();
  }

  Future<List<Track>> mostPlayed({int limit = 50}) async {
    return await (select(tracks)
          ..where((t) => t.playCount.isBiggerThanValue(0))
          ..orderBy([(t) => OrderingTerm.desc(t.playCount)])
          ..limit(limit))
        .get();
  }

  Future<List<Track>> forgotten({int minDays = 180}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: minDays))
        .millisecondsSinceEpoch;
    return await (select(tracks)
          ..where((t) =>
              t.playCount.isBiggerThanValue(0) &
              t.lastPlayedAt.isSmallerThanValue(cutoff))
          ..orderBy([(t) => OrderingTerm.asc(t.lastPlayedAt)]))
        .get();
  }

  Future<List<Track>> favorites() async {
    return await (select(tracks)
          ..where((t) => t.favorite.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.title)]))
        .get();
  }

  Future<void> setFavorite(int id, bool value) async {
    await (update(tracks)..where((t) => t.id.equals(id)))
        .write(TracksCompanion(favorite: Value(value)));
  }

  Future<void> setRating(int id, int value) async {
    await (update(tracks)..where((t) => t.id.equals(id)))
        .write(TracksCompanion(rating: Value(value.clamp(0, 5))));
  }

  Future<void> recordSkip(int id) async {
    await customUpdate(
      'UPDATE tracks SET skip_count = skip_count + 1 WHERE id = ?',
      variables: [Variable.withInt(id)],
      updates: {tracks},
    );
  }

  Future<List<Track>> recentlyPlayed({int limit = 200}) async {
    return await (select(tracks)
          ..where((t) => t.lastPlayedAt.isBiggerThanValue(0))
          ..orderBy([(t) => OrderingTerm.desc(t.lastPlayedAt)])
          ..limit(limit))
        .get();
  }

  Future<List<Track>> highlyRated({int min = 4}) async {
    return await (select(tracks)
          ..where((t) => t.rating.isBiggerOrEqualValue(min))
          ..orderBy([(t) => OrderingTerm.desc(t.rating)]))
        .get();
  }

  /// Estimated total listen time across the library: sum of (plays × duration).
  /// Skipped plays inflate this (we count every recorded play as a full track),
  /// but it's a fair "you've listened to roughly X" number.
  Future<Duration> totalListenTime() async {
    final rows = await customSelect(
      'SELECT COALESCE(SUM(play_count * duration_ms), 0) AS total FROM tracks',
      readsFrom: {tracks},
    ).getSingle();
    final ms = rows.read<int>('total');
    return Duration(milliseconds: ms);
  }

  /// Top N tracks by play count.
  Future<List<Track>> topTracks({int limit = 25}) async {
    return await (select(tracks)
          ..where((t) => t.playCount.isBiggerThanValue(0))
          ..orderBy([(t) => OrderingTerm.desc(t.playCount)])
          ..limit(limit))
        .get();
  }

  /// Top artists with their aggregate play count.
  Future<List<TopAggregate>> topArtists({int limit = 25}) async {
    final rows = await customSelect(
      '''
      SELECT
        CASE WHEN album_artist != '' THEN album_artist ELSE artist END AS name,
        SUM(play_count) AS plays,
        SUM(play_count * duration_ms) AS time_ms
      FROM tracks
      WHERE play_count > 0
      GROUP BY name
      HAVING name != ''
      ORDER BY plays DESC
      LIMIT ?
      ''',
      variables: [Variable.withInt(limit)],
      readsFrom: {tracks},
    ).get();
    return rows
        .map((r) => TopAggregate(
              name: r.read<String>('name'),
              plays: r.read<int>('plays'),
              listenTime: Duration(milliseconds: r.read<int>('time_ms')),
            ))
        .toList();
  }

  /// Top albums with their aggregate play count.
  Future<List<TopAggregate>> topAlbums({int limit = 25}) async {
    final rows = await customSelect(
      '''
      SELECT
        album AS name,
        CASE WHEN album_artist != '' THEN album_artist ELSE artist END AS artist,
        SUM(play_count) AS plays,
        SUM(play_count * duration_ms) AS time_ms
      FROM tracks
      WHERE play_count > 0 AND album != ''
      GROUP BY album, artist
      ORDER BY plays DESC
      LIMIT ?
      ''',
      variables: [Variable.withInt(limit)],
      readsFrom: {tracks},
    ).get();
    return rows
        .map((r) => TopAggregate(
              name: r.read<String>('name'),
              subtitle: r.read<String>('artist'),
              plays: r.read<int>('plays'),
              listenTime: Duration(milliseconds: r.read<int>('time_ms')),
            ))
        .toList();
  }

  /// Tracks played in the last N days.
  Future<List<Track>> playedSince(Duration window) async {
    final cutoff = DateTime.now().subtract(window).millisecondsSinceEpoch;
    return await (select(tracks)
          ..where((t) => t.lastPlayedAt.isBiggerThanValue(cutoff))
          ..orderBy([(t) => OrderingTerm.desc(t.lastPlayedAt)]))
        .get();
  }

  Future<LibrarySummary> librarySummary() async {
    final tracksCount = await customSelect(
      'SELECT COUNT(*) AS c FROM tracks',
      readsFrom: {tracks},
    ).getSingle();
    final playedCount = await customSelect(
      'SELECT COUNT(*) AS c FROM tracks WHERE play_count > 0',
      readsFrom: {tracks},
    ).getSingle();
    final favoritesCount = await customSelect(
      'SELECT COUNT(*) AS c FROM tracks WHERE favorite = 1',
      readsFrom: {tracks},
    ).getSingle();
    return LibrarySummary(
      totalTracks: tracksCount.read<int>('c'),
      playedTracks: playedCount.read<int>('c'),
      favorites: favoritesCount.read<int>('c'),
    );
  }

  /// Removes duplicate tracks. Two tracks are "the same" if they share
  /// title + artist + album + track number ([sameSongKey]) and their
  /// durations are within a second. Keeps the row with the smallest id,
  /// which preserves favorites/ratings/play counts on the canonical row.
  ///
  /// The scanner uses the same test to leave such copies out, so a copy
  /// isn't added and removed again on every scan.
  Future<int> dedupeTracks() async {
    final rows =
        await (select(tracks)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    final kept = <String, List<int>>{};
    final drop = <int>[];
    for (final t in rows) {
      final key = sameSongKey(t.title, t.artist, t.album, t.trackNumber);
      if (key == null) continue;
      final durations = kept.putIfAbsent(key, () => []);
      if (durations.any((ms) => (ms - t.durationMs).abs() <= 1000)) {
        drop.add(t.id);
      } else {
        durations.add(t.durationMs);
      }
    }
    // Only wakes the library lists when something is actually removed.
    await deleteTracksByIds(drop);
    return drop.length;
  }

  Future<void> wipeAllTracks() async {
    await delete(tracks).go();
  }

  Future<void> setAlbumArt(String album, String albumArtist, String artUri) async {
    await (update(tracks)
          ..where((t) =>
              t.album.equals(album) &
              (t.albumArtist.equals(albumArtist) | t.artist.equals(albumArtist))))
        .write(TracksCompanion(artUri: Value(artUri)));
  }

  Future<void> recordPlay(int id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await customUpdate(
      'UPDATE tracks SET play_count = play_count + 1, last_played_at = ? WHERE id = ?',
      variables: [Variable.withInt(now), Variable.withInt(id)],
      updates: {tracks},
    );
  }

  Future<int> createPlaylist(String name) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return await into(playlists).insert(
      PlaylistsCompanion.insert(
        name: name,
        createdAt: now,
        modifiedAt: now,
      ),
    );
  }

  Future<void> renamePlaylist(int id, String name) async {
    await (update(playlists)..where((p) => p.id.equals(id))).write(
      PlaylistsCompanion(
        name: Value(name),
        modifiedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> deletePlaylist(int id) async {
    await (delete(playlists)..where((p) => p.id.equals(id))).go();
  }

  Future<List<Track>> tracksInPlaylist(int playlistId) async {
    final query = select(playlistTracks).join([
      innerJoin(tracks, tracks.id.equalsExp(playlistTracks.trackId)),
    ])
      ..where(playlistTracks.playlistId.equals(playlistId))
      ..orderBy([OrderingTerm.asc(playlistTracks.position)]);
    final rows = await query.get();
    return rows.map((r) => r.readTable(tracks)).toList();
  }

  Future<void> addToPlaylist(int playlistId, int trackId) async {
    final maxPos = await (select(playlistTracks)
          ..where((pt) => pt.playlistId.equals(playlistId))
          ..orderBy([(pt) => OrderingTerm.desc(pt.position)])
          ..limit(1))
        .getSingleOrNull();
    final pos = (maxPos?.position ?? -1) + 1;
    await into(playlistTracks).insert(
      PlaylistTracksCompanion.insert(
        playlistId: playlistId,
        trackId: trackId,
        position: pos,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> removeFromPlaylist(int playlistId, int trackId, int position) async {
    await (delete(playlistTracks)
          ..where((pt) =>
              pt.playlistId.equals(playlistId) &
              pt.trackId.equals(trackId) &
              pt.position.equals(position)))
        .go();
  }

  /// Remove every occurrence of a track from a playlist.
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await (delete(playlistTracks)
          ..where((pt) =>
              pt.playlistId.equals(playlistId) & pt.trackId.equals(trackId)))
        .go();
  }

  Future<int> countPlaylistTracks(int playlistId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM playlist_tracks WHERE playlist_id = ?',
      variables: [Variable.withInt(playlistId)],
      readsFrom: {playlistTracks},
    ).getSingle();
    return row.read<int>('c');
  }

  /// Delete library rows by id (playlist entries cascade).
  Future<void> deleteTracksByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    await (delete(tracks)..where((t) => t.id.isIn(ids))).go();
  }

  Future<List<MusicFolder>> getMusicFolders() => select(musicFolders).get();

  Future<int> addMusicFolder(String uri, String displayName) async {
    return await into(musicFolders).insertOnConflictUpdate(
      MusicFoldersCompanion.insert(
        uri: uri,
        displayName: displayName,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> removeMusicFolder(String uri) async {
    await (delete(musicFolders)..where((f) => f.uri.equals(uri))).go();
    await (delete(tracks)..where((t) => t.folderUri.equals(uri))).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'mudita_player.sqlite'));
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;
    return NativeDatabase.createInBackground(file);
  });
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
