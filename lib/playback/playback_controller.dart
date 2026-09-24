import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/theme_controller.dart';
import '../data/database/app_database.dart';
import '../data/repositories/library_repository.dart';

class PlaybackState {
  final Track? current;
  final List<Track> queue;
  final int index;
  final bool playing;
  final Duration position;
  final Duration duration;
  final ShuffleMode shuffle;
  final RepeatMode repeat;

  const PlaybackState({
    this.current,
    this.queue = const [],
    this.index = 0,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.shuffle = ShuffleMode.off,
    this.repeat = RepeatMode.off,
  });

  PlaybackState copyWith({
    Track? current,
    List<Track>? queue,
    int? index,
    bool? playing,
    Duration? position,
    Duration? duration,
    ShuffleMode? shuffle,
    RepeatMode? repeat,
    bool clearCurrent = false,
  }) {
    return PlaybackState(
      current: clearCurrent ? null : (current ?? this.current),
      queue: queue ?? this.queue,
      index: index ?? this.index,
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
    );
  }
}

class PlaybackController extends StateNotifier<PlaybackState> {
  final AudioPlayer _player = AudioPlayer();
  final LibraryRepository _repo;
  final SharedPreferences _prefs;
  // Manually queued songs ("Add to queue" / "Play next") that haven't played
  // yet, tracked by TRACK ID — not by index. Indexes shift on every insert,
  // remove, reorder and shuffle rebuild, which is why the old index-based
  // tail kept breaking. Identity tracking self-heals: the up-next slot is
  // recomputed fresh from the live player position on every operation.
  final List<int> _pendingQueueIds = [];
  // While a shuffle rebuild is rearranging the audio source, the player's
  // index transiently jumps around; this flag stops the index listener from
  // clobbering state with garbage mid-rebuild.
  bool _rebuilding = false;
  /// Sleep-timer "end of track": when set, playback pauses as soon as the
  /// current song finishes (i.e. at the transition to the next one).
  bool stopAfterCurrent = false;
  // The pre-shuffle order, so we can restore linear order when the user turns
  // shuffle off. We manage shuffle ourselves (the queue list IS the play
  // order, always played linearly) — this keeps "play next" deterministic,
  // which just_audio's internal shuffle does not.
  List<Track> _originalOrder = [];
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _idxSub;
  StreamSubscription? _becomingNoisySub;
  StreamSubscription? _devicesSub;
  StreamSubscription? _interruptionSub;
  Timer? _resumeSaveTimer;
  bool _restored = false;
  AudioSession? _audioSession;

  PlaybackController(this._repo, this._prefs)
      : super(PlaybackState(
          shuffle: ShuffleMode.values[
              (_prefs.getInt(PrefsKeys.shuffleMode) ?? 0)
                  .clamp(0, ShuffleMode.values.length - 1)],
          repeat: RepeatMode.values[
              (_prefs.getInt(PrefsKeys.repeatMode) ?? 0)
                  .clamp(0, RepeatMode.values.length - 1)],
        )) {
    _wire();
    _initAudioSession();
    // Persist the current track + position every 5s so a crash never costs
    // more than a few seconds of queue context.
    _resumeSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (state.current != null && _player.playing) {
        _saveResumeState();
      }
    });
    Future.microtask(() async {
      if (_prefs.getBool(PrefsKeys.skipSilence) ?? false) {
        await _player.setSkipSilenceEnabled(true);
      }
      final s = _prefs.getDouble(PrefsKeys.playbackSpeed) ?? 1.0;
      if (s != 1.0) await _player.setSpeed(s);
      final p = _prefs.getDouble(PrefsKeys.playbackPitch) ?? 1.0;
      if (p != 1.0) {
        try {
          await _player.setPitch(p);
        } catch (_) {}
      }
    });
  }

  Future<void> _initAudioSession() async {
    try {
      _audioSession = await AudioSession.instance;
      await _audioSession!.configure(const AudioSessionConfiguration.music());
      // Auto-pause when headphones unplug. ACTION_AUDIO_BECOMING_NOISY is the
      // documented signal, but plenty of ROMs only broadcast it for the wired
      // jack, which is why Bluetooth earbuds could disconnect and leave the
      // music playing out of the phone's speaker.
      _becomingNoisySub = _audioSession!.becomingNoisyEventStream.listen((_) {
        _pauseForLostOutput();
      });

      // The reliable signal: the OS telling us an output device went away.
      // Covers Bluetooth (A2DP and headset), the wired jack and USB audio.
      _devicesSub = _audioSession!.devicesChangedEventStream.listen((event) {
        final lostListening = event.devicesRemoved.any(
          (d) => d.isOutput && _personalOutput.contains(d.type),
        );
        if (lostListening) _pauseForLostOutput();
      });
      // Pause for phone calls and resume after
      _interruptionSub =
          _audioSession!.interruptionEventStream.listen((event) {
        if (event.begin) {
          if (event.type == AudioInterruptionType.duck) {
            _player.setVolume(0.3);
          } else {
            _player.pause();
          }
        } else {
          if (event.type == AudioInterruptionType.duck) {
            _player.setVolume(1.0);
          }
          // Don't auto-resume on unknown events
        }
      });
    } catch (_) {
      // Audio session init can fail on some emulators; ignore.
    }
  }

  /// Output types that mean "only I can hear this". Losing one of them should
  /// stop the music rather than move it to the phone's speaker.
  static const _personalOutput = {
    AudioDeviceType.bluetoothA2dp,
    AudioDeviceType.bluetoothSco,
    AudioDeviceType.wiredHeadset,
    AudioDeviceType.wiredHeadphones,
    AudioDeviceType.usbAudio,
  };

  /// Pause because the thing you were listening through has gone. Both signals
  /// can arrive for one disconnect, so this is safe to call twice.
  void _pauseForLostOutput() {
    if (!(_prefs.getBool(PrefsKeys.autoPauseHeadphone) ?? true)) return;
    if (!_player.playing) return;
    _player.pause();
  }

  AudioPlayer get player => _player;

  void _wire() {
    // Once a second, not five times: every tick rebuilds the now-playing
    // screen, and on E-Ink each rebuild is a screen refresh.
    _posSub = _player
        .createPositionStream(
          steps: 1,
          minPeriod: const Duration(seconds: 1),
          maxPeriod: const Duration(seconds: 1),
        )
        .listen((p) {
      state = state.copyWith(position: p);
    });
    _durSub = _player.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    });
    _stateSub = _player.playerStateStream.listen((s) {
      state = state.copyWith(playing: s.playing);
      if (s.processingState == ProcessingState.completed) {
        _onTrackCompleted();
      }
    });
    _idxSub = _player.currentIndexStream.listen((i) async {
      if (i == null) return;
      // Ignore transient index churn while a shuffle rebuild is rearranging
      // the source — it would clobber state against the wrong queue list.
      if (_rebuilding) return;
      if (i >= 0 && i < state.queue.length) {
        // Sleep timer "end of track": the previous song just finished.
        if (stopAfterCurrent && i != state.index) {
          stopAfterCurrent = false;
          await _player.pause();
          await _player.seek(Duration.zero);
        }
        final nowPlaying = state.queue[i];
        // A manually queued song is "consumed" the moment it starts playing.
        _pendingQueueIds.remove(nowPlaying.id);
        state = state.copyWith(
          index: i,
          current: nowPlaying,
        );
        await _repo.recordPlay(nowPlaying.id);
        await _saveResumeState();
      }
    });
  }

  Future<void> setSkipSilence(bool enabled) async {
    await _player.setSkipSilenceEnabled(enabled);
    await _prefs.setBool(PrefsKeys.skipSilence, enabled);
  }

  bool get skipSilence => _prefs.getBool(PrefsKeys.skipSilence) ?? false;

  /// When true, the player is locked to whole-album listening: shuffle is
  /// forced off, next/previous are no-ops, and playback stops when the
  /// queue ends instead of looping to another album.
  bool get albumOnly => _prefs.getBool(PrefsKeys.albumOnlyMode) ?? false;

  Future<void> setAlbumOnly(bool enabled) async {
    await _prefs.setBool(PrefsKeys.albumOnlyMode, enabled);
    if (enabled && state.shuffle == ShuffleMode.on) {
      await setShuffle(ShuffleMode.off);
    }
    // Force a state notification so listeners (mini-player, now-playing)
    // re-render with the right disabled state.
    state = state.copyWith();
  }

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    await _prefs.setDouble(PrefsKeys.playbackSpeed, speed);
  }

  double get speed => _prefs.getDouble(PrefsKeys.playbackSpeed) ?? 1.0;

  Future<void> setPitch(double pitch) async {
    try {
      await _player.setPitch(pitch);
      await _prefs.setDouble(PrefsKeys.playbackPitch, pitch);
    } catch (_) {
      // Pitch may not be supported on all platforms; silently ignore.
    }
  }

  double get pitch => _prefs.getDouble(PrefsKeys.playbackPitch) ?? 1.0;

  /// Smooth fade-out → pause. Used by auto-fade-on-pause and the sleep timer.
  Future<void> fadePause({Duration duration = const Duration(milliseconds: 300)}) async {
    if (!_player.playing) return;
    final start = _player.volume;
    const steps = 12;
    final stepDur = duration ~/ steps;
    for (var i = steps - 1; i >= 0; i--) {
      await _player.setVolume(start * (i / steps));
      await Future.delayed(stepDur);
    }
    await _player.pause();
    await _player.setVolume(start);
  }

  Future<void> fadeOutAndPause(Duration duration) async {
    if (!_player.playing) return;
    final start = _player.volume;
    final steps = (duration.inMilliseconds / 100).clamp(8, 200).toInt();
    final stepDur = duration ~/ steps;
    for (var i = steps - 1; i >= 0; i--) {
      await _player.setVolume(start * (i / steps));
      await Future.delayed(stepDur);
    }
    await _player.pause();
    await _player.setVolume(start);
  }

  /// [shuffle] semantics:
  ///   - null  → respect the current global shuffle toggle
  ///   - true  → force shuffle on for this queue (and flip the toggle on)
  ///   - false → force play in the exact given order (and flip the toggle off)
  ///
  /// Spotify queue semantics: starting a new album/playlist replaces the
  /// CONTEXT ("next up from…"), but any manually queued songs ("next in
  /// queue") survive the switch — they still play right after the tapped
  /// track, before the new context continues.
  Future<void> playFromList(
    List<Track> tracks,
    int startIndex, {
    bool? shuffle,
  }) async {
    if (tracks.isEmpty) return;

    // Carry over manually queued songs from the old queue (identity-based:
    // the contiguous run of pending ids sitting after the current track).
    final carried = <Track>[];
    if (_pendingQueueIds.isNotEmpty && state.queue.isNotEmpty) {
      final cur = _liveIndex;
      for (var i = cur + 1;
          i < state.queue.length &&
              _pendingQueueIds.contains(state.queue[i].id);
          i++) {
        carried.add(state.queue[i]);
      }
    }
    _pendingQueueIds
      ..clear()
      ..addAll(carried.map((t) => t.id));

    _originalOrder = List.of(tracks);

    final bool shuffleOn;
    if (shuffle != null) {
      shuffleOn = shuffle;
      final mode = shuffle ? ShuffleMode.on : ShuffleMode.off;
      if (state.shuffle != mode) {
        state = state.copyWith(shuffle: mode);
        await _prefs.setInt(PrefsKeys.shuffleMode, mode.index);
      }
    } else {
      shuffleOn = state.shuffle == ShuffleMode.on;
    }

    List<Track> queue;
    int idx;
    if (shuffle == true) {
      // Explicit "Shuffle" action: randomise EVERYTHING, including which
      // song goes first. (Previously the album's first track was pinned to
      // position 0, so "shuffle" always opened with the same song.)
      final all = [...tracks]..shuffle(math.Random());
      queue = [all.first, ...carried, ...all.skip(1)];
      idx = 0;
    } else if (shuffleOn) {
      // Shuffle mode is on but the user tapped a specific song: that song
      // plays first, queued songs glued right after it, the rest shuffled.
      final current = tracks[startIndex];
      final rest = [...tracks]..removeAt(startIndex);
      rest.shuffle(math.Random());
      queue = [current, ...carried, ...rest];
      idx = 0;
    } else {
      // Tapped track keeps its place in the album/playlist order; queued
      // songs slot in right after it, then the context continues.
      final before = tracks.sublist(0, startIndex + 1);
      final after = tracks.sublist(startIndex + 1);
      queue = [...before, ...carried, ...after];
      idx = startIndex;
    }

    state = state.copyWith(
      queue: queue,
      index: idx,
      current: queue[idx],
    );
    await _loadQueue(startAt: idx);
    await _player.play();
    await _saveResumeState();
  }

  Future<void> _loadQueue({required int startAt}) async {
    final sources = state.queue.map(_toMediaItem).toList();
    // Gapless playback: when ON (default), each upcoming source is prepared
    // eagerly so the transition between tracks is sample-accurate. When OFF,
    // sources are loaded lazily and a small silence sneaks in between songs.
    // Always lazy. Eager preparation opened and parsed every file in the
    // queue up front — four hundred of them when playing from all songs —
    // and kept them all prepared, which is where the battery went while
    // listening. ExoPlayer still prepares the next item ahead of time, so
    // the gapless join is unaffected.
    final source = ConcatenatingAudioSource(
      children: sources,
      useLazyPreparation: true,
    );
    // We always play linearly; shuffle is reflected in the ORDER of the queue
    // list itself, never via just_audio's internal shuffle. This makes
    // "play next" / "add to queue" behave deterministically.
    await _player.setShuffleModeEnabled(false);
    await _player.setAudioSource(source, initialIndex: startAt);
    await _applyRepeatMode();
  }

  Future<void> _applyRepeatMode() async {
    switch (state.repeat) {
      case RepeatMode.off:
        await _player.setLoopMode(LoopMode.off);
        break;
      case RepeatMode.all:
        await _player.setLoopMode(LoopMode.all);
        break;
      case RepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
    }
  }

  AudioSource _toMediaItem(Track t) {
    return AudioSource.uri(
      Uri.parse(t.uri.startsWith('content://') || t.uri.startsWith('file://')
          ? t.uri
          : 'file://${t.uri}'),
    );
  }

  Future<void> play() async {
    // Explicitly take audio focus. Without an active audio session the OS
    // won't route the hardware volume keys to the music stream when the
    // screen is locked or we're in the background — it falls back to the
    // ringer. Mudita's ROM doesn't auto-activate, so we do it ourselves.
    try {
      await _audioSession?.setActive(true);
    } catch (_) {}
    await _player.play();
  }

  Future<void> pause() async {
    if (_prefs.getBool(PrefsKeys.autoFadePause) ?? false) {
      await fadePause();
    } else {
      await _player.pause();
    }
    // Note: we intentionally keep the audio session active on pause so the
    // volume keys still control music while paused-but-locked.
  }

  Future<void> toggle() async {
    if (_player.playing) {
      await pause();
    } else {
      await _player.play();
    }
  }

  Future<void> next() async {
    if (albumOnly) return; // committed album listening — no skipping
    _maybeRecordSkip();
    await _player.seekToNext();
  }

  /// Jump straight to a song in the queue (tapped from the queue screen).
  Future<void> skipTo(int index) async {
    if (albumOnly) return;
    if (index < 0 || index >= state.queue.length) return;
    _maybeRecordSkip();
    await _player.seek(Duration.zero, index: index);
    if (!_player.playing) await _player.play();
  }

  Future<void> stopAndClear() async {
    _pendingQueueIds.clear();
    await _player.stop();
    state = state.copyWith(
      queue: const [],
      index: 0,
      clearCurrent: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    await _prefs.remove(PrefsKeys.lastTrackId);
    await _prefs.remove(PrefsKeys.lastPositionMs);
    await _prefs.remove(PrefsKeys.lastQueueIds);
  }

  Future<void> previous() async {
    if (albumOnly) {
      // Allow scrubbing back to the start of the same song, but no skipping
      // to a previous track in album-only mode.
      await _player.seek(Duration.zero);
      return;
    }
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else {
      _maybeRecordSkip();
      await _player.seekToPrevious();
    }
  }

  void _maybeRecordSkip() {
    final cur = state.current;
    if (cur == null) return;
    final dur = state.duration.inMilliseconds;
    if (dur <= 0) return;
    final progressed = state.position.inMilliseconds / dur;
    if (progressed < AppConstants.skipThresholdFraction) {
      _repo.recordSkip(cur.id);
    }
  }

  Future<void> seek(Duration to) async => _player.seek(to);

  Future<void> setShuffle(ShuffleMode mode) async {
    // Shuffle is disallowed while in album-only mode — silently reject.
    if (mode == ShuffleMode.on && albumOnly) return;
    final wasOn = state.shuffle == ShuffleMode.on;
    state = state.copyWith(shuffle: mode);
    await _prefs.setInt(PrefsKeys.shuffleMode, mode.index);

    final source = _player.audioSource;
    if (source is! ConcatenatingAudioSource || state.queue.isEmpty) return;
    final cur = state.current;
    if (cur == null) return;

    // Pull the manually-queued songs out so they survive the reshuffle and
    // stay glued right after the current track — same as Spotify.
    final curIdx = _liveIndex;
    final pending = <Track>[];
    for (var i = curIdx + 1;
        i < state.queue.length &&
            _pendingQueueIds.contains(state.queue[i].id);
        i++) {
      pending.add(state.queue[i]);
    }
    final pendingIds = pending.map((t) => t.id).toSet();

    if (mode == ShuffleMode.on && !wasOn) {
      // Keep _originalOrder if we have it; otherwise snapshot now.
      if (_originalOrder.isEmpty) _originalOrder = List.of(state.queue);
      // Build: current first, queued songs next, everything else shuffled.
      final rest = [...state.queue]..removeAt(curIdx);
      rest.removeWhere((t) => pendingIds.contains(t.id));
      rest.shuffle(math.Random());
      await _rebuildAround(cur, before: const [], after: [...pending, ...rest]);
    } else if (mode == ShuffleMode.off && wasOn) {
      // Restore linear order around the current track, queued songs first.
      final orig =
          _originalOrder.isNotEmpty ? _originalOrder : List.of(state.queue);
      final origIdx = orig.indexWhere((t) => t.id == cur.id);
      if (origIdx < 0) {
        // Current track isn't in original list; just keep what we have.
        return;
      }
      final before = orig.sublist(0, origIdx).toList()
        ..removeWhere((t) => pendingIds.contains(t.id));
      final after = orig.sublist(origIdx + 1).toList()
        ..removeWhere((t) => pendingIds.contains(t.id));
      await _rebuildAround(cur, before: before, after: [...pending, ...after]);
    }
  }

  /// Rearrange the live ConcatenatingAudioSource so [current] keeps playing
  /// uninterrupted, with [before] placed ahead of it and [after] behind it.
  Future<void> _rebuildAround(
    Track current, {
    required List<Track> before,
    required List<Track> after,
  }) async {
    final source = _player.audioSource;
    if (source is! ConcatenatingAudioSource) return;
    // Mute the index listener: removing items before the current track makes
    // the player's index jump around transiently, and the listener would
    // clobber state (and record phantom plays) against the half-built queue.
    _rebuilding = true;
    try {
      final curIdx = _liveIndex;
      // Remove everything after current, then everything before — leaving
      // only the currently-playing item, never touched (no audio restart).
      if (curIdx + 1 < source.length) {
        await source.removeRange(curIdx + 1, source.length);
      }
      if (curIdx > 0) {
        await source.removeRange(0, curIdx);
      }
      // Now current is the only child, at index 0.
      if (before.isNotEmpty) {
        await source.insertAll(0, before.map(_toMediaItem).toList());
      }
      if (after.isNotEmpty) {
        await source.addAll(after.map(_toMediaItem).toList());
      }
      state = state.copyWith(
        queue: [...before, current, ...after],
        index: before.length,
      );
      await _saveResumeState();
    } finally {
      _rebuilding = false;
    }
  }

  Future<void> toggleShuffle() async {
    await setShuffle(
      state.shuffle == ShuffleMode.on ? ShuffleMode.off : ShuffleMode.on,
    );
  }

  Future<void> cycleRepeat() async {
    final next = switch (state.repeat) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    state = state.copyWith(repeat: next);
    await _prefs.setInt(PrefsKeys.repeatMode, next.index);
    await _applyRepeatMode();
  }

  /// The player's own index is updated synchronously with track changes;
  /// state.index lags behind it by one stream event. Always position queue
  /// inserts against the live value so a queue-during-transition can't land
  /// behind the playhead.
  int get _liveIndex {
    final i = _player.currentIndex;
    if (i != null && i >= 0 && i < state.queue.length) return i;
    return state.index.clamp(0, state.queue.isEmpty ? 0 : state.queue.length - 1);
  }

  /// Where the next queued item should go: right after the current song,
  /// past any still-pending manually queued songs. Identity-based — walks
  /// the actual queue contents instead of trusting a stored index.
  int _nextQueueSlot() {
    if (state.queue.isEmpty) return 0;
    var slot = _liveIndex + 1;
    while (slot < state.queue.length &&
        _pendingQueueIds.contains(state.queue[slot].id)) {
      slot++;
    }
    return slot.clamp(0, state.queue.length);
  }

  /// IDs of manually queued songs that haven't played yet. Used by the queue
  /// screen to render the "Next in queue" section, Spotify-style.
  Set<int> get pendingQueueIds => _pendingQueueIds.toSet();

  /// "Add to queue" — accumulates after the current song. First add plays
  /// next; the second add plays after the first, and so on.
  Future<void> addToQueue(Track t) async {
    if (state.queue.isEmpty) {
      // Nothing playing — just start playing this track.
      await playFromList([t], 0);
      return;
    }
    final insertAt = _nextQueueSlot();
    final source = _player.audioSource;
    if (source is! ConcatenatingAudioSource) return;
    // Mutate the player FIRST; only commit our bookkeeping if it succeeds,
    // so state.queue can never drift out of sync with what's audible.
    await source.insert(insertAt, _toMediaItem(t));
    final newQueue = [...state.queue]..insert(insertAt, t);
    state = state.copyWith(queue: newQueue);
    _pendingQueueIds.add(t.id);
    _originalOrder = [..._originalOrder, t];
    await _saveResumeState();
  }

  /// "Play next" — jumps the song to the front of the up-next zone, right
  /// after the current track (ahead of anything previously queued).
  Future<void> playNext(Track t) async {
    if (state.queue.isEmpty) {
      await playFromList([t], 0);
      return;
    }
    final insertAt = (_liveIndex + 1).clamp(0, state.queue.length);
    final source = _player.audioSource;
    if (source is! ConcatenatingAudioSource) return;
    await source.insert(insertAt, _toMediaItem(t));
    final newQueue = [...state.queue]..insert(insertAt, t);
    state = state.copyWith(queue: newQueue);
    _pendingQueueIds.insert(0, t.id);
    _originalOrder = [..._originalOrder, t];
    await _saveResumeState();
  }

  /// Queue a whole album/playlist after any already-queued songs, in order.
  Future<void> addAllToQueue(List<Track> tracks) async {
    for (final t in tracks) {
      await addToQueue(t);
    }
  }

  /// Play a whole album/playlist next, in order, ahead of the queued zone.
  Future<void> playAllNext(List<Track> tracks) async {
    // playNext puts each song at the FRONT of the zone, so feed it the list
    // reversed to end up in the original order.
    for (final t in tracks.reversed) {
      await playNext(t);
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final list = [...state.queue];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = state.copyWith(queue: list);
    final source = _player.audioSource;
    if (source is ConcatenatingAudioSource) {
      await source.move(oldIndex, newIndex);
    }
    // Identity-based queue tracking survives reorders — if the user drags a
    // queued song out of the up-next zone, treat it as un-queueing it.
    final cur = _liveIndex;
    if (_pendingQueueIds.contains(item.id)) {
      final stillInZone = newIndex > cur &&
          (newIndex == cur + 1 ||
              _pendingQueueIds.contains(state.queue[newIndex - 1].id));
      if (!stillInZone) _pendingQueueIds.remove(item.id);
    }
  }

  Future<void> removeFromQueue(int idx) async {
    if (idx < 0 || idx >= state.queue.length) return;
    final removed = state.queue[idx];
    final list = [...state.queue]..removeAt(idx);
    state = state.copyWith(queue: list);
    final source = _player.audioSource;
    if (source is ConcatenatingAudioSource) {
      await source.removeAt(idx);
    }
    _pendingQueueIds.remove(removed.id);
  }

  void _onTrackCompleted() {}

  int? _savedQueueSig;

  Future<void> _saveResumeState() async {
    final cur = state.current;
    if (cur == null) return;
    await _prefs.setInt(PrefsKeys.lastTrackId, cur.id);
    // Read live position from player (state.position can be slightly stale).
    await _prefs.setInt(PrefsKeys.lastPositionMs, _player.position.inMilliseconds);
    // The queue list is only rewritten when it actually changes. Writing
    // hundreds of ids to disk every five seconds was steady work for nothing.
    final ids = state.queue.map((t) => t.id.toString()).toList();
    final sig = Object.hashAll(ids);
    if (sig != _savedQueueSig) {
      await _prefs.setStringList(PrefsKeys.lastQueueIds, ids);
      _savedQueueSig = sig;
    }
  }

  Future<void> restoreLastSession() async {
    if (_restored) return;
    _restored = true;
    final ids = _prefs.getStringList(PrefsKeys.lastQueueIds);
    final lastTrackId = _prefs.getInt(PrefsKeys.lastTrackId);
    final lastPosMs = _prefs.getInt(PrefsKeys.lastPositionMs) ?? 0;
    if (ids == null || ids.isEmpty || lastTrackId == null) return;

    final allTracks = await _repo.allTracks();
    final byId = {for (final t in allTracks) t.id: t};
    final queue = ids
        .map((s) => int.tryParse(s))
        .where((id) => id != null && byId.containsKey(id))
        .map((id) => byId[id]!)
        .toList();
    if (queue.isEmpty) return;
    final idx = queue.indexWhere((t) => t.id == lastTrackId);
    if (idx < 0) return;

    state = state.copyWith(
      queue: queue,
      index: idx,
      current: queue[idx],
    );
    await _loadQueue(startAt: idx);
    if (lastPosMs > 0) {
      await _player.seek(Duration(milliseconds: lastPosMs));
    }
  }

  @override
  Future<void> dispose() async {
    _resumeSaveTimer?.cancel();
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _stateSub?.cancel();
    await _idxSub?.cancel();
    await _becomingNoisySub?.cancel();
    await _devicesSub?.cancel();
    await _interruptionSub?.cancel();
    await _player.dispose();
    super.dispose();
  }
}

final playbackControllerProvider =
    StateNotifierProvider<PlaybackController, PlaybackState>((ref) {
  return PlaybackController(
    ref.watch(libraryRepositoryProvider),
    ref.watch(sharedPreferencesProvider),
  );
});

final positionStreamProvider = StreamProvider<Duration>((ref) {
  final p = ref.watch(playbackControllerProvider.notifier);
  return p.player.createPositionStream(
    steps: 1,
    minPeriod: const Duration(seconds: 1),
    maxPeriod: const Duration(seconds: 1),
  );
});
