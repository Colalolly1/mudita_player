import 'dart:io';

import 'package:audiotags/audiotags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class SyncedLine {
  final Duration time;
  final String text;
  const SyncedLine(this.time, this.text);
}

class LoadedLyrics {
  final String? plain;
  final List<SyncedLine> synced;
  final String source;

  const LoadedLyrics({
    required this.plain,
    required this.synced,
    required this.source,
  });

  bool get isEmpty => (plain == null || plain!.trim().isEmpty) && synced.isEmpty;
  bool get isSynced => synced.isNotEmpty;
}

class LyricsLoader {
  Future<LoadedLyrics> load(String trackPath, {String? overridePath}) async {
    if (overridePath != null && overridePath.isNotEmpty) {
      final f = File(overridePath);
      if (await f.exists()) {
        final text = await f.readAsString();
        final synced = _parseLrc(text);
        return LoadedLyrics(
          plain: synced.isEmpty ? text : null,
          synced: synced,
          source: 'override',
        );
      }
    }
    final lrcSibling = File(
      p.join(
        p.dirname(trackPath),
        '${p.basenameWithoutExtension(trackPath)}.lrc',
      ),
    );
    if (await lrcSibling.exists()) {
      final text = await lrcSibling.readAsString();
      final synced = _parseLrc(text);
      return LoadedLyrics(
        plain: synced.isEmpty ? text : null,
        synced: synced,
        source: 'sidecar',
      );
    }

    try {
      final tag = await AudioTags.read(trackPath);
      // audiotags doesn't expose lyrics directly; fallback to sidecar text only
      // for plain. Real ID3 USLT would need extra processing.
      // Leave plain empty if no sidecar.
      if (tag != null) {
        return const LoadedLyrics(plain: null, synced: [], source: 'embedded');
      }
    } catch (_) {}

    return const LoadedLyrics(plain: null, synced: [], source: 'none');
  }

  static List<SyncedLine> _parseLrc(String text) {
    final out = <SyncedLine>[];
    final timeRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      final stamps = timeRegex.allMatches(line).toList();
      if (stamps.isEmpty) continue;
      final lyric = line.substring(stamps.last.end).trim();
      for (final m in stamps) {
        final mn = int.parse(m.group(1)!);
        final sc = int.parse(m.group(2)!);
        final fr = m.group(3);
        int ms = 0;
        if (fr != null) {
          final f = int.parse(fr);
          ms = fr.length == 2 ? f * 10 : f;
        }
        out.add(SyncedLine(
          Duration(minutes: mn, seconds: sc, milliseconds: ms),
          lyric,
        ));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }
}

final lyricsLoaderProvider = Provider<LyricsLoader>((ref) => LyricsLoader());
