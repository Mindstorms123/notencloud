import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/musician_profile.dart';
import '../../models/song.dart';
import '../../services/annotation_service.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_matcher.dart';
import '../widgets/voice_selector_sheet.dart';
import 'score_viewer_screen.dart';

class RepertoireScreen extends StatefulWidget {
  final StorageService storageService;
  final AnnotationService annotationService;
  final NextcloudService? nextcloudService;
  final MusicianProfile profile;

  const RepertoireScreen({
    super.key,
    required this.storageService,
    required this.annotationService,
    this.nextcloudService,
    required this.profile,
  });

  @override
  State<RepertoireScreen> createState() => _RepertoireScreenState();
}

class _RepertoireScreenState extends State<RepertoireScreen> {
  List<Song> _allSongs = [];
  List<Song> _filteredSongs = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isSyncing = false;
  String? _syncMessage;
  String _selectedCategory = 'Alle';
  bool _onlyMyVoice = false;

  @override
  void initState() {
    super.initState();
    _loadLocalSongs();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadLocalSongs() {
    final cached = widget.storageService.getCachedSongs();
    setState(() {
      _allSongs = cached;
      _onSearchChanged();
    });
  }

  List<String> get _categories {
    final cats = _allSongs.map((s) => s.category).where((c) => c.isNotEmpty).toSet().toList();
    cats.sort();
    return ['Alle', ...cats];
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredSongs = _allSongs.where((song) {
        final matchesCat = _selectedCategory == 'Alle' || song.category == _selectedCategory;
        if (!matchesCat) return false;

        if (_onlyMyVoice) {
          final best = VoiceMatcher.findBestMatch(song.parts, widget.profile);
          if (best == null) return false;
        }

        if (query.isEmpty) return true;
        return song.title.toLowerCase().contains(query) ||
            song.folderName.toLowerCase().contains(query) ||
            song.composer.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _syncWithCloud() async {
    if (widget.nextcloudService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Nextcloud-Verbindung konfiguriert.')),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncMessage = 'Scanne Notenarchiv...';
    });

    try {
      final remoteSongs = await widget.nextcloudService!.scanLibrary(
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _syncMessage = 'Lade Stücke: $current / $total...';
            });
          }
        },
      );
      await widget.storageService.saveCachedSongs(remoteSongs);

      setState(() {
        _allSongs = remoteSongs;
        _onSearchChanged();
        _isSyncing = false;
        _syncMessage = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${remoteSongs.length} Stücke erfolgreich synchronisiert!')),
        );
      }
    } catch (e) {
      setState(() {
        _isSyncing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Synchronisationsfehler: $e'),
          ),
        );
      }
    }
  }

  Future<void> _downloadAllForOffline() async {
    if (widget.nextcloudService == null) return;

    int total = _allSongs.length;
    int current = 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Bühnen-Download'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: total > 0 ? current / total : 0),
              const SizedBox(height: 16),
              Text('$current von $total Stücken heruntergeladen...'),
            ],
          ),
        ),
      ),
    );

    for (final song in _allSongs) {
      final bestMatch = VoiceMatcher.findBestMatch(song.parts, widget.profile);
      if (bestMatch != null) {
        try {
          final localPath = await widget.storageService.getLocalPdfPath(
            song.id,
            bestMatch.fileName,
          );
          if (!await File(localPath).exists()) {
            await widget.nextcloudService!.downloadPart(bestMatch, localPath);
          }
        } catch (_) {}
      }
      current++;
    }

    if (mounted) {
      Navigator.pop(context); // Close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alle Stimmen für Offline-Betrieb heruntergeladen!')),
      );
    }
  }

  void _openSong(Song song) {
    if (song.parts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Stimmen für dieses Stück verfügbar.')),
      );
      return;
    }

    final bestMatch = VoiceMatcher.findBestMatch(song.parts, widget.profile);
    if (bestMatch == null) {
      // Open voice selector sheet so musician can pick any other part or score
      showModalBottomSheet(
        context: context,
        builder: (ctx) => VoiceSelectorSheet(
          song: song,
          currentPart: song.parts.first,
          profile: widget.profile,
          onSelectPart: (part) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => ScoreViewerScreen(
                  song: song,
                  initialPart: part,
                  profile: widget.profile,
                  storageService: widget.storageService,
                  annotationService: widget.annotationService,
                  nextcloudService: widget.nextcloudService,
                ),
              ),
            );
          },
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Noten & Repertoire', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: 'Alle Stimmen für Bühne vorladen',
            onPressed: _downloadAllForOffline,
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Mit Nextcloud synchronisieren',
            onPressed: _isSyncing ? null : _syncWithCloud,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Stück suchen...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),

          // Active Profile Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Theme.of(context).primaryColor.withOpacity(0.08),
            child: Row(
              children: [
                Icon(Icons.person, size: 18, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.profile.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                FilterChip(
                  label: const Text('Nur meine', style: TextStyle(fontSize: 11)),
                  selected: _onlyMyVoice,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (val) {
                    setState(() {
                      _onlyMyVoice = val;
                      _onSearchChanged();
                    });
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  '${_filteredSongs.length}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Live Sync Progress Bar
          if (_isSyncing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.amber.shade50,
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _syncMessage ?? 'Synchronisiere...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
            ),

          // Category Filter Chips
          if (_categories.length > 2)
            SizedBox(
              height: 42,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = cat == _selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat, style: const TextStyle(fontSize: 12)),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedCategory = cat;
                            _onSearchChanged();
                          });
                        }
                      },
                    ),
                  );
                },
              ),
            ),

          // Songs List
          Expanded(
            child: _filteredSongs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.library_music_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          _allSongs.isEmpty
                              ? 'Noch keine Noten synchronisiert'
                              : 'Keine Stücke gefunden',
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),
                        if (_allSongs.isEmpty)
                          ElevatedButton.icon(
                            onPressed: _syncWithCloud,
                            icon: const Icon(Icons.cloud_download),
                            label: const Text('Jetzt aus Nextcloud laden'),
                          ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _syncWithCloud,
                    child: ListView.separated(
                      itemCount: _filteredSongs.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final song = _filteredSongs[index];
                        final bestMatch =
                            VoiceMatcher.findBestMatch(song.parts, widget.profile);

                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.12),
                            foregroundColor: Theme.of(context).primaryColor,
                            child: const Icon(Icons.music_note),
                          ),
                          title: Text(
                            song.title,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (bestMatch != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: Text(
                                      bestMatch.fileName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade800,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Keine ${widget.profile.instrument}-Stimme',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                if (song.category.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.blue.shade200),
                                    ),
                                    child: Text(
                                      song.category,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blue.shade800,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                Text(
                                  '${song.parts.length} Stimmen',
                                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () => _openSong(song),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
