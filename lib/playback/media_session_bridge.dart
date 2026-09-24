import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_controller.dart';

/// Talks to the native [MediaPlaybackService] in MainActivity.kt.
///
/// Pushes playback metadata + state to it whenever the player changes; subscribes
/// to its event channel to receive media-button presses (lock screen, car,
/// Bluetooth, headphone hook).
class MediaSessionBridge {
  static const _control =
      MethodChannel('com.muditakompakt.mudita_player/media_control');
  static const _events =
      EventChannel('com.muditakompakt.mudita_player/media_events');

  final Ref _ref;
  StreamSubscription? _eventSub;
  ProviderSubscription? _stateSub;
  bool _serviceStarted = false;
  String _lastTitle = '';
  String? _lastArt;
  int _lastDurationMs = 0;
  int _lastStatePushMs = 0;
  int _lastPushedPosMs = 0;
  bool _lastPlaying = false;

  MediaSessionBridge(this._ref);

  void init() {
    _eventSub = _events
        .receiveBroadcastStream()
        .listen(_onAction, onError: (_) {});
    _stateSub = _ref.listen<PlaybackState>(
      playbackControllerProvider,
      (prev, next) => _push(next),
      fireImmediately: true,
    );
  }

  Future<void> _push(PlaybackState next) async {
    final cur = next.current;
    if (cur == null) {
      if (_serviceStarted) {
        try {
          await _control.invokeMethod('stop');
        } catch (_) {}
        _serviceStarted = false;
        _lastTitle = '';
        _lastArt = null;
        _lastDurationMs = 0;
      }
      return;
    }

    if (!_serviceStarted) {
      try {
        await _control.invokeMethod('start');
        _serviceStarted = true;
      } catch (_) {}
    }

    // Prefer the player's real duration; fall back to the tag value. The
    // player duration arrives a moment after the track loads, so we re-push
    // metadata when it changes — otherwise the car shows no progress bar.
    final realDuration = next.duration.inMilliseconds > 0
        ? next.duration.inMilliseconds
        : cur.durationMs;

    final metaChanged = cur.title != _lastTitle ||
        cur.artUri != _lastArt ||
        realDuration != _lastDurationMs;

    if (metaChanged) {
      _lastTitle = cur.title;
      _lastArt = cur.artUri;
      _lastDurationMs = realDuration;
      final art = cur.artUri.isEmpty ? null : cur.artUri;
      try {
        await _control.invokeMethod('setMetadata', {
          'title': cur.title,
          'artist': cur.artist.isEmpty ? null : cur.artist,
          'album': cur.album.isEmpty ? null : cur.album,
          'durationMs': realDuration,
          'artPath': art,
        });
      } catch (_) {}
    }

    // Android extrapolates the position itself from the last state and the
    // speed, so the session only needs a new state when something actually
    // changed: play/pause, a new track, or a seek. Pushing every second
    // re-posted the media notification every second, and every notification
    // listener on the phone (Bigme's standby app among them) woke for it.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final playStateChanged = next.playing != _lastPlaying;
    final posMs = next.position.inMilliseconds;
    final expectedMs = _lastPushedPosMs +
        (_lastPlaying ? nowMs - _lastStatePushMs : 0);
    final seeked = (posMs - expectedMs).abs() > 1500;
    if (playStateChanged || metaChanged || seeked || _lastStatePushMs == 0) {
      _lastStatePushMs = nowMs;
      _lastPushedPosMs = posMs;
      _lastPlaying = next.playing;
      try {
        await _control.invokeMethod('setPlaybackState', {
          'playing': next.playing,
          'positionMs': next.position.inMilliseconds,
        });
      } catch (_) {}
    }
  }

  /// True if the app is exempt from battery optimization (so the OS won't
  /// kill the media service in the background).
  Future<bool> isBatteryExempt() async {
    try {
      return (await _control.invokeMethod<bool>('isBatteryExempt')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "ignore battery optimizations" prompt for this app.
  Future<bool> requestBatteryExemption() async {
    try {
      return (await _control.invokeMethod<bool>('requestBatteryExemption')) ??
          false;
    } catch (_) {
      return false;
    }
  }

  void _onAction(dynamic ev) {
    final action = ev as String? ?? '';
    final pb = _ref.read(playbackControllerProvider.notifier);
    if (action == 'play') {
      pb.play();
    } else if (action == 'pause') {
      pb.pause();
    } else if (action == 'next') {
      pb.next();
    } else if (action == 'previous') {
      pb.previous();
    } else if (action == 'stop') {
      pb.stopAndClear();
    } else if (action.startsWith('seek:')) {
      final ms = int.tryParse(action.substring(5));
      if (ms != null) pb.seek(Duration(milliseconds: ms));
    }
  }

  void dispose() {
    _eventSub?.cancel();
    _stateSub?.close();
    if (_serviceStarted) {
      _control.invokeMethod('stop').catchError((_) => null);
    }
  }
}

final mediaSessionBridgeProvider = Provider<MediaSessionBridge>((ref) {
  final bridge = MediaSessionBridge(ref);
  bridge.init();
  ref.onDispose(bridge.dispose);
  return bridge;
});
