import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../playback/playback_controller.dart';
import 'cover_art.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    if (state.current == null) return const SizedBox.shrink();
    final t = state.current!;

    final progress = state.duration.inMilliseconds == 0
        ? 0.0
        : (state.position.inMilliseconds / state.duration.inMilliseconds)
            .clamp(0.0, 1.0);

    return Material(
      color: scheme.surfaceContainer,
      child: GestureDetector(
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -300) context.push('/now-playing');
        },
        child: InkWell(
          onTap: () => context.push('/now-playing'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: progress,
                minHeight: 1.5,
                backgroundColor: scheme.outlineVariant,
                valueColor: AlwaysStoppedAnimation(scheme.primary),
              ),
              SizedBox(
                height: 60,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    CoverArt(
                      artUri: t.artUri.isEmpty ? null : t.artUri,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      onPressed: ref
                              .read(playbackControllerProvider.notifier)
                              .albumOnly
                          ? null
                          : () => ref
                              .read(playbackControllerProvider.notifier)
                              .previous(),
                    ),
                    IconButton(
                      icon: Icon(state.playing
                          ? Icons.pause_outlined
                          : Icons.play_arrow),
                      onPressed: () => ref
                          .read(playbackControllerProvider.notifier)
                          .toggle(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: ref
                              .read(playbackControllerProvider.notifier)
                              .albumOnly
                          ? null
                          : () => ref
                              .read(playbackControllerProvider.notifier)
                              .next(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Stop and clear queue',
                      onPressed: () => ref
                          .read(playbackControllerProvider.notifier)
                          .stopAndClear(),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
