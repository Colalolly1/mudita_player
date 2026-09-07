import 'dart:convert';
import 'dart:io';

import 'package:audiotags/audiotags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart' show md5;

class ArtLoader {
  static const _coverNames = [
    'cover.jpg', 'cover.jpeg', 'cover.png',
    'folder.jpg', 'folder.jpeg', 'folder.png',
    'album.jpg', 'album.jpeg', 'album.png',
    'front.jpg', 'front.jpeg', 'front.png',
  ];

  Future<String?> loadFor(String trackPath, Directory artDir, {Tag? tag}) async {
    final folder = Directory(p.dirname(trackPath));

    for (final name in _coverNames) {
      final f = File(p.join(folder.path, name));
      if (await f.exists()) return f.path;
      final upper = File(p.join(folder.path, name[0].toUpperCase() + name.substring(1)));
      if (await upper.exists()) return upper.path;
    }

    if (tag != null && tag.pictures.isNotEmpty) {
      final pic = tag.pictures.first;
      final hash = md5.convert(utf8.encode(trackPath)).toString();
      final ext = _extFromMime(pic.mimeType);
      final out = File(p.join(artDir.path, '$hash$ext'));
      if (!await out.exists()) {
        await out.writeAsBytes(pic.bytes);
      }
      return out.path;
    }

    return null;
  }

  String _extFromMime(MimeType? mime) {
    return switch (mime) {
      MimeType.jpeg => '.jpg',
      MimeType.png => '.png',
      _ => '.img',
    };
  }
}

final artLoaderProvider = Provider<ArtLoader>((ref) => ArtLoader());
