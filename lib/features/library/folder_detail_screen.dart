import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/track_tile.dart';
import '../../shared/providers/library_providers.dart';
import '../../playback/playback_controller.dart';

class FolderDetailScreen extends ConsumerWidget {
  final String folderUri;
  final String displayPath;
  const FolderDetailScreen({
    super.key,
    required this.folderUri,
    required this.displayPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(folderTracksProvider(folderUri));
    return Scaffold(
      appBar: AppBar(title: Text(displayPath)),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tracks) {
          if (tracks.isEmpty) return const Center(child: Text('No tracks'));
          return ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (ctx, i) => TrackTile(
              track: tracks[i],
              onTap: () => ref
                  .read(playbackControllerProvider.notifier)
                  .playFromList(tracks, i),
            ),
          );
        },
      ),
    );
  }
}
