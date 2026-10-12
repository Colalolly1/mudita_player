import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_controller.dart';
import '../../data/database/app_database.dart';
import '../../data/lyrics/lyrics_loader.dart';
import '../../playback/playback_controller.dart';

class LyricsScreen extends ConsumerStatefulWidget {
  final Track track;
  const LyricsScreen({super.key, required this.track});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  late Future<LoadedLyrics> _future;
  final _scroll = ScrollController();
  int _activeIdx = -1;

  @override
  void initState() {
    super.initState();
    _future = ref.read(lyricsLoaderProvider).load(
          widget.track.uri,
          overridePath: widget.track.syncedLyricsPath.isEmpty
              ? null
              : widget.track.syncedLyricsPath,
        );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final karaoke = prefs.getBool(PrefsKeys.karaokeMode) ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lyrics'),
        actions: [
          IconButton(
            icon: Icon(karaoke ? Icons.mic : Icons.mic_none),
            tooltip: karaoke ? 'Karaoke on' : 'Karaoke off',
            onPressed: () async {
              await prefs.setBool(PrefsKeys.karaokeMode, !karaoke);
              setState(() {});
            },
          ),
        ],
      ),
      body: FutureBuilder<LoadedLyrics>(
        future: _future,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lyrics = snap.data!;
          if (lyrics.isEmpty) {
            return const Center(child: Text('No lyrics found'));
          }
          if (lyrics.isSynced) {
            return _Synced(
              lyrics: lyrics,
              scroll: _scroll,
              karaoke: karaoke,
              onActive: (i) {
                if (i != _activeIdx) {
                  _activeIdx = i;
                  _autoScroll(i, lyrics.synced.length);
                }
              },
            );
          }
          return _Plain(text: lyrics.plain ?? '', karaoke: karaoke);
        },
      ),
    );
  }

  void _autoScroll(int i, int total) {
    if (!_scroll.hasClients) return;
    final approxLineH = 36.0;
    final target = (i * approxLineH) - MediaQuery.of(context).size.height / 3;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }
}

class _Plain extends StatelessWidget {
  final String text;
  final bool karaoke;
  const _Plain({required this.text, this.karaoke = false});
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(karaoke ? 32 : 24),
      child: Text(
        text,
        textAlign: karaoke ? TextAlign.center : TextAlign.left,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: karaoke ? 22 : 16,
              fontWeight: karaoke ? FontWeight.w500 : FontWeight.w400,
              height: 1.7,
            ),
      ),
    );
  }
}

class _Synced extends ConsumerWidget {
  final LoadedLyrics lyrics;
  final ScrollController scroll;
  final ValueChanged<int> onActive;
  final bool karaoke;

  const _Synced({
    required this.lyrics,
    required this.scroll,
    required this.onActive,
    this.karaoke = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(positionStreamProvider).valueOrNull ??
        ref.read(playbackControllerProvider.notifier).player.position;
    int active = -1;
    for (var i = 0; i < lyrics.synced.length; i++) {
      if (lyrics.synced[i].time <= pos) active = i;
    }
    if (active >= 0) WidgetsBinding.instance.addPostFrameCallback((_) => onActive(active));

    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    // Other lines: about #757575 on white, never lighter than #777777.
    final muted = Color.lerp(scheme.onSurface, scheme.surface, 0.42)!;
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      itemCount: lyrics.synced.length,
      itemBuilder: (ctx, i) {
        final line = lyrics.synced[i];
        final isActive = i == active;
        return GestureDetector(
          onTap: () => ref
              .read(playbackControllerProvider.notifier)
              .seek(line.time),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: karaoke ? 12 : 6),
            child: Text(
              line.text.isEmpty ? '·' : line.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: karaoke
                    ? (isActive ? 32 : 18)
                    : (isActive ? 22 : 16),
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                color: isActive ? accent : muted,
                height: 1.4,
              ),
            ),
          ),
        );
      },
    );
  }
}
