import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../repositories/library_repository.dart';

/// Runs once on app start. If the library has no folders yet, requests audio
/// permissions and scans the device's MediaStore so the user sees their music
/// without having to manually add a folder in Settings.
class LibraryInitializer {
  final LibraryRepository repo;
  LibraryInitializer(this.repo);

  bool _ran = false;
  Future<void>? _running;
  String _status = '';

  String get status => _status;

  /// Returns the future of the in-flight initialization, so callers can await
  /// the same work without spawning duplicates.
  Future<void> ensureInitialized() {
    if (_running != null) return _running!;
    _running = _run();
    return _running!;
  }

  /// The launch scan: only new or changed files are opened, so it is cheap.
  /// It never asks for permission, and is skipped until audio access has
  /// been granted, so a missing permission can't make songs look deleted.
  Future<void> refreshOnLaunch() => _launchScan ??= _refresh();
  Future<void>? _launchScan;

  Future<void> _refresh() async {
    if (Platform.isAndroid) {
      final audio = await Permission.audio.isGranted;
      final storage = await Permission.storage.isGranted;
      if (!audio && !storage) return;
    }
    if ((await repo.getMusicFolders()).isEmpty) return;
    // If any folder can't be listed (SD card not mounted, folder renamed),
    // nothing is pruned, so its songs and their history stay.
    await repo.rescan(atLaunch: true);
  }

  Future<void> _run() async {
    if (_ran) return;
    _ran = true;
    try {
      // Permissions
      if (Platform.isAndroid) {
        _status = 'Requesting permissions';
        final audio = await Permission.audio.request();
        final storage = await Permission.storage.request();
        if (!audio.isGranted && !storage.isGranted) {
          _status = 'Permission denied — open Settings to grant audio access';
          return;
        }
      }

      final folders = await repo.getMusicFolders();
      if (folders.isEmpty) {
        // Pick ONE canonical root that exists. /sdcard is a symlink to
        // /storage/emulated/0 on Android, so we never want to scan both —
        // every track would end up indexed twice with different paths.
        final candidates = <String>[
          '/storage/emulated/0',
          '/sdcard',
        ];
        String? root;
        for (final path in candidates) {
          try {
            if (await Directory(path).exists()) {
              root = path;
              break;
            }
          } catch (_) {}
        }
        if (root == null) {
          _status = 'No accessible storage';
          return;
        }
        // Only register subdirs that actually exist, and only ones rooted at
        // the same canonical parent so we never double-index.
        final subDirs = <String>['Music', 'Download', 'Podcasts'];
        bool addedAny = false;
        for (final sub in subDirs) {
          final path = '$root/$sub';
          try {
            if (await Directory(path).exists()) {
              _status = 'Scanning $path';
              await repo.addMusicFolder(path, sub);
              addedAny = true;
            }
          } catch (_) {}
        }
        // If none of the subdirs exist, scan the whole root once.
        if (!addedAny) {
          _status = 'Scanning $root';
          await repo.addMusicFolder(root, 'Internal storage');
        }
      } else {
        _status = 'Rescanning';
        await repo.rescan();
      }
      _status = 'Ready';
    } catch (e) {
      _status = 'Init failed: $e';
    }
  }
}

final libraryInitializerProvider = Provider<LibraryInitializer>((ref) {
  return LibraryInitializer(ref.watch(libraryRepositoryProvider));
});
