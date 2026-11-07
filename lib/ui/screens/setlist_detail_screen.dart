import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/musician_profile.dart';
import '../../models/setlist.dart';
import '../../models/song.dart';
import '../../services/annotation_service.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_matcher.dart';
import 'score_viewer_screen.dart';

class SetlistDetailScreen extends StatefulWidget {
  final Setlist setlist;
  final StorageService storageService;
  final AnnotationService annotationService;
  final NextcloudService? nextcloudService;
  final MusicianProfile profile;
  final Function(Setlist) onSetlistUpdated;

  const SetlistDetailScreen({
    super.key,
    required this.setlist,
    required this.storageService,
    required this.annotationService,
    this.nextcloudService,
    required this.profile,
    required this.onSetlistUpdated,
  });

  @override
  State<SetlistDetailScreen> createState() => _SetlistDetailScreenState();
}

class _SetlistDetailScreenState extends State<SetlistDetailScreen> {
  late Setlist _setlist;
  bool _isSavingToCloud = false;

  @override
  void initState() {
    super.initState();
    _setlist = widget.setlist;
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final items = List<SetlistItem>.from(_setlist.items);
      final item = items.removeAt(oldIndex);
      items.insert(newIndex, item);

      // Re-index orders
      final reindexed = items.asMap().entries.map((e) {
        return e.value.copyWith(order: e.key + 1);
      }).toList();

      _setlist = _setlist.copyWith(
        items: reindexed,
        updatedAt: DateTime.now(),
      );
    });
    _saveLocally();
  }

  Future<void> _saveLocally() async {
    await widget.storageService.upsertSetlist(_setlist);
    widget.onSetlistUpdated(_setlist);
  }

  Future<void> _syncToNextcloud() async {
    if (widget.nextcloudService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Nextcloud verbunden.')),
      );
      return;
    }

    setState(() {
      _isSavingToCloud = true;
    });

    try {
      final hasPerm = await widget.nextcloudService!.hasSetlistWritePermission();
      if (!hasPerm) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text(
                  'Keine Schreibberechtigung auf Nextcloud/_Setlisten. Setlist bleibt lokal gespeichert.'),
            ),
          );
        }
        setState(() {
          _isSavingToCloud = false;
        });
        return;
      }

      final success = await widget.nextcloudService!.uploadSetlist(_setlist);
      if (success) {
        setState(() {
          _setlist = _setlist.copyWith(isSyncedWithCloud: true);
        });
        await _saveLocally();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('Setlist erfolgreich auf Nextcloud veröffentlicht!'),
            ),
          );
        }
      } else {
        throw Exception('Upload fehlgeschlagen');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingToCloud = false;
        });
      }
    }
  }

  void _showAddSongDialog() {
    final allSongs = widget.storageService.getCachedSongs();
    String query = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = query.isEmpty
              ? allSongs
              : allSongs.where((s) => s.title.toLowerCase().contains(query)).toList();

          return AlertDialog(
            title: const Text('Stück hinzufügen'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Stück suchen...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (val) {
                      setDialogState(() {
                        query = val.trim().toLowerCase();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final song = filtered[index];
                        return ListTile(
                          title: Text(song.title),
                          subtitle: Text('${song.parts.length} Stimmen'),
                          trailing: const Icon(Icons.add),
                          onTap: () {
                            _addSongToSetlist(song);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Schließen'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addSongToSetlist(Song song) {
    final newItem = SetlistItem(
      id: const Uuid().v4(),
      songId: song.id,
      songTitle: song.title,
      songFolderName: song.folderName,
      order: _setlist.items.length + 1,
    );

    setState(() {
      _setlist = _setlist.copyWith(
        items: List.from(_setlist.items)..add(newItem),
        updatedAt: DateTime.now(),
      );
    });
    _saveLocally();
  }

  void _addIntermission() {
    final pauseItem = SetlistItem(
      id: const Uuid().v4(),
      songId: 'pause',
      songTitle: '--- PAUSE ---',
      songFolderName: '',
      order: _setlist.items.length + 1,
      isIntermission: true,
    );

    setState(() {
      _setlist = _setlist.copyWith(
        items: List.from(_setlist.items)..add(pauseItem),
        updatedAt: DateTime.now(),
      );
    });
    _saveLocally();
  }

  void _openSongAt(int itemIndex) {
    final item = _setlist.items[itemIndex];
    if (item.isIntermission) return;

    final allSongs = widget.storageService.getCachedSongs();
    final song = allSongs.firstWhere(
      (s) => s.id == item.songId || s.folderName == item.songFolderName,
      orElse: () => Song(
        id: item.songId,
        title: item.songTitle,
        folderName: item.songFolderName,
        remoteFolderPath: '',
      ),
    );

    final bestMatch = VoiceMatcher.findBestMatch(song.parts, widget.profile);
    if (bestMatch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine passende Stimme für dieses Stück gefunden.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ScoreViewerScreen(
          song: song,
          initialPart: bestMatch,
          profile: widget.profile,
          storageService: widget.storageService,
          annotationService: widget.annotationService,
          nextcloudService: widget.nextcloudService,
          currentSetlist: _setlist,
          setlistIndex: itemIndex,
        ),
      ),
    );
  }

  void _editItemNotes(SetlistItem item) {
    final controller = TextEditingController(text: item.notes);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Notiz für "${item.songTitle}"'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'z.B. Ohne Wiederholung, Attacca...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              final updated = _setlist.items.map((i) {
                return i.id == item.id ? i.copyWith(notes: controller.text.trim()) : i;
              }).toList();
              setState(() {
                _setlist = _setlist.copyWith(items: updated);
              });
              _saveLocally();
              Navigator.pop(ctx);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_setlist.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              '${_setlist.items.length} Einträge • ${widget.profile.displayName}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isSavingToCloud
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            tooltip: 'Auf Nextcloud veröffentlichen / synchronisieren',
            onPressed: _isSavingToCloud ? null : _syncToNextcloud,
          ),
        ],
      ),
      body: Column(
        children: [
          // Action banner: Start Concert Mode
          if (_setlist.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.play_circle_fill),
                label: const Text('Auftritt / Probe starten (Bühnenmodus)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  // Find first playable song
                  final firstSongIndex =
                      _setlist.items.indexWhere((item) => !item.isIntermission);
                  if (firstSongIndex >= 0) {
                    _openSongAt(firstSongIndex);
                  }
                },
              ),
            ),

          // Reorderable list of songs
          Expanded(
            child: _setlist.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.playlist_add, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'Diese Setlist ist noch leer',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _showAddSongDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Stücke hinzufügen'),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    itemCount: _setlist.items.length,
                    onReorder: _onReorder,
                    itemBuilder: (context, index) {
                      final item = _setlist.items[index];

                      if (item.isIntermission) {
                        return Container(
                          key: ValueKey(item.id),
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            border: Border.all(color: Colors.amber.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.coffee, color: Colors.amber),
                              const SizedBox(width: 12),
                              const Text(
                                'PAUSE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.brown,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () {
                                  setState(() {
                                    final items = List<SetlistItem>.from(_setlist.items)
                                      ..removeAt(index);
                                    _setlist = _setlist.copyWith(items: items);
                                  });
                                  _saveLocally();
                                },
                              ),
                              const Icon(Icons.drag_handle, color: Colors.grey),
                            ],
                          ),
                        );
                      }

                      return Dismissible(
                        key: ValueKey(item.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) {
                          setState(() {
                            final items = List<SetlistItem>.from(_setlist.items)..removeAt(index);
                            _setlist = _setlist.copyWith(items: items);
                          });
                          _saveLocally();
                        },
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.grey.shade200,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            item.songTitle,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: item.notes.isNotEmpty
                              ? Text(
                                  item.notes,
                                  style: const TextStyle(color: Colors.deepOrange, fontSize: 12),
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.note_add_outlined, size: 20),
                                tooltip: 'Notiz hinzufügen',
                                onPressed: () => _editItemNotes(item),
                              ),
                              const Icon(Icons.drag_handle, color: Colors.grey),
                            ],
                          ),
                          onTap: () => _openSongAt(index),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: _showAddSongDialog,
              icon: const Icon(Icons.add),
              label: const Text('Stück hinzufügen'),
            ),
            TextButton.icon(
              onPressed: _addIntermission,
              icon: const Icon(Icons.coffee),
              label: const Text('Pause einfügen'),
            ),
          ],
        ),
      ),
    );
  }
}
