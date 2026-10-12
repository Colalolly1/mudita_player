import 'package:audiotags/audiotags.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../shared/providers/library_providers.dart';

class TagEditorScreen extends ConsumerStatefulWidget {
  final List<Track> tracks;
  const TagEditorScreen({super.key, required this.tracks});

  @override
  ConsumerState<TagEditorScreen> createState() => _TagEditorScreenState();
}

class _TagEditorScreenState extends ConsumerState<TagEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  late final TextEditingController _albumArtist;
  late final TextEditingController _year;
  late final TextEditingController _genre;
  late final TextEditingController _track;
  late final TextEditingController _disc;
  bool _saving = false;

  bool get _isBatch => widget.tracks.length > 1;

  @override
  void initState() {
    super.initState();
    final t = widget.tracks.first;
    final all = widget.tracks;

    String shared(String Function(Track) sel) {
      final v = sel(t);
      return all.every((x) => sel(x) == v) ? v : '';
    }

    String sharedInt(int Function(Track) sel) {
      final v = sel(t);
      return all.every((x) => sel(x) == v) && v != 0 ? v.toString() : '';
    }

    _title = TextEditingController(text: _isBatch ? '' : t.title);
    _artist = TextEditingController(text: shared((x) => x.artist));
    _album = TextEditingController(text: shared((x) => x.album));
    _albumArtist = TextEditingController(text: shared((x) => x.albumArtist));
    _year = TextEditingController(text: sharedInt((x) => x.year));
    _genre = TextEditingController(text: shared((x) => x.genre));
    _track = TextEditingController(
        text: _isBatch ? '' : (t.trackNumber == 0 ? '' : t.trackNumber.toString()));
    _disc = TextEditingController(
        text: _isBatch ? '' : (t.discNumber == 0 ? '' : t.discNumber.toString()));
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _albumArtist.dispose();
    _year.dispose();
    _genre.dispose();
    _track.dispose();
    _disc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    int updated = 0;
    int failed = 0;

    for (final t in widget.tracks) {
      try {
        Tag? existing;
        try {
          existing = await AudioTags.read(t.uri);
        } catch (_) {}

        final newTag = Tag(
          title: _isBatch
              ? (existing?.title ?? t.title)
              : (_title.text.isEmpty ? t.title : _title.text),
          trackArtist: _artist.text.isEmpty
              ? (existing?.trackArtist ?? t.artist)
              : _artist.text,
          album: _album.text.isEmpty ? (existing?.album ?? t.album) : _album.text,
          albumArtist: _albumArtist.text.isEmpty
              ? (existing?.albumArtist ?? t.albumArtist)
              : _albumArtist.text,
          year: _year.text.isEmpty
              ? (existing?.year ?? (t.year == 0 ? null : t.year))
              : int.tryParse(_year.text),
          genre: _genre.text.isEmpty ? (existing?.genre ?? t.genre) : _genre.text,
          trackNumber: _isBatch
              ? existing?.trackNumber
              : (_track.text.isEmpty ? null : int.tryParse(_track.text)),
          discNumber: _isBatch
              ? existing?.discNumber
              : (_disc.text.isEmpty ? null : int.tryParse(_disc.text)),
          pictures: existing?.pictures ?? const [],
          duration: existing?.duration,
          trackTotal: existing?.trackTotal,
          discTotal: existing?.discTotal,
        );

        try {
          await AudioTags.write(t.uri, newTag);
        } catch (_) {
          failed++;
          continue;
        }

        await db.upsertTrack(
          TracksCompanion(
            id: drift.Value(t.id),
            uri: drift.Value(t.uri),
            filename: drift.Value(t.filename),
            folderUri: drift.Value(t.folderUri),
            folderPath: drift.Value(t.folderPath),
            title: drift.Value(newTag.title ?? t.title),
            artist: drift.Value(newTag.trackArtist ?? ''),
            albumArtist: drift.Value(newTag.albumArtist ?? ''),
            album: drift.Value(newTag.album ?? ''),
            genre: drift.Value(newTag.genre ?? ''),
            year: drift.Value(newTag.year ?? 0),
            trackNumber: drift.Value(newTag.trackNumber ?? 0),
            discNumber: drift.Value(newTag.discNumber ?? 0),
          ),
        );
        updated++;
      } catch (_) {
        failed++;
      }
    }

    ref.invalidate(allTracksProvider);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated $updated track${updated == 1 ? '' : 's'}${failed > 0 ? ", $failed couldn't be written. Allow all files access in Settings." : ''}',
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _isBatch ? 'Edit ${widget.tracks.length} tracks' : 'Edit tags'),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_isBatch) _Field(label: 'Title', controller: _title),
          _Field(
            label: 'Artist',
            controller: _artist,
            hint: _isBatch ? '(mixed)' : null,
          ),
          _Field(
            label: 'Album',
            controller: _album,
            hint: _isBatch ? '(mixed)' : null,
          ),
          _Field(
            label: 'Album Artist',
            controller: _albumArtist,
            hint: _isBatch ? '(mixed)' : null,
          ),
          _Field(
            label: 'Year',
            controller: _year,
            keyboardType: TextInputType.number,
            hint: _isBatch ? '(mixed)' : null,
          ),
          _Field(
            label: 'Genre',
            controller: _genre,
            hint: _isBatch ? '(mixed)' : null,
          ),
          if (!_isBatch) ...[
            _Field(
              label: 'Track #',
              controller: _track,
              keyboardType: TextInputType.number,
            ),
            _Field(
              label: 'Disc #',
              controller: _disc,
              keyboardType: TextInputType.number,
            ),
          ],
          if (_isBatch)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Empty fields keep existing values per-track.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;

  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}
