import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/library_providers.dart';
import '../folder_detail_screen.dart';

class FoldersTab extends ConsumerWidget {
  const FoldersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider);
    return folders.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) return const Center(child: Text('No folders'));
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (ctx, i) {
            final f = list[i];
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(f.displayPath),
              subtitle: Text('${f.trackCount} track${f.trackCount == 1 ? '' : 's'}'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FolderDetailScreen(folderUri: f.uri, displayPath: f.displayPath),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
