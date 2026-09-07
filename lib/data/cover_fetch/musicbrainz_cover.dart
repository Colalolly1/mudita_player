import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../repositories/library_repository.dart';
import '../../shared/models/album.dart';

/// Fetches missing album art from public APIs.
///
/// Strategy is intentionally aggressive — most users would rather get a
/// "close enough" cover than no cover at all. Tries several search
/// formulations against iTunes, then Deezer, then MusicBrainz/CoverArtArchive,
/// and reports detailed reasons when nothing matches. Every applied cover is
/// embedded into the audio files themselves (via the repository).
class MusicBrainzCoverFetcher {
  static const _userAgent =
      'MuditaPlayer/0.1 (https://github.com/mudita; offline music app)';

  final LibraryRepository repo;
  MusicBrainzCoverFetcher(this.repo);

  static const _throttle = Duration(milliseconds: 300);
  static const _httpTimeout = Duration(seconds: 8);

  Future<http.Response> _get(Uri url) {
    return http.get(url, headers: {
      'User-Agent': _userAgent,
      'Accept': 'application/json',
    }).timeout(_httpTimeout);
  }

  Future<http.Response> _getRaw(Uri url) {
    return http.get(url, headers: {
      'User-Agent': _userAgent,
    }).timeout(_httpTimeout);
  }

  /// Result of a single-album fetch attempt with a human-readable reason.
  Future<CoverFetchResult> fetchForAlbumDetailed(AlbumKey key) async {
    // Build candidate search terms — broad to narrow.
    final terms = <String>{};
    if (key.album.isNotEmpty && key.albumArtist.isNotEmpty) {
      terms.add('${key.album} ${key.albumArtist}');
    }
    if (key.album.isNotEmpty) terms.add(key.album);
    if (key.albumArtist.isNotEmpty) terms.add(key.albumArtist);

    // Also try without anything in parens (often Soulseek tags include "(2012)" etc.)
    final albumStripped =
        key.album.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
    if (albumStripped.isNotEmpty && albumStripped != key.album) {
      if (key.albumArtist.isNotEmpty) {
        terms.add('$albumStripped ${key.albumArtist}');
      }
      terms.add(albumStripped);
    }

    if (terms.isEmpty) {
      return const CoverFetchResult.failure(
          'Track has no album / artist tag — cannot search');
    }

    // 1) iTunes
    for (final term in terms) {
      try {
        final r = await _itunesSearch(term);
        if (r != null) {
          final saved = await repo.setAlbumArtFromBytes(key, r);
          return CoverFetchResult.success(saved, 'iTunes ("$term")');
        }
      } catch (e) {
        return CoverFetchResult.failure('iTunes error: $e');
      }
      await Future.delayed(_throttle);
    }

    // 2) Deezer
    for (final term in terms) {
      try {
        final candidates = await _searchDeezer(term, limit: 3);
        for (final c in candidates) {
          final res = await _getRaw(Uri.parse(c.hiResUrl));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            final saved = await repo.setAlbumArtFromBytes(key, res.bodyBytes);
            return CoverFetchResult.success(saved, 'Deezer ("$term")');
          }
        }
      } catch (_) {}
      await Future.delayed(_throttle);
    }

    // 3) MusicBrainz / CAA fallback
    try {
      final mb = await _musicBrainzSearch(key);
      if (mb != null) {
        final saved = await repo.setAlbumArtFromBytes(key, mb);
        return CoverFetchResult.success(saved, 'MusicBrainz');
      }
    } catch (e) {
      return CoverFetchResult.failure('MusicBrainz error: $e');
    }

    return const CoverFetchResult.failure(
        'No match on iTunes, Deezer or MusicBrainz');
  }

  Future<String?> fetchForAlbum(AlbumKey key) async {
    final r = await fetchForAlbumDetailed(key);
    return r.uri;
  }

  /// Combined candidate search across iTunes AND Deezer, interleaved so both
  /// sources appear near the top. Deezer fills the gaps in Apple's catalog
  /// (and vice versa), which is what makes the right cover findable.
  Future<List<CoverCandidate>> searchCoverCandidates(String term,
      {int limitPerSource = 12}) async {
    if (term.trim().isEmpty) return [];
    final results = await Future.wait([
      _searchItunesCandidates(term, limit: limitPerSource),
      _searchDeezer(term, limit: limitPerSource),
    ]);
    final a = results[0];
    final b = results[1];
    final merged = <CoverCandidate>[];
    for (var i = 0; i < a.length || i < b.length; i++) {
      if (i < a.length) merged.add(a[i]);
      if (i < b.length) merged.add(b[i]);
    }
    return merged;
  }

  Future<List<CoverCandidate>> _searchItunesCandidates(String term,
      {int limit = 12}) async {
    try {
      final url = Uri.https('itunes.apple.com', '/search', {
        'term': term,
        'entity': 'album',
        'limit': '$limit',
      });
      final res = await _get(url);
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List? ?? [];
      final out = <CoverCandidate>[];
      for (final r in results) {
        final m = r as Map;
        final url100 = m['artworkUrl100'] as String?;
        if (url100 == null) continue;
        out.add(CoverCandidate(
          albumName: (m['collectionName'] as String?) ?? '',
          artistName: (m['artistName'] as String?) ?? '',
          releaseYear: _yearFromIso(m['releaseDate'] as String?),
          thumbUrl: url100,
          hiResUrl: url100.replaceAll('100x100bb.jpg', '1200x1200bb.jpg'),
          source: 'iTunes',
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<CoverCandidate>> _searchDeezer(String term,
      {int limit = 12}) async {
    try {
      final url = Uri.https('api.deezer.com', '/search/album', {
        'q': term,
        'limit': '$limit',
      });
      final res = await _get(url);
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'] as List? ?? [];
      final out = <CoverCandidate>[];
      for (final r in data) {
        final m = r as Map;
        final thumb = m['cover_medium'] as String?;
        final hi = (m['cover_xl'] ?? m['cover_big']) as String?;
        if (thumb == null || hi == null) continue;
        out.add(CoverCandidate(
          albumName: (m['title'] as String?) ?? '',
          artistName: ((m['artist'] as Map?)?['name'] as String?) ?? '',
          releaseYear: null,
          thumbUrl: thumb,
          hiResUrl: hi,
          source: 'Deezer',
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Download a specific candidate and apply it as the album's cover —
  /// cached for instant UI AND embedded into the audio files themselves.
  Future<String?> applyCandidate(AlbumKey key, CoverCandidate c) async {
    try {
      final res = await _getRaw(Uri.parse(c.hiResUrl));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      final ext = c.hiResUrl.toLowerCase().contains('.png') ? '.png' : '.jpg';
      return await repo.setAlbumArtFromBytes(key, res.bodyBytes, ext: ext);
    } catch (_) {
      return null;
    }
  }

  int? _yearFromIso(String? iso) {
    if (iso == null || iso.length < 4) return null;
    return int.tryParse(iso.substring(0, 4));
  }

  Future<List<int>?> _itunesSearch(String term) async {
    final url = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'entity': 'album',
      'limit': '5',
    });
    final res = await _get(url);
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final results = body['results'] as List? ?? [];
    if (results.isEmpty) return null;
    for (final r in results) {
      final m = r as Map;
      final url100 = m['artworkUrl100'] as String?;
      if (url100 == null) continue;
      final hi = url100.replaceAll('100x100bb.jpg', '1200x1200bb.jpg');
      final imgRes = await _getRaw(Uri.parse(hi));
      if (imgRes.statusCode == 200 && imgRes.bodyBytes.isNotEmpty) {
        return imgRes.bodyBytes;
      }
    }
    return null;
  }

  Future<List<int>?> _musicBrainzSearch(AlbumKey key) async {
    if (key.album.isEmpty) return null;
    final mbids = await _searchReleaseGroups(key);
    for (final mbid in mbids) {
      await Future.delayed(_throttle);
      final imgUrl =
          'https://coverartarchive.org/release-group/$mbid/front-500';
      final imgRes = await _getRaw(Uri.parse(imgUrl));
      if (imgRes.statusCode == 200 && imgRes.bodyBytes.isNotEmpty) {
        return imgRes.bodyBytes;
      }
    }
    return null;
  }

  String _escape(String s) {
    return s.replaceAllMapped(
      RegExp(r'([+\-!(){}\[\]^"~*?:\\/])'),
      (m) => '\\${m[0]}',
    );
  }

  Future<List<String>> _searchReleaseGroups(AlbumKey key) async {
    final q = key.albumArtist.isEmpty
        ? 'release:"${_escape(key.album)}"'
        : 'release:"${_escape(key.album)}" AND artist:"${_escape(key.albumArtist)}"';
    final url = Uri.https('musicbrainz.org', '/ws/2/release-group', {
      'query': q,
      'fmt': 'json',
      'limit': '5',
    });
    final res = await _get(url);
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final groups = body['release-groups'] as List? ?? [];
    return groups
        .map((g) => (g as Map)['id'] as String?)
        .whereType<String>()
        .toList();
  }

  /// Quick connectivity check — returns null on success, error string on
  /// failure. Used by the "Test cover-fetch connection" button in Settings.
  Future<String?> selfTest() async {
    try {
      final url = Uri.https('itunes.apple.com', '/search', {
        'term': 'pink floyd',
        'entity': 'album',
        'limit': '1',
      });
      final res = await _get(url);
      if (res.statusCode != 200) {
        return 'iTunes returned HTTP ${res.statusCode}';
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final n = (body['results'] as List?)?.length ?? 0;
      if (n == 0) return 'iTunes responded but returned 0 results';
      return null; // success
    } on SocketException catch (e) {
      return 'No network: ${e.osError?.message ?? e.message}';
    } on http.ClientException catch (e) {
      return 'HTTP client error: ${e.message}';
    } catch (e) {
      return 'Network error: $e';
    }
  }

  /// Walk albums needing covers and try to fetch one for each.
  ///
  /// [overwriteExisting] - if true, fetch covers for ALL albums regardless of
  /// whether they already have one. Useful when existing artUris point to
  /// deleted or broken files.
  Future<FetchResult> fetchAllMissing({
    bool overwriteExisting = false,
    void Function(String album, int done, int total, String? error)?
        onProgress,
  }) async {
    final albums = await repo.albums();
    final candidates = <AlbumSummary>[];
    for (final a in albums) {
      if (overwriteExisting) {
        candidates.add(a);
        continue;
      }
      // Treat as missing if no artUri OR the file at that URI no longer exists.
      final uri = a.artUri;
      if (uri == null || uri.isEmpty) {
        candidates.add(a);
        continue;
      }
      final path = uri.startsWith('file://') ? uri.substring(7) : uri;
      try {
        if (!await File(path).exists()) {
          candidates.add(a);
        }
      } catch (_) {
        candidates.add(a);
      }
    }
    int filled = 0;
    int failed = 0;
    String? lastError;
    for (var i = 0; i < candidates.length; i++) {
      final a = candidates[i];
      try {
        final r = await fetchForAlbumDetailed(a.key);
        if (r.uri != null) {
          filled++;
          onProgress?.call(a.album, i + 1, candidates.length, null);
        } else {
          failed++;
          lastError = r.reason;
          onProgress?.call(a.album, i + 1, candidates.length, r.reason);
        }
      } catch (e) {
        failed++;
        lastError = '$e';
        onProgress?.call(a.album, i + 1, candidates.length, '$e');
      }
    }
    return FetchResult(
      total: candidates.length,
      filled: filled,
      failed: failed,
      lastError: lastError,
    );
  }
}

class CoverFetchResult {
  final String? uri;
  final String reason;
  const CoverFetchResult.success(String this.uri, this.reason);
  const CoverFetchResult.failure(this.reason) : uri = null;
}

class CoverCandidate {
  final String albumName;
  final String artistName;
  final int? releaseYear;
  final String thumbUrl; // small — for the picker grid
  final String hiResUrl; // 1000–1200px — downloaded when user picks one
  final String source; // 'iTunes' or 'Deezer'
  const CoverCandidate({
    required this.albumName,
    required this.artistName,
    required this.releaseYear,
    required this.thumbUrl,
    required this.hiResUrl,
    required this.source,
  });
}

class FetchResult {
  final int total;
  final int filled;
  final int failed;
  final String? lastError;
  const FetchResult({
    required this.total,
    required this.filled,
    required this.failed,
    this.lastError,
  });
}

final musicBrainzCoverProvider = Provider<MusicBrainzCoverFetcher>((ref) {
  return MusicBrainzCoverFetcher(
    ref.watch(libraryRepositoryProvider),
  );
});
