import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/musician_profile.dart';
import '../../models/setlist.dart';
import '../../models/song.dart';
import '../../services/annotation_service.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_matcher.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_selector_sheet.dart';
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

  void _onReorderItem(int oldIndex, int newIndex) {
    setState(() {
      final items = List<SetlistItem>.from(_setlist.items);
      final item = items.removeAt(oldIndex);
      items.insert(newIndex, item);

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
    if (widget.nextcloudService != null) {
      widget.nextcloudService!.uploadSetlist(_setlist).then((success) {
        if (success && !_setlist.isSyncedWithCloud && mounted) {
          setState(() {
            _setlist = _setlist.copyWith(isSyncedWithCloud: true);
          });
          widget.storageService.upsertSetlist(_setlist);
        }
      }).catchError((_) {});
    }
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
      final success = await widget.nextcloudService!.uploadSetlist(_setlist);
      if (success) {
        setState(() {
          _setlist = _setlist.copyWith(isSyncedWithCloud: true);
        });
        await _saveLocally();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.emerald,
              content: Text('Setlist erfolgreich auf Nextcloud synchronisiert!'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.amber,
              content: Text(
                  'Upload fehlgeschlagen. Bitte Verbindung und Nextcloud-Speicher prüfen.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppTheme.rose, content: Text('Fehler: $e')),
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

  void _showAddSongSheet() {
    final allSongs = widget.storageService.getCachedSongs();
    String query = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = query.isEmpty
              ? allSongs
              : allSongs.where((s) => s.title.toLowerCase().contains(query)).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.library_music_rounded, color: AppTheme.primaryLight),
                        const SizedBox(width: 10),
                        const Text(
                          'Stück zur Setlist hinzufügen',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Stück suchen...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (val) {
                        setSheetState(() {
                          query = val.trim().toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'Keine passenden Stücke im Archiv gefunden',
                                style: TextStyle(color: AppTheme.darkTextMuted),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: filtered.length,
                              separatorBuilder: (c, i) => const Divider(color: AppTheme.darkBorder),
                              itemBuilder: (context, index) {
                                final song = filtered[index];
                                final bestMatch =
                                    VoiceMatcher.findBestMatch(song.parts, widget.profile);

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  leading: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: bestMatch != null
                                          ? AppTheme.emerald.withValues(alpha: 0.15)
                                          : AppTheme.darkCard,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.music_note_rounded,
                                        color: bestMatch != null
                                            ? AppTheme.emerald
                                            : AppTheme.darkTextMuted,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    song.title,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                  ),
                                  subtitle: Text(
                                    bestMatch != null
                                        ? '✓ ${VoiceMatcher.getPartDisplayLabel(bestMatch)}'
                                        : '${song.parts.length} Stimmen vorhanden',
                                    style: TextStyle(
                                      color: bestMatch != null
                                          ? AppTheme.emerald
                                          : AppTheme.darkTextMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.add_circle_outline_rounded,
                                        color: AppTheme.primaryLight),
                                    onPressed: () {
                                      _addSongToSetlist(song);
                                      Navigator.pop(ctx);
                                    },
                                  ),
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
              );
            },
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
      songTitle: 'PAUSE',
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

    final bestMatch = VoiceMatcher.findBestMatchForSong(song, widget.profile);
    if (bestMatch == null) {
      if (song.parts.isNotEmpty) {
        showModalBottomSheet(
          context: context,
          backgroundColor: AppTheme.darkCard,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => VoiceSelectorSheet(
            song: song,
            profile: widget.profile,
            currentPart: song.parts.first,
            onSelectPart: (selectedPart) {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => ScoreViewerScreen(
                    song: song,
                    initialPart: selectedPart,
                    profile: widget.profile,
                    storageService: widget.storageService,
                    annotationService: widget.annotationService,
                    nextcloudService: widget.nextcloudService,
                    currentSetlist: _setlist,
                    setlistIndex: itemIndex,
                  ),
                ),
              );
            },
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.amber,
          content: Text('Keine Notendateien für "${item.songTitle}" vorhanden.'),
        ),
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
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: AppTheme.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Notiz für "${item.songTitle}"',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'z.B. Ohne Wiederholung, Attacca, Takt 32 Einsatz...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen', style: TextStyle(color: AppTheme.darkTextMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
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
    final playableCount = _setlist.items.where((i) => !i.isIntermission).length;
    final allSongs = widget.storageService.getCachedSongs();

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_setlist.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            Row(
              children: [
                Text(
                  '$playableCount Stücke • ${widget.profile.displayName}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.darkTextSecondary),
                ),
                if (_setlist.isSyncedWithCloud) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.cloud_done_rounded, size: 14, color: AppTheme.emerald),
                ],
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isSavingToCloud
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            tooltip: 'Auf Nextcloud veröffentlichen',
            onPressed: _isSavingToCloud ? null : _syncToNextcloud,
          ),
        ],
      ),
      body: Column(
        children: [
          // Stage Mode Hero Banner
          if (_setlist.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  final firstSongIndex = _setlist.items.indexWhere((item) => !item.isIntermission);
                  if (firstSongIndex >= 0) {
                    _openSongAt(firstSongIndex);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4338CA), Color(0xFF6366F1), Color(0xFF818CF8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.play_circle_fill_rounded, size: 36, color: Colors.white),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bühnenmodus starten',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: -0.2,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Stücke nacheinander durchblättern',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
                    ],
                  ),
                ),
              ),
            ),

          // Setlist Items list
          Expanded(
            child: _setlist.items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppTheme.darkCard,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.darkBorder),
                            ),
                            child: const Center(
                              child: Icon(Icons.playlist_add_rounded,
                                  size: 36, color: AppTheme.darkTextMuted),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Diese Setlist ist noch leer',
                            style: TextStyle(
                              color: AppTheme.darkTextPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Füge Stücke aus dem Repertoire-Archiv hinzu oder plane Pausen ein.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.darkTextMuted, fontSize: 14),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _showAddSongSheet,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Stück hinzufügen', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _setlist.items.length,
                    onReorderItem: _onReorderItem,
                    itemBuilder: (context, index) {
                      final item = _setlist.items[index];

                      if (item.isIntermission) {
                        return Container(
                          key: ValueKey(item.id),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.amber.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.coffee_rounded, color: AppTheme.amber, size: 18),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'PAUSE / DURCHATMEN',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
                                  color: AppTheme.amber,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppTheme.darkTextMuted),
                                onPressed: () {
                                  setState(() {
                                    final items = List<SetlistItem>.from(_setlist.items)..removeAt(index);
                                    _setlist = _setlist.copyWith(items: items);
                                  });
                                  _saveLocally();
                                },
                              ),
                              const Icon(Icons.drag_indicator_rounded, color: AppTheme.darkTextMuted),
                            ],
                          ),
                        );
                      }

                      // Try to match song
                      final song = allSongs.firstWhere(
                        (s) => s.id == item.songId || s.folderName == item.songFolderName,
                        orElse: () => Song(id: item.songId, title: item.songTitle, folderName: item.songFolderName, remoteFolderPath: ''),
                      );
                      final match = VoiceMatcher.findDetailedMatchForSong(song, widget.profile);
                      final bestMatch = match?.part;
                      final isFallback = match?.isFallback ?? false;

                      return Dismissible(
                        key: ValueKey(item.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.rose.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete_rounded, color: Colors.white),
                        ),
                        onDismissed: (direction) {
                          setState(() {
                            final items = List<SetlistItem>.from(_setlist.items)..removeAt(index);
                            _setlist = _setlist.copyWith(items: items);
                          });
                          _saveLocally();
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.darkCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.darkBorder),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _openSongAt(index),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    // Order Badge
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: AppTheme.darkSurface,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppTheme.darkBorder),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.darkTextSecondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Title & Voice details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.songTitle,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: AppTheme.darkTextPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              if (bestMatch != null)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isFallback
                                                        ? AppTheme.amber.withValues(alpha: 0.15)
                                                        : AppTheme.emerald.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: isFallback
                                                          ? AppTheme.amber.withValues(alpha: 0.3)
                                                          : AppTheme.emerald.withValues(alpha: 0.25),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        isFallback ? Icons.info_outline_rounded : Icons.check_circle_rounded,
                                                        size: 13,
                                                        color: isFallback ? AppTheme.amber : AppTheme.emerald,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        isFallback
                                                            ? (widget.profile.instrument == 'Percussion' &&
                                                                    widget.profile.percussionInstrument.isNotEmpty &&
                                                                    widget.profile.percussionInstrument != 'Alle'
                                                                ? 'Keine ${widget.profile.percussionInstrument} • Ersatz: ${VoiceMatcher.getPartDisplayLabel(bestMatch)}'
                                                                : (widget.profile.voiceNumber > 0
                                                                    ? 'Keine ${widget.profile.voiceNumber}. St. • Ersatz: ${VoiceMatcher.getPartDisplayLabel(bestMatch)}'
                                                                    : 'Ersatz: ${VoiceMatcher.getPartDisplayLabel(bestMatch)}'))
                                                            : (song.isDocumentOrList
                                                                ? 'Dokument / Liste (alle Stimmen)'
                                                                : VoiceMatcher.getPartDisplayLabel(bestMatch)),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: isFallback
                                                              ? AppTheme.amber
                                                              : AppTheme.emerald,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              else
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withValues(alpha: 0.06),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: Colors.white12),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.music_off_rounded, size: 13, color: AppTheme.darkTextMuted),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Keine ${widget.profile.displayName}',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppTheme.darkTextMuted,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (item.notes.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.amber.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.sticky_note_2_rounded,
                                                          size: 11, color: AppTheme.amber),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        item.notes,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppTheme.amber,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Action buttons
                                    IconButton(
                                      icon: Icon(
                                        item.notes.isEmpty
                                            ? Icons.note_add_outlined
                                            : Icons.edit_note_rounded,
                                        size: 20,
                                        color: item.notes.isNotEmpty ? AppTheme.amber : AppTheme.darkTextMuted,
                                      ),
                                      tooltip: 'Notiz',
                                      onPressed: () => _editItemNotes(item),
                                    ),
                                    const Icon(Icons.drag_indicator_rounded, color: AppTheme.darkTextMuted),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: const BoxDecoration(
          color: AppTheme.darkSurface,
          border: Border(top: BorderSide(color: AppTheme.darkBorder)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _showAddSongSheet,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Stück hinzufügen', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.amber,
                  side: const BorderSide(color: AppTheme.amber),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _addIntermission,
                icon: const Icon(Icons.coffee_rounded, size: 18),
                label: const Text('Pause', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
