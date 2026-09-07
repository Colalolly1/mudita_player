import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_controller.dart';
import '../../data/cover_fetch/musicbrainz_cover.dart';
import '../../shared/models/album.dart';
import '../../shared/providers/library_providers.dart';

/// Lets the user search iTunes for the right album cover and pick one,
/// instead of trusting the auto-match (which often picks the wrong release).
class CoverSearchScreen extends ConsumerStatefulWidget {
  final AlbumKey albumKey;
  const CoverSearchScreen({super.key, required this.albumKey});

  @override
  ConsumerState<CoverSearchScreen> createState() => _CoverSearchScreenState();
}

class _CoverSearchScreenState extends ConsumerState<CoverSearchScreen> {
  late final TextEditingController _ctrl;
  List<CoverCandidate> _results = [];
  bool _loading = false;
  bool _applying = false;
  String? _errorMsg;

  GridDensity get _density {
    final s = ref
        .read(sharedPreferencesProvider)
        .getString(PrefsKeys.albumsViewDensity);
    return GridDensity.values.firstWhere(
      (d) => d.name == s,
      orElse: () => GridDensity.roomy,
    );
  }

  Future<void> _cycleDensity() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final next = _density == GridDensity.roomy
        ? GridDensity.compact
        : GridDensity.roomy;
    await prefs.setString(PrefsKeys.albumsViewDensity, next.name);
    setState(() {});
  }

  IconData _iconForDensity(GridDensity d) =>
      d == GridDensity.compact ? Icons.grid_view : Icons.apps;

  @override
  void initState() {
    super.initState();
    final initial = [
      widget.albumKey.album,
      widget.albumKey.albumArtist,
    ].where((s) => s.isNotEmpty).join(' ');
    _ctrl = TextEditingController(text: initial);
    _runSearch();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final term = _ctrl.text.trim();
    if (term.isEmpty) {
      setState(() {
        _results = [];
        _errorMsg = 'Type something to search';
      });
      return;
    }
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final r = await ref
          .read(musicBrainzCoverProvider)
          .searchCoverCandidates(term, limitPerSource: 12);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
        _errorMsg = r.isEmpty ? 'No matches on iTunes' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Search failed: $e';
      });
    }
  }

  Future<void> _apply(CoverCandidate c) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _applying = true);
    final uri = await ref
        .read(musicBrainzCoverProvider)
        .applyCandidate(widget.albumKey, c);
    if (!mounted) return;
    setState(() => _applying = false);
    if (uri != null) {
      ref.invalidate(albumTracksProvider(widget.albumKey));
      ref.invalidate(albumsProvider);
      ref.invalidate(allTracksProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Cover applied')));
      Navigator.of(context).pop();
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to download — try another')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find cover art'),
        actions: [
          IconButton(
            tooltip: 'Toggle layout',
            icon: Icon(_iconForDensity(_density)),
            onPressed: _cycleDensity,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                hintText: 'Album + artist',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : _runSearch,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          if (_errorMsg != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _errorMsg!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          Expanded(
            child: Builder(builder: (_) {
              final compact = _density == GridDensity.compact;
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: compact ? 110 : 180,
                  mainAxisSpacing: compact ? 8 : 12,
                  crossAxisSpacing: compact ? 8 : 12,
                  childAspectRatio: compact ? 1.0 : 0.72,
                ),
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final c = _results[i];
                  return _CandidateCard(
                    candidate: c,
                    showLabels: !compact,
                    onTap: _applying ? null : () => _apply(c),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final CoverCandidate candidate;
  final VoidCallback? onTap;
  final bool showLabels;
  const _CandidateCard({
    required this.candidate,
    required this.onTap,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    candidate.thumbUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: scheme.surfaceContainerHigh,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      candidate.source,
                      style: const TextStyle(
                        fontSize: 8,
                        letterSpacing: 0.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showLabels) ...[
            const SizedBox(height: 6),
            Text(
              candidate.albumName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              [
                candidate.artistName,
                if (candidate.releaseYear != null) '${candidate.releaseYear}',
              ].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
