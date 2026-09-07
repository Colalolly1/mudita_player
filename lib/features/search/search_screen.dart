import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/database/app_database.dart';
import '../../shared/widgets/track_tile.dart';
import '../../playback/playback_controller.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Track> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: AppConstants.searchDebounceMs), () async {
      if (q.trim().isEmpty) {
        setState(() => _results = []);
        return;
      }
      setState(() => _searching = true);
      final db = ref.read(databaseProvider);
      final res = await db.searchTracks(q.trim());
      if (mounted) setState(() {
        _results = res;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Search title, artist, album',
            border: InputBorder.none,
          ),
        ),
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? Center(
                  child: Text(
                    _controller.text.isEmpty ? 'Type to search' : 'No results',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) => TrackTile(
                    track: _results[i],
                    onTap: () => ref
                        .read(playbackControllerProvider.notifier)
                        .playFromList(_results, i),
                  ),
                ),
    );
  }
}
