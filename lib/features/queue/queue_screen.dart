import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../playback/playback_controller.dart';
import '../../shared/widgets/cover_art.dart';

/// The queue, opened at the song that's playing. Starting a song from "all
/// songs" puts the whole library in the queue, so without this you'd land
/// at the top and have to scroll hundreds of rows to find your place.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  static const double _rowHeight = 64;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final index = ref.read(playbackControllerProvider).index;
    _scroll = ScrollController(initialScrollOffset: _offsetFor(index));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Put the current song one row down from the top, so the song before it
  /// is visible for context and everything after it reads as "up next".
  double _offsetFor(int index) => ((index - 1) * _rowHeight).clamp(0, double.infinity).toDouble();

  void _jumpToCurrent() {
    if (!_scroll.hasClients) return;
    final index = ref.read(playbackControllerProvider).index;
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      _offsetFor(index).clamp(0, max),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackControllerProvider);
    final ctrl = ref.read(playbackControllerProvider.notifier);
    final upNext = (state.queue.length - state.index - 1).clamp(0, state.queue.length);

    return Scaffold(
      appBar: AppBar(
        title: Text(state.queue.isEmpty
            ? 'Queue'
            : 'Queue · ${state.index + 1} of ${state.queue.length}'),
        actions: [
          if (state.queue.isNotEmpty)
            TextButton(
              onPressed: _jumpToCurrent,
              child: const Text('Now playing'),
            ),
        ],
      ),
      body: state.queue.isEmpty
          ? const Center(child: Text('Queue is empty'))
          : ReorderableListView.builder(
              scrollController: _scroll,
              itemExtent: _rowHeight,
              itemCount: state.queue.length,
              onReorder: (o, n) => ctrl.reorderQueue(o, n),
              footer: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    upNext == 0 ? 'End of the queue' : '$upNext up next',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              itemBuilder: (ctx, i) {
                final t = state.queue[i];
                final isCurrent = i == state.index;
                final isPast = i < state.index;
                final isQueued =
                    !isCurrent && ctrl.pendingQueueIds.contains(t.id);
                final scheme = Theme.of(context).colorScheme;
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
                  child: Container(
                    // A firm left rule marks the song that's playing; e-ink
                    // shows this more reliably than a colour change alone.
                    decoration: isCurrent
                        ? BoxDecoration(
                            border: Border(
                              left: BorderSide(color: scheme.onSurface, width: 3),
                            ),
                          )
                        : null,
                    child: ListTile(
                      onTap: isCurrent ? null : () => ctrl.skipTo(i),
                      leading: CoverArt(
                        artUri: t.artUri.isEmpty ? null : t.artUri,
                        size: 40,
                      ),
                      title: Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isPast ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                      subtitle: Text(
                        isCurrent ? 'Now playing · ${t.artist}' : t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isQueued)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: scheme.onSurface.withAlpha(160)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'IN QUEUE',
                                style: TextStyle(fontSize: 9, letterSpacing: 0.6),
                              ),
                            ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
