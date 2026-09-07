import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/track_tile.dart';
import '../../shared/providers/library_providers.dart';
import '../../playback/playback_controller.dart';

class ArtistDetailScreen extends ConsumerWidget {
  final String artist;
  const ArtistDetailScreen({super.key, required this.artist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(artistTracksProvider(artist));
    return Scaffold(
      appBar: AppBar(title: Text(artist.isEmpty ? 'Unknown Artist' : artist)),
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
