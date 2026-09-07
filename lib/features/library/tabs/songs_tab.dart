import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/scanner/library_initializer.dart';
import '../../../shared/widgets/alphabet_scrollbar.dart';
import '../../../shared/widgets/track_tile.dart';
import '../../../shared/providers/library_providers.dart';
import '../../../playback/playback_controller.dart';

class SongsTab extends ConsumerStatefulWidget {
  const SongsTab({super.key});

  @override
  ConsumerState<SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends ConsumerState<SongsTab> {
  bool _scanning = false;
  String _status = '';
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _runScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _status = 'Requesting permission…';
    });
    try {
      await ref.read(libraryInitializerProvider).ensureInitialized();
      if (!mounted) return;
      setState(() {
        _status = ref.read(libraryInitializerProvider).status;
      });
      ref.invalidate(allTracksProvider);
      ref.invalidate(albumsProvider);
      ref.invalidate(artistsProvider);
      ref.invalidate(foldersProvider);
      ref.invalidate(musicFoldersProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Scan failed: $e');
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(allTracksProvider);
    return tracks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListView(children: [Center(child: Text('Error: $e'))]),
      data: (raw) {
        if (raw.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              try {
                await ref.read(libraryRepositoryProvider).rescan();
              } catch (_) {}
              ref.invalidate(allTracksProvider);
            },
            child: ListView(children: [
              _EmptyState(
                onScan: _runScan,
                scanning: _scanning,
                status: _status,
              ),
            ]),
          );
        }

        final list = [...raw]..sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        final pb = ref.read(playbackControllerProvider.notifier);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Text(
                    '${list.length} songs',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => pb.playFromList(list, 0, shuffle: false),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Play all'),
                  ),
                  TextButton.icon(
                    onPressed: () => pb.playFromList(list, 0, shuffle: true),
                    icon: const Icon(Icons.shuffle, size: 18),
                    label: const Text('Shuffle'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: () async {
                      try {
                        await ref.read(libraryRepositoryProvider).rescan();
                      } catch (_) {}
                      ref.invalidate(allTracksProvider);
                      ref.invalidate(albumsProvider);
                      ref.invalidate(artistsProvider);
                      ref.invalidate(foldersProvider);
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.only(right: 22),
                      itemCount: list.length,
                      itemBuilder: (ctx, i) => TrackTile(
                        track: list[i],
                        onTap: () => pb.playFromList(list, i),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: AlphabetScrollBar(
                      controller: _scroll,
                      itemCount: list.length,
                      firstIndexForLetter: (letter) {
                        for (var i = 0; i < list.length; i++) {
                          if (AlphabetScrollBar.letterFor(list[i].title) ==
                              letter) {
                            return i;
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onScan;
  final bool scanning;
  final String status;
  const _EmptyState({
    required this.onScan,
    required this.scanning,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.music_note_outlined, size: 56),
          const SizedBox(height: 16),
          Text(
            'No music yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tap below to scan your device for music files.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (scanning)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(),
            )
          else
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.search),
              label: const Text('Scan for music'),
            ),
          if (status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              status,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
