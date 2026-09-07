import '../../data/database/app_database.dart';

class AlbumKey {
  final String album;
  final String albumArtist;
  const AlbumKey(this.album, this.albumArtist);

  @override
  bool operator ==(Object other) =>
      other is AlbumKey &&
      other.album == album &&
      other.albumArtist == albumArtist;

  @override
  int get hashCode => Object.hash(album, albumArtist);
}

class AlbumSummary {
  final String album;
  final String albumArtist;
  final int year;
  final int trackCount;
  final String? artUri;
  final List<Track> tracks;

  const AlbumSummary({
    required this.album,
    required this.albumArtist,
    required this.year,
    required this.trackCount,
    required this.artUri,
    required this.tracks,
  });

  AlbumKey get key => AlbumKey(album, albumArtist);
}

class ArtistSummary {
  final String name;
  final int albumCount;
  final int trackCount;
  final String? artUri;

  const ArtistSummary({
    required this.name,
    required this.albumCount,
    required this.trackCount,
    required this.artUri,
  });
}

class FolderSummary {
  final String uri;
  final String displayPath;
  final int trackCount;

  const FolderSummary({
    required this.uri,
    required this.displayPath,
    required this.trackCount,
  });
}
