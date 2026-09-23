import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../playback/playback_controller.dart';
import '../../shared/widgets/cover_art.dart';

/// The queue the way Spotify does it: what's playing, then what's next.
/// Songs already played are not shown; you can't get lost in them.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final ctrl = ref.read(playbackControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    if (state.queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Queue')),
        body: const Center(child: Text('Queue is empty')),
      );
    }

    final current = state.queue[state.index.clamp(0, state.queue.length - 1)];
    final base = state.index + 1;
    final upcoming = base < state.queue.length ? state.queue.sublist(base) : const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Queue')),
      body: ReorderableListView.builder(
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Label(context, 'Now playing'),
            ListTile(
              leading: CoverArt(
                artUri: current.artUri.isEmpty ? null : current.artUri,
                size: 44,
              ),
              title: Text(current.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(current.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            _Label(
                context,
                upcoming.isEmpty
                    ? 'Nothing next'
                    : 'Next up · ${upcoming.length}'),
          ],
        ),
        itemCount: upcoming.length,
        onReorder: (o, n) => ctrl.reorderQueue(o + base, n + base),
        itemBuilder: (ctx, i) {
          final t = upcoming[i];
          final queued = ctrl.pendingQueueIds.contains(t.id);
          return Dismissible(
            key: ValueKey('q-${t.id}-${i + base}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red.withAlpha(40),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.delete_outline),
            ),
            onDismissed: (_) => ctrl.removeFromQueue(i + base),
            child: ListTile(
              onTap: () => ctrl.skipTo(i + base),
              leading: CoverArt(
                artUri: t.artUri.isEmpty ? null : t.artUri,
                size: 40,
              ),
              title: Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(t.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (queued)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: scheme.onSurface.withAlpha(160)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('IN QUEUE',
                          style:
                              TextStyle(fontSize: 9, letterSpacing: 0.6)),
                    ),
                  ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _Label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(letterSpacing: 1.0)),
      );
}
