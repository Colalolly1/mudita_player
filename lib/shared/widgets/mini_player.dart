import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../playback/playback_controller.dart';
import 'cover_art.dart';

/// Cover, title, artist, one button. Tap or swipe up for everything else.
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
      color: scheme.surface,
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
                minHeight: 1,
                backgroundColor: scheme.outlineVariant,
                valueColor: AlwaysStoppedAnimation(scheme.onSurface),
              ),
              SizedBox(
                height: 64,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    CoverArt(
                      artUri: t.artUri.isEmpty ? null : t.artUri,
                      size: 44,
                      radius: 0,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w500),
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
                      iconSize: 30,
                      icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
                      onPressed: () => ref
                          .read(playbackControllerProvider.notifier)
                          .toggle(),
                    ),
                    const SizedBox(width: 8),
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
