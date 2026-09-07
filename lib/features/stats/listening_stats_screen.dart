import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../shared/providers/library_providers.dart';

/// Aggregate listening stats: total time, top artists/albums/tracks, recent
/// activity. Computed live from the existing `tracks` table — no separate
/// history table needed yet.
class ListeningStatsScreen extends ConsumerWidget {
  const ListeningStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_statsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Listening stats')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(_statsProvider),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _SummaryCard(stats: s),
              _SectionHeader('This week'),
              _RecentRow(count: s.playedThisWeek, label: 'tracks played'),
              const SizedBox(height: 8),
              _SectionHeader('Top artists'),
              ...s.topArtists.take(10).map((a) => _AggregateTile(item: a)),
              const SizedBox(height: 8),
              _SectionHeader('Top albums'),
              ...s.topAlbums.take(10).map((a) => _AggregateTile(item: a)),
              const SizedBox(height: 8),
              _SectionHeader('Top tracks'),
              ...s.topTracks.take(20).map((t) => _TrackStatTile(track: t)),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Listen time is estimated from play count × track length. '
                  'Skipped plays inflate it slightly.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stats {
  final Duration totalListenTime;
  final LibrarySummary summary;
  final List<TopAggregate> topArtists;
  final List<TopAggregate> topAlbums;
  final List<Track> topTracks;
  final int playedThisWeek;
  const _Stats({
    required this.totalListenTime,
    required this.summary,
    required this.topArtists,
    required this.topAlbums,
    required this.topTracks,
    required this.playedThisWeek,
  });
}

final _statsProvider = FutureProvider<_Stats>((ref) async {
  ref.watch(allTracksProvider);
  final db = ref.watch(databaseProvider);
  final results = await Future.wait([
    db.totalListenTime(),
    db.librarySummary(),
    db.topArtists(limit: 10),
    db.topAlbums(limit: 10),
    db.topTracks(limit: 20),
    db.playedSince(const Duration(days: 7)),
  ]);
  return _Stats(
    totalListenTime: results[0] as Duration,
    summary: results[1] as LibrarySummary,
    topArtists: results[2] as List<TopAggregate>,
    topAlbums: results[3] as List<TopAggregate>,
    topTracks: results[4] as List<Track>,
    playedThisWeek: (results[5] as List<Track>).length,
  );
});

class _SummaryCard extends StatelessWidget {
  final _Stats stats;
  const _SummaryCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDuration(stats.totalListenTime),
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'estimated total listening',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(
                  label: 'Played',
                  value: '${stats.summary.playedTracks}',
                  subtitle: 'of ${stats.summary.totalTracks} tracks',
                ),
                const SizedBox(width: 24),
                _Stat(
                  label: 'Favorites',
                  value: '${stats.summary.favorites}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  const _Stat({required this.label, required this.value, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        if (subtitle != null)
          Text(subtitle!, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final int count;
  final String label;
  const _RecentRow({required this.count, required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('$count',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _AggregateTile extends StatelessWidget {
  final TopAggregate item;
  const _AggregateTile({required this.item});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: item.subtitle == null
          ? null
          : Text(item.subtitle!,
              maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${item.plays} plays',
              style: Theme.of(context).textTheme.bodyMedium),
          Text(_formatDuration(item.listenTime),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TrackStatTile extends StatelessWidget {
  final Track track;
  const _TrackStatTile({required this.track});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [track.artist, track.album].where((s) => s.isNotEmpty).join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${track.playCount}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h >= 24) {
    final days = h ~/ 24;
    final remainH = h % 24;
    return '${days}d ${remainH}h';
  }
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
