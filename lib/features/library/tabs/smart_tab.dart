import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../smart_playlist_screen.dart';

enum SmartKind {
  recentlyAdded,
  mostPlayed,
  neverPlayed,
  forgotten,
  favorites,
  highlyRated,
  history,
  dailyMix,
  duplicates,
  missing,
  oftenSkipped,
}

class SmartTab extends ConsumerWidget {
  const SmartTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = [
      _Entry(SmartKind.dailyMix, 'Daily Mix', Icons.auto_awesome,
          'A fresh shuffle each day, weighted by what you love'),
      _Entry(SmartKind.history, 'History', Icons.history,
          'Recently played, newest first'),
      _Entry(SmartKind.recentlyAdded, 'Recently Added', Icons.fiber_new_outlined,
          'Added in the last 30 days'),
      _Entry(SmartKind.mostPlayed, 'Most Played', Icons.trending_up,
          'Top 50 by play count'),
      _Entry(SmartKind.favorites, 'Favorites', Icons.favorite_border,
          'Tracks you marked as favorite'),
      _Entry(SmartKind.highlyRated, 'Highly Rated', Icons.star_outline,
          '4 stars or higher'),
      _Entry(SmartKind.neverPlayed, 'Never Played', Icons.radio_button_unchecked,
          'Never played in this app'),
      _Entry(SmartKind.forgotten, 'Forgotten', Icons.history_toggle_off,
          'Played, but not in 6 months'),
      _Entry(SmartKind.oftenSkipped, 'Often Skipped', Icons.fast_forward,
          'You keep skipping these'),
      _Entry(SmartKind.duplicates, 'Duplicates', Icons.content_copy,
          'Same title + artist appearing multiple times'),
      _Entry(SmartKind.missing, 'Missing files', Icons.report_gmailerrorred_outlined,
          "Tracks in DB whose file is gone"),
    ];
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (ctx, i) {
        final e = entries[i];
        return ListTile(
          leading: Icon(e.icon),
          title: Text(e.title),
          subtitle: Text(e.subtitle),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SmartPlaylistScreen(kind: e.kind, title: e.title),
            ),
          ),
        );
      },
    );
  }
}

class _Entry {
  final SmartKind kind;
  final String title;
  final IconData icon;
  final String subtitle;
  const _Entry(this.kind, this.title, this.icon, this.subtitle);
}
