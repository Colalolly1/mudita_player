import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../playback/playback_controller.dart';
import 'theme_controller.dart';

/// Watches the now-playing track. If "album-derived accent" is enabled,
/// extracts a dominant color from the cover art and pushes it into the
/// theme controller as the current accent.
class AlbumAccentSync {
  final Ref _ref;
  String? _lastUri;

  AlbumAccentSync(this._ref) {
    // Only attach the listener if the user has the feature enabled. This way,
    // any failure in palette extraction can't cause boot issues for users who
    // don't use the feature.
    final prefs = _ref.read(themeControllerProvider);
    if (!prefs.albumDerivedAccent) return;
    _ref.listen(playbackControllerProvider, (prev, next) {
      _maybeUpdate(next.current?.artUri);
    });
  }

  Future<void> _maybeUpdate(String? artUri) async {
    final theme = _ref.read(themeControllerProvider);
    if (!theme.albumDerivedAccent) return;
    if (artUri == null || artUri.isEmpty) return;
    if (artUri == _lastUri) return;
    _lastUri = artUri;
    try {
      ImageProvider? provider;
      if (artUri.startsWith('http')) {
        provider = NetworkImage(artUri);
      } else if (artUri.startsWith('file://')) {
        provider = FileImage(File(artUri.substring(7)));
      } else if (artUri.startsWith('content://')) {
        return; // not directly readable as ImageProvider; skip
      } else {
        provider = FileImage(File(artUri));
      }
      final p = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(120, 120),
        maximumColorCount: 8,
      );
      final c = p.vibrantColor?.color ??
          p.dominantColor?.color ??
          p.mutedColor?.color;
      if (c != null) {
        await _ref.read(themeControllerProvider.notifier).setAccent(c);
      }
    } catch (_) {
      // ignore extraction errors
    }
  }
}

final albumAccentSyncProvider = Provider<AlbumAccentSync>((ref) {
  return AlbumAccentSync(ref);
});
