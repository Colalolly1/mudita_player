import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/library_providers.dart';
import '../../../shared/widgets/alphabet_scrollbar.dart';
import '../artist_detail_screen.dart';

class ArtistsTab extends ConsumerStatefulWidget {
  const ArtistsTab({super.key});

  @override
  ConsumerState<ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends ConsumerState<ArtistsTab> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artists = ref.watch(artistsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(libraryRepositoryProvider).rescan();
        ref.invalidate(artistsProvider);
        ref.invalidate(allTracksProvider);
      },
      child: artists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ListView(children: [Center(child: Text('Error: $e'))]),
        data: (list) {
          if (list.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 100),
              Center(child: Text('No artists')),
            ]);
          }
          return Stack(
            children: [
              ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.only(right: 22),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (ctx, i) {
                  final a = list[i];
                  return ListTile(
                    title: Text(
                      a.name.isEmpty ? 'Unknown Artist' : a.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      '${a.albumCount} album${a.albumCount == 1 ? '' : 's'} • ${a.trackCount} track${a.trackCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ArtistDetailScreen(artist: a.name),
                      ),
                    ),
                  );
                },
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
                      if (AlphabetScrollBar.letterFor(list[i].name) ==
                          letter) {
                        return i;
                      }
                    }
                    return null;
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
