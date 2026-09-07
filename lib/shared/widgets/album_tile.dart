import 'package:flutter/material.dart';

import '../models/album.dart';
import 'cover_art.dart';

class AlbumTile extends StatelessWidget {
  final AlbumSummary album;
  final VoidCallback? onTap;
  final bool showLabels;

  const AlbumTile({
    super.key,
    required this.album,
    this.onTap,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: CoverArt(
                artUri: album.artUri,
                size: double.infinity,
                radius: 4,
              ),
            ),
            if (showLabels) ...[
              const SizedBox(height: 8),
              Text(
                album.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                album.albumArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
