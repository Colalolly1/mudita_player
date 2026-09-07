import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/library_repository.dart';
import '../../features/library/tabs/smart_tab.dart';
import '../models/album.dart';

export '../../data/repositories/library_repository.dart' show libraryRepositoryProvider;

final allTracksProvider = StreamProvider<List<Track>>((ref) {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.watchAllTracks();
});

final albumsProvider = FutureProvider<List<AlbumSummary>>((ref) async {
  ref.watch(allTracksProvider);
  return ref.watch(libraryRepositoryProvider).albums();
});

final artistsProvider = FutureProvider<List<ArtistSummary>>((ref) async {
  ref.watch(allTracksProvider);
  return ref.watch(libraryRepositoryProvider).artists();
});

final foldersProvider = FutureProvider<List<FolderSummary>>((ref) async {
  ref.watch(allTracksProvider);
  return ref.watch(libraryRepositoryProvider).folders();
});

final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  return ref.watch(libraryRepositoryProvider).getPlaylists();
});

final albumTracksProvider =
    FutureProvider.family<List<Track>, AlbumKey>((ref, key) async {
  ref.watch(allTracksProvider);
  return ref.watch(libraryRepositoryProvider).tracksInAlbum(key);
});

final artistTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, name) async {
  ref.watch(allTracksProvider);
  return ref.watch(libraryRepositoryProvider).tracksByArtist(name);
});

final folderTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, uri) async {
  ref.watch(allTracksProvider);
  return ref.watch(libraryRepositoryProvider).tracksInFolder(uri);
});

final playlistTracksProvider =
    FutureProvider.family<List<Track>, int>((ref, id) async {
  return ref.watch(libraryRepositoryProvider).getPlaylistTracks(id);
});

/// Bumped each time the user taps "reshuffle" on the Daily Mix, forcing the
/// mix to regenerate with a fresh random seed instead of the once-per-day one.
final dailyMixRefreshProvider = StateProvider<int>((ref) => 0);

final smartPlaylistProvider =
    FutureProvider.family<List<Track>, SmartKind>((ref, kind) async {
  final db = ref.watch(databaseProvider);
  ref.watch(allTracksProvider);
  switch (kind) {
    case SmartKind.recentlyAdded:
      return db.recentlyAdded();
    case SmartKind.mostPlayed:
      return db.mostPlayed();
    case SmartKind.neverPlayed:
      return db.neverPlayed();
    case SmartKind.forgotten:
      return db.forgotten();
    case SmartKind.favorites:
      return db.favorites();
    case SmartKind.highlyRated:
      return db.highlyRated();
    case SmartKind.history:
      return db.recentlyPlayed(limit: AppConstants.historyLimit);
    case SmartKind.oftenSkipped:
      final all = await db.allTracks();
      final filtered = all.where((t) =>
          t.skipCount > 0 && t.skipCount > t.playCount).toList()
        ..sort((a, b) => b.skipCount.compareTo(a.skipCount));
      return filtered;
    case SmartKind.duplicates:
      final all = await db.allTracks();
      final groups = <String, List<Track>>{};
      for (final t in all) {
        final k = '${t.title.toLowerCase().trim()}::${t.artist.toLowerCase().trim()}';
        groups.putIfAbsent(k, () => []).add(t);
      }
      final dupes = <Track>[];
      for (final g in groups.values) {
        if (g.length > 1) dupes.addAll(g);
      }
      dupes.sort((a, b) {
        final t = a.title.compareTo(b.title);
        if (t != 0) return t;
        return a.artist.compareTo(b.artist);
      });
      return dupes;
    case SmartKind.missing:
      final all = await db.allTracks();
      final missing = <Track>[];
      for (final t in all) {
        final uri = t.uri;
        if (uri.startsWith('content://')) continue; // can't easily stat
        final p = uri.startsWith('file://') ? uri.substring(7) : uri;
        if (!await File(p).exists()) missing.add(t);
      }
      return missing;
    case SmartKind.dailyMix:
      final all = await db.allTracks();
      if (all.isEmpty) return all;
      // Completely random: a pure seeded shuffle of the whole library, no
      // scoring or weighting (the old favorite/rating boost meant the same
      // 5-star songs always floated to the top). Seed = date + manual
      // refresh counter, so the mix changes daily and on demand.
      final now = DateTime.now();
      final refresh = ref.watch(dailyMixRefreshProvider);
      final seed =
          now.year * 10000 + now.month * 100 + now.day + refresh * 7919;
      final shuffled = [...all]..shuffle(Random(seed));
      return shuffled.take(50).toList();
  }
});

final musicFoldersProvider = FutureProvider<List<MusicFolder>>((ref) async {
  return ref.watch(libraryRepositoryProvider).getMusicFolders();
});
