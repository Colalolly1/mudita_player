import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'tabs/songs_tab.dart';
import 'tabs/albums_tab.dart';
import 'tabs/artists_tab.dart';
import 'tabs/folders_tab.dart';
import 'tabs/playlists_tab.dart';
import 'tabs/smart_tab.dart';
import '../../shared/widgets/mini_player.dart';

/// The library. Words, not tabs: one line of views above a wall of covers.
/// Folders and Smart playlists live behind the last word, along with
/// Settings, so the line stays short enough to read at a glance.
class LibraryShell extends ConsumerStatefulWidget {
  const LibraryShell({super.key});

  @override
  ConsumerState<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends ConsumerState<LibraryShell> {
  int _view = 0;

  static const _views = ['Albums', 'Artists', 'Songs', 'Playlists'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('Library',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w500)),
                  const Spacer(),
                  _Word('Search', onTap: () => context.push('/search')),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Row(
                children: [
                  for (var i = 0; i < _views.length; i++) ...[
                    _ViewWord(
                      _views[i],
                      selected: _view == i,
                      onTap: () => setState(() => _view = i),
                    ),
                    const SizedBox(width: 18),
                  ],
                  _ViewWord('More', selected: false, onTap: () => _more(context)),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            Expanded(
              child: IndexedStack(
                index: _view,
                children: const [
                  AlbumsTab(),
                  ArtistsTab(),
                  SongsTab(),
                  PlaylistsTab(),
                ],
              ),
            ),
            const MiniPlayer(),
          ],
        ),
      ),
    );
  }

  void _more(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: false,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetWord('Folders', () {
              Navigator.pop(ctx);
              _pushView(context, 'Folders', const FoldersTab());
            }),
            _SheetWord('Smart playlists', () {
              Navigator.pop(ctx);
              _pushView(context, 'Smart playlists', const SmartTab());
            }),
            _SheetWord('Settings', () {
              Navigator.pop(ctx);
              context.push('/settings');
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _pushView(BuildContext context, String title, Widget body) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Column(
            children: [Expanded(child: body), const MiniPlayer()],
          ),
        ),
      ),
    );
  }
}

class _Word extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _Word(this.text, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
    );
  }
}

class _ViewWord extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _ViewWord(this.text, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

class _SheetWord extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _SheetWord(this.text, this.onTap);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
