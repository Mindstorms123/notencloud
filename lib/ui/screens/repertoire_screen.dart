import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/musician_profile.dart';
import '../../models/song.dart';
import '../../services/annotation_service.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_matcher.dart';
import '../theme/app_theme.dart';
import '../widgets/voice_selector_sheet.dart';
import '../widgets/instrument_filter_sheet.dart';
import 'score_viewer_screen.dart';

class RepertoireScreen extends StatefulWidget {
  final StorageService storageService;
  final AnnotationService annotationService;
  final NextcloudService? nextcloudService;
  final MusicianProfile profile;
  final ValueChanged<MusicianProfile>? onProfileUpdated;

  const RepertoireScreen({
    super.key,
    required this.storageService,
    required this.annotationService,
    this.nextcloudService,
    required this.profile,
    this.onProfileUpdated,
  });

  @override
  State<RepertoireScreen> createState() => _RepertoireScreenState();
}

class _RepertoireScreenState extends State<RepertoireScreen> {
  List<Song> _allSongs = [];
  List<Song> _filteredSongs = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isSyncing = false;
  bool _isBackgroundSyncing = false;
  String? _syncMessage;
  late String _selectedCategory;
  bool _onlyMyVoice = false;
  late MusicianProfile _activeProfile;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.storageService.getLastActiveCategory();
    _activeProfile = widget.profile;
    _loadLocalSongs();
    _searchController.addListener(_onSearchChanged);
    // Silent background delta-sync on launch if Nextcloud is configured
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.nextcloudService != null) {
        _syncWithCloud(isBackground: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant RepertoireScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile != oldWidget.profile) {
      setState(() {
        _activeProfile = widget.profile;
        _onSearchChanged();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadLocalSongs() {
    final cached = widget.storageService.getCachedSongs().where((s) {
      if (s.id == '01_Aktuelle Noten_01_Aktuelle Noten' || s.id == '02_Ältere Noten_02_Ältere Noten') return false;
      if (s.folderName == '01_Aktuelle Noten' || s.folderName == '02_Ältere Noten') return false;
      if ((s.title.toLowerCase() == 'aktuelle noten' || s.title.toLowerCase() == 'ältere noten') && s.parts.length > 50) return false;
      return true;
    }).toList();

    final lastCat = widget.storageService.getLastActiveCategory();
    final availableCats = cached.map((s) => s.category).where((c) => c.isNotEmpty).toSet().toList();
    availableCats.sort();
    final categories = ['Alle', ...availableCats];

    setState(() {
      _allSongs = cached;
      if (categories.contains(lastCat)) {
        _selectedCategory = lastCat;
      } else if (categories.contains('Aktuelle Noten')) {
        _selectedCategory = 'Aktuelle Noten';
      } else {
        _selectedCategory = 'Alle';
      }
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
          final best = VoiceMatcher.findBestMatchForSong(song, _activeProfile);
          if (best == null) return false;
        }

        if (query.isEmpty) return true;
        return song.title.toLowerCase().contains(query) ||
            song.folderName.toLowerCase().contains(query) ||
            song.composer.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _showInstrumentFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InstrumentFilterSheet(
        currentProfile: _activeProfile,
        allSongs: _allSongs,
        onlyMyVoice: _onlyMyVoice,
        onApply: (updatedProfile, onlyMyVoice, savePermanently) async {
          setState(() {
            _activeProfile = updatedProfile;
            _onlyMyVoice = onlyMyVoice;
            _onSearchChanged();
          });
          if (savePermanently) {
            await widget.storageService.saveProfile(updatedProfile);
            widget.onProfileUpdated?.call(updatedProfile);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppTheme.emerald,
                  content: Text('Standard-Profil gespeichert: ${updatedProfile.displayName}'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        },
      ),
    );
  }

  void _setPercussionSubInstrument(String sub) {
    final updated = _activeProfile.copyWith(percussionInstrument: sub);
    setState(() {
      _activeProfile = updated;
      _onSearchChanged();
    });
    widget.storageService.saveProfile(updated);
    widget.onProfileUpdated?.call(updated);
  }

  Widget _buildPercussionChip({
    required String label,
    required IconData icon,
    required String subValue,
    required bool isDark,
  }) {
    final currentSub = _activeProfile.percussionInstrument.isEmpty
        ? 'Alle'
        : _activeProfile.percussionInstrument;
    final isSelected = currentSub.toLowerCase() == subValue.toLowerCase();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _setPercussionSubInstrument(subValue),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryLight
                : (isDark ? AppTheme.darkCard : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryLight
                  : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _syncWithCloud({bool isBackground = false}) async {
    if (widget.nextcloudService == null) {
      if (!isBackground && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Nextcloud-Verbindung konfiguriert.')),
        );
      }
      return;
    }

    if (isBackground) {
      setState(() {
        _isBackgroundSyncing = true;
      });
    } else {
      setState(() {
        _isSyncing = true;
        _syncMessage = 'Prüfe auf Änderungen...';
      });
    }

    try {
      final initialCount = _allSongs.length;
      final remoteSongs = await widget.nextcloudService!.scanLibrary(
        existingCachedSongs: _allSongs,
        onProgress: (current, total) {
          if (mounted && !isBackground) {
            setState(() {
              _syncMessage = 'Aktualisiere geänderte Stücke: $current / $total...';
            });
          }
        },
      );
      await widget.storageService.saveCachedSongs(remoteSongs);

      final diffCount = remoteSongs.length - initialCount;

      if (mounted) {
        setState(() {
          _allSongs = remoteSongs;
          _onSearchChanged();
          _isSyncing = false;
          _isBackgroundSyncing = false;
          _syncMessage = null;
        });

        if (!isBackground) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.emerald,
              content: Text(
                diffCount > 0
                    ? '$diffCount neues Stück / neue Stücke synchronisiert (${remoteSongs.length} gesamt)!'
                    : 'Bibliothek ist aktuell (${remoteSongs.length} Stücke geprüft)',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (diffCount != 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.primary,
              content: Text('Notenarchiv im Hintergrund aktualisiert: ${remoteSongs.length} Stücke'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _isBackgroundSyncing = false;
          _syncMessage = null;
        });
        if (!isBackground) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.rose,
              content: Text('Synchronisationsfehler: $e'),
            ),
          );
        }
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
          backgroundColor: AppTheme.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.offline_pin_rounded, color: AppTheme.emerald),
              SizedBox(width: 10),
              Text('Bühnen-Download', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: total > 0 ? current / total : 0,
                  backgroundColor: AppTheme.darkSurface,
                  color: AppTheme.emerald,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$current von $total Stücken heruntergeladen...',
                style: const TextStyle(color: AppTheme.darkTextSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );

    for (final song in _allSongs) {
      final bestMatch = VoiceMatcher.findBestMatchForSong(song, widget.profile);
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
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.emerald,
          content: Text('Alle Stimmen für Offline-Betrieb heruntergeladen!'),
        ),
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

    final bestMatch = VoiceMatcher.findBestMatchForSong(song, _activeProfile);
    if (bestMatch == null) {
      showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.darkCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => VoiceSelectorSheet(
          song: song,
          currentPart: song.parts.first,
          profile: _activeProfile,
          onSelectPart: (part) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => ScoreViewerScreen(
                  song: song,
                  initialPart: part,
                  profile: _activeProfile,
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
          profile: _activeProfile,
          storageService: widget.storageService,
          annotationService: widget.annotationService,
          nextcloudService: widget.nextcloudService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.library_music_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Notenarchiv',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_for_offline_rounded),
            tooltip: 'Alle Stimmen für Bühne vorladen',
            onPressed: _downloadAllForOffline,
          ),
          IconButton(
            icon: (_isSyncing || _isBackgroundSyncing)
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryLight),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'Mit Nextcloud synchronisieren',
            onPressed: (_isSyncing || _isBackgroundSyncing)
                ? null
                : () => _syncWithCloud(isBackground: false),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Search & Voice Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Stück suchen...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 22),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // "Nur meine" Toggle Pill
                FilterChip(
                  label: const Text('Nur meine'),
                  selected: _onlyMyVoice,
                  avatar: Icon(
                    _onlyMyVoice ? Icons.check_circle_rounded : Icons.person_rounded,
                    size: 16,
                    color: _onlyMyVoice ? Colors.white : AppTheme.darkTextMuted,
                  ),
                  selectedColor: AppTheme.emerald,
                  checkmarkColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  onSelected: (val) {
                    setState(() {
                      _onlyMyVoice = val;
                      _onSearchChanged();
                    });
                  },
                ),
              ],
            ),
          ),

          // Active Profile Status Indicator
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _showInstrumentFilterSheet,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppTheme.emerald,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Deine Stimme: ',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              _activeProfile.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppTheme.primaryLight,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down_rounded, size: 18, color: AppTheme.primaryLight),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${_filteredSongs.length} ${_filteredSongs.length == 1 ? "Stück" : "Stücke"}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Percussion Sub-Instrument Quick-Selector (Schnellauswahl)
          if (_activeProfile.instrument == 'Percussion')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildPercussionChip(
                      label: 'Alle',
                      icon: Icons.auto_awesome_rounded,
                      subValue: 'Alle',
                      isDark: isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildPercussionChip(
                      label: 'Schlagzeug',
                      icon: Icons.album_rounded,
                      subValue: 'Schlagzeug',
                      isDark: isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildPercussionChip(
                      label: 'Pauken',
                      icon: Icons.radio_button_checked_rounded,
                      subValue: 'Pauken',
                      isDark: isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildPercussionChip(
                      label: 'Mallets',
                      icon: Icons.piano_rounded,
                      subValue: 'Mallets',
                      isDark: isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildPercussionChip(
                      label: 'Percussion',
                      icon: Icons.music_note_rounded,
                      subValue: 'Percussion',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ),

          // Live Sync Progress Bar (only shown during active user sync)
          if (_isSyncing && !_isBackgroundSyncing)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amber),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _syncMessage ?? 'Synchronisiere...',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.amber,
                    ),
                  ),
                ],
              ),
            ),

          // Category Sliding Filter Chips
          if (_categories.length > 2)
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = cat == _selectedCategory;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      selectedColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.white : null,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedCategory = cat;
                            _onSearchChanged();
                          });
                          widget.storageService.setLastActiveCategory(cat);
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
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkSurface : Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.music_off_rounded,
                            size: 48,
                            color: isDark ? AppTheme.darkTextMuted : Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _allSongs.isEmpty
                              ? 'Noch keine Noten synchronisiert'
                              : 'Keine Stücke gefunden',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _onlyMyVoice
                              ? 'Deaktiviere "Nur meine", um alle Stücke zu sehen'
                              : 'Tippe auf Synchronisieren, um Noten zu laden',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_allSongs.isEmpty)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _syncWithCloud,
                            icon: const Icon(Icons.cloud_download_rounded),
                            label: const Text('Jetzt aus Nextcloud laden'),
                          ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: () => _syncWithCloud(isBackground: false),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _filteredSongs.length,
                      separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final song = _filteredSongs[index];
                        final match =
                            VoiceMatcher.findDetailedMatchForSong(song, _activeProfile);
                        final bestMatch = match?.part;
                        final isFallback = match?.isFallback ?? false;
                        final isDoc = song.isDocumentOrList;

                        return Material(
                          color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _openSong(song),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Left Musical Glyph Box
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isDoc
                                          ? AppTheme.primaryLight.withValues(alpha: 0.15)
                                          : (bestMatch != null
                                              ? (isFallback
                                                  ? AppTheme.amber.withValues(alpha: 0.15)
                                                  : AppTheme.emerald.withValues(alpha: 0.12))
                                              : (isDark
                                                  ? AppTheme.darkSurface
                                                  : Colors.grey.shade100)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        isDoc
                                            ? Icons.description_rounded
                                            : (bestMatch != null
                                                ? Icons.music_note_rounded
                                                : Icons.library_music_rounded),
                                        color: isDoc
                                            ? AppTheme.primaryLight
                                            : (bestMatch != null
                                                ? (isFallback ? AppTheme.amber : AppTheme.emerald)
                                                : (isDark
                                                    ? AppTheme.darkTextMuted
                                                    : Colors.grey.shade500)),
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Middle Information
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          song.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            // Matching Voice Badge (or Document Badge for Listen und Co)
                                            if (isDoc)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primaryLight.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: AppTheme.primaryLight.withValues(alpha: 0.35),
                                                  ),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.description_outlined,
                                                      size: 12,
                                                      color: AppTheme.primaryLight,
                                                    ),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'Dokument / Liste (alle Stimmen)',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: AppTheme.primaryLight,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else if (bestMatch != null)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: isFallback
                                                      ? AppTheme.amber.withValues(alpha: 0.15)
                                                      : AppTheme.emerald.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: isFallback
                                                        ? AppTheme.amber.withValues(alpha: 0.4)
                                                        : AppTheme.emerald.withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      isFallback
                                                          ? Icons.info_outline_rounded
                                                          : Icons.check_rounded,
                                                      size: 12,
                                                      color: isFallback
                                                          ? AppTheme.amber
                                                          : AppTheme.emerald,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        isFallback
                                                            ? (_activeProfile.instrument == 'Percussion' &&
                                                                    _activeProfile.percussionInstrument.isNotEmpty &&
                                                                    _activeProfile.percussionInstrument != 'Alle'
                                                                ? 'Keine ${_activeProfile.percussionInstrument} • Ersatz: ${bestMatch.fileName}'
                                                                : 'Keine ${_activeProfile.voiceNumber}. St. • Ersatz: ${bestMatch.fileName}')
                                                            : bestMatch.fileName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: isFallback
                                                              ? AppTheme.amber
                                                              : AppTheme.emerald,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? AppTheme.darkSurface
                                                      : Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  'Keine ${_activeProfile.instrument}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: isDark
                                                        ? AppTheme.darkTextMuted
                                                        : Colors.grey.shade600,
                                                  ),
                                                ),
                                              ),

                                            // Category Tag
                                            if (song.category.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 6, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  song.category,
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: AppTheme.primaryLight,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),

                                            // Parts Count
                                            Text(
                                              '${song.parts.length} Stimmen',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark
                                                    ? AppTheme.darkTextMuted
                                                    : AppTheme.lightTextMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Right Chevron
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: isDark ? AppTheme.darkTextMuted : Colors.grey.shade400,
                                  ),
                                ],
                              ),
                            ),
                          ),
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
