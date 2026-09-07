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

class LibraryShell extends ConsumerStatefulWidget {
  const LibraryShell({super.key});

  @override
  ConsumerState<LibraryShell> createState() => _LibraryShellState();
}

class _LibraryShellState extends ConsumerState<LibraryShell>
    with TickerProviderStateMixin {
  late final TabController _tabs;

  static const _tabLabels = ['Songs', 'Albums', 'Artists', 'Folders', 'Playlists', 'Smart'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabLabels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
            tooltip: 'Search',
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/settings'),
            tooltip: 'Settings',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                SongsTab(),
                AlbumsTab(),
                ArtistsTab(),
                FoldersTab(),
                PlaylistsTab(),
                SmartTab(),
              ],
            ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }
}
