import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../playback/playback_controller.dart';
import '../../shared/widgets/cover_art.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackControllerProvider);
    final ctrl = ref.read(playbackControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
      ),
      body: state.queue.isEmpty
          ? const Center(child: Text('Queue is empty'))
          : ReorderableListView.builder(
              itemCount: state.queue.length,
              onReorder: (o, n) => ctrl.reorderQueue(o, n),
              itemBuilder: (ctx, i) {
                final t = state.queue[i];
                final isCurrent = i == state.index;
                final isQueued =
                    !isCurrent && ctrl.pendingQueueIds.contains(t.id);
                final accent = Theme.of(context).colorScheme.primary;
                return Dismissible(
                  key: ValueKey('q-${t.id}-$i'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red.withAlpha(40),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete_outline),
                  ),
                  onDismissed: (_) => ctrl.removeFromQueue(i),
                  child: ListTile(
                    leading: CoverArt(
                      artUri: t.artUri.isEmpty ? null : t.artUri,
                      size: 40,
                    ),
                    title: Text(
                      t.title,
                      style: TextStyle(
                        fontWeight:
                            isCurrent ? FontWeight.w600 : FontWeight.w500,
                        color: isCurrent ? accent : null,
                      ),
                    ),
                    subtitle: Text(t.artist,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isQueued)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              border: Border.all(color: accent.withAlpha(160)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'IN QUEUE',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 0.6,
                                color: accent,
                              ),
                            ),
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
}
