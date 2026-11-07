import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/song.dart';
import '../../services/digitization_service.dart';
import '../../services/edition_lookup_service.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import '../theme/app_theme.dart';

enum AuditStatusFilter {
  all,
  incomplete,
  complete,
}

enum AuditSortOption {
  percentAsc,  // % niedrigste zuerst (Dringend)
  percentDesc, // % höchste zuerst (Fast fertig)
  nameAsc,     // Name (A – Z)
  nameDesc,    // Name (Z – A)
  missingDesc, // Meiste fehlende Stimmen
}

class DigitizationAuditScreen extends StatefulWidget {
  final List<Song> allSongs;
  final StorageService storageService;
  final NextcloudService? nextcloudService;
  final Function(List<Song>)? onSongsUpdated;

  const DigitizationAuditScreen({
    super.key,
    required this.allSongs,
    required this.storageService,
    this.nextcloudService,
    this.onSongsUpdated,
  });

  @override
  State<DigitizationAuditScreen> createState() => _DigitizationAuditScreenState();
}

class _DigitizationAuditScreenState extends State<DigitizationAuditScreen> {
  AuditMode _mode = AuditMode.smartBesetzung;
  String _searchQuery = '';
  String _selectedCategory = 'Alle Kategorien';
  String _selectedInstrument = 'Alle Instrumente';
  AuditStatusFilter _statusFilter = AuditStatusFilter.all; // Show all pieces by default so complete pieces are visible!
  AuditSortOption _sortOption = AuditSortOption.percentAsc;

  late List<Song> _currentSongs;
  late List<SongDigitizationReport> _reports;
  late DigitizationSummary _summary;
  final TextEditingController _searchController = TextEditingController();
  bool _isExporting = false;
  bool _isSyncing = false;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    _currentSongs = List.from(widget.allSongs);
    _recomputeReports();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _recomputeReports() {
    final ignoredMap = widget.storageService.getIgnoredMissingPartsMap();
    _reports = DigitizationService.analyzeAllSongs(
      _currentSongs,
      mode: _mode,
      ignoredPartsMap: ignoredMap,
    );
    _summary = DigitizationService.calculateSummary(_reports);
  }

  Future<void> _syncWithCloud() async {
    if (widget.nextcloudService == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Keine Nextcloud-Verbindung verfügbar (Offline oder nicht angemeldet)'),
            backgroundColor: AppTheme.amber,
          ),
        );
      }
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncMessage = 'Prüfe Cloud auf Änderungen...';
    });

    try {
      final updatedSongs = await widget.nextcloudService!.scanLibrary(
        existingCachedSongs: _currentSongs,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _syncMessage = 'Aktualisiere: $current / $total...';
            });
          }
        },
      );

      await widget.storageService.saveCachedSongs(updatedSongs);

      if (mounted) {
        setState(() {
          _currentSongs = updatedSongs;
          _isSyncing = false;
          _syncMessage = null;
          _recomputeReports();
        });

        widget.onSongsUpdated?.call(updatedSongs);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${updatedSongs.length} Stücke erfolgreich synchronisiert'),
            backgroundColor: AppTheme.emerald,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Synchronisieren: $e'),
            backgroundColor: AppTheme.rose,
          ),
        );
      }
    }
  }

  List<String> get _categories {
    final cats = {'Alle Kategorien'};
    for (final s in _currentSongs) {
      if (s.category.isNotEmpty) cats.add(s.category);
    }
    return cats.toList();
  }

  List<String> get _instrumentsWithMissingParts {
    final insts = {'Alle Instrumente'};
    for (final r in _reports) {
      for (final m in r.missingParts) {
        // Extract instrument root name (e.g. "Trompete" from "Trompete 2")
        final root = m.split(' ').first;
        insts.add(root);
      }
    }
    return insts.toList();
  }

  List<SongDigitizationReport> get _filteredReports {
    final list = _reports.where((r) {
      // 1. Completion / Status filter
      if (_statusFilter == AuditStatusFilter.incomplete && r.isComplete) return false;
      if (_statusFilter == AuditStatusFilter.complete && !r.isComplete) return false;

      // 2. Category filter
      if (_selectedCategory != 'Alle Kategorien' && r.song.category != _selectedCategory) {
        return false;
      }

      // 3. Instrument filter
      if (_selectedInstrument != 'Alle Instrumente') {
        final query = _selectedInstrument.toLowerCase();
        final matchesMissing = r.missingParts.any((m) => m.toLowerCase().contains(query));
        final matchesPresent = r.presentParts.any((p) => p.toLowerCase().contains(query));

        if (_statusFilter == AuditStatusFilter.complete) {
          if (!matchesPresent) return false;
        } else if (_statusFilter == AuditStatusFilter.incomplete) {
          if (!matchesMissing) return false;
        } else {
          if (!matchesMissing && !matchesPresent) return false;
        }
      }

      // 4. Search query
      if (_searchQuery.isNotEmpty) {
        final title = r.song.title.toLowerCase();
        final folder = r.song.folderName.toLowerCase();
        final missing = r.missingParts.join(' ').toLowerCase();
        final present = r.presentParts.join(' ').toLowerCase();
        if (!title.contains(_searchQuery) &&
            !folder.contains(_searchQuery) &&
            !missing.contains(_searchQuery) &&
            !present.contains(_searchQuery)) {
          return false;
        }
      }

      return true;
    }).toList();

    // 5. Apply sorting
    switch (_sortOption) {
      case AuditSortOption.percentAsc:
        list.sort((a, b) {
          final cmp = a.completionPercentage.compareTo(b.completionPercentage);
          if (cmp != 0) return cmp;
          return a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase());
        });
        break;
      case AuditSortOption.percentDesc:
        list.sort((a, b) {
          final cmp = b.completionPercentage.compareTo(a.completionPercentage);
          if (cmp != 0) return cmp;
          return a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase());
        });
        break;
      case AuditSortOption.nameAsc:
        list.sort((a, b) => a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase()));
        break;
      case AuditSortOption.nameDesc:
        list.sort((a, b) => b.song.title.toLowerCase().compareTo(a.song.title.toLowerCase()));
        break;
      case AuditSortOption.missingDesc:
        list.sort((a, b) {
          final cmp = b.missingParts.length.compareTo(a.missingParts.length);
          if (cmp != 0) return cmp;
          return a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase());
        });
        break;
    }

    return list;
  }

  /// Sorts missing parts so that parts matching the selected instrument filter are prioritized to the front
  List<String> _getSortedMissingParts(List<String> missingParts) {
    if (_selectedInstrument == 'Alle Instrumente' || missingParts.isEmpty) {
      return missingParts;
    }

    final query = _selectedInstrument.toLowerCase();
    final matching = <String>[];
    final other = <String>[];

    for (final m in missingParts) {
      if (m.toLowerCase().contains(query)) {
        matching.add(m);
      } else {
        other.add(m);
      }
    }

    return [...matching, ...other];
  }

  Future<void> _shareText() async {
    final text = DigitizationService.generateShareText(
      _filteredReports,
      categoryFilter: _selectedCategory,
      instrumentFilter: _selectedInstrument,
    );
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    try {
      final file = await DigitizationService.generateAuditPdf(
        _filteredReports,
        categoryFilter: _selectedCategory,
        instrumentFilter: _selectedInstrument,
      );

      if (mounted) {
        setState(() => _isExporting = false);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/pdf')],
            text: 'Fehlende Noten Digitalisierungs-Liste (Blasorchester 1862)',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppTheme.rose, content: Text('Fehler beim PDF-Export: $e')),
        );
      }
    }
  }

  void _showExportModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Digitalisierungs-Liste exportieren',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_filteredReports.where((r) => !r.isComplete).length} unvollständige Stücke teilen',
                    style: const TextStyle(fontSize: 13, color: AppTheme.darkTextMuted),
                  ),
                  const SizedBox(height: 18),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.rose.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.rose),
                    ),
                    title: const Text('Als druckfertige PDF exportieren', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    subtitle: const Text('Übersichtliche Tabelle zum Ausdrucken & Notenarchiv-Abhaken', style: TextStyle(fontSize: 12, color: AppTheme.darkTextMuted)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _exportPdf();
                    },
                  ),
                  const Divider(color: AppTheme.darkBorder),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.emerald),
                    ),
                    title: const Text('Als Text / WhatsApp-Nachricht teilen', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    subtitle: const Text('Kompakte Liste für die Musiker-Gruppe', style: TextStyle(fontSize: 12, color: AppTheme.darkTextMuted)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _shareText();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSongDetailsModal(SongDigitizationReport r) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: isLandscape ? 0.85 : 0.65,
            minChildSize: isLandscape ? 0.45 : 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    r.song.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    '${r.song.category} • ${r.completionPercentage.round()}% digitalisiert (${r.totalPresent} von ${r.totalExpected} Stimmen)',
                    style: const TextStyle(fontSize: 12, color: AppTheme.darkTextMuted),
                  ),
                  const SizedBox(height: 16),

                  // Publisher Edition & Online-Lookup Card
                  Builder(builder: (context) {
                    final edition = EditionLookupService.getEdition(r.song.title);

                    if (edition != null) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.menu_book_rounded, color: AppTheme.primaryLight, size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  'VERLAGSAUSGABE & BESETZUNG',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryLight, letterSpacing: 0.5),
                                ),
                                const Spacer(),
                                if (edition.publisher.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryLight.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      edition.publisher,
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (edition.arranger.isNotEmpty || edition.orderNumber.isNotEmpty)
                              Text(
                                [
                                  if (edition.arranger.isNotEmpty) 'Arrangement: ${edition.arranger}',
                                  if (edition.series.isNotEmpty) edition.series,
                                  if (edition.orderNumber.isNotEmpty) 'Bestell-Nr. ${edition.orderNumber}',
                                ].join(' • '),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            if (edition.instrumentationNote.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                edition.instrumentationNote,
                                style: const TextStyle(fontSize: 11, color: AppTheme.darkTextSecondary, height: 1.3),
                              ),
                            ],
                            const SizedBox(height: 12),
                            if (edition.hasDirectUrl)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                  label: Text('Verlagsausgabe öffnen (${edition.publisher})', style: const TextStyle(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryLight,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => launchUrl(
                                    Uri.parse(edition.directUrl!),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                ),
                              )
                            else
                              const Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.darkTextMuted),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Kein direkter Verlagslink verifiziert',
                                      style: TextStyle(fontSize: 11, color: AppTheme.darkTextMuted),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    }

                    // Edition is null: honest status
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.darkBorder),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.library_books_outlined, size: 16, color: AppTheme.darkTextMuted),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Keine spezielle Verlagsausgabe verifiziert. Prüfung erfolgt nach Standard-Blasorchester-Besetzung.',
                              style: TextStyle(fontSize: 11, color: AppTheme.darkTextMuted),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  // Missing section
                  if (r.missingParts.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppTheme.rose, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'FEHLENDE STIMMEN (${r.missingParts.length})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.rose, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Quick action button: "Kein Flügelhorn in diesem Satz"
                    if (r.missingParts.any((m) => m.toLowerCase().contains('flügelhorn') || m.toLowerCase().contains('fluegel')))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.music_off_rounded, size: 16, color: AppTheme.amber),
                            label: const Text('Kein Flügelhorn in diesem Satz (ausblenden)', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.amber,
                              side: BorderSide(color: AppTheme.amber.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () async {
                              final fluegelParts = r.missingParts
                                  .where((m) => m.toLowerCase().contains('flügelhorn') || m.toLowerCase().contains('fluegel'))
                                  .toList();
                              await widget.storageService.setPartsIgnored(r.song.id, fluegelParts, true);
                              if (mounted && ctx.mounted) {
                                setState(() => _recomputeReports());
                                Navigator.pop(ctx);
                                final updated = _reports.firstWhere((rep) => rep.song.id == r.song.id);
                                _showSongDetailsModal(updated);
                              }
                            },
                          ),
                        ),
                      ),

                    // Quick action button: "Alle fehlenden Stimmen dieser Ausgabe ausblenden (nicht im Original)"
                    if (r.missingParts.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.done_all_rounded, size: 16, color: AppTheme.emerald),
                            label: Text('Alle ${r.missingParts.length} Stimmen als "nicht im Original" markieren', style: const TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.emerald,
                              side: BorderSide(color: AppTheme.emerald.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () async {
                              await widget.storageService.setPartsIgnored(r.song.id, r.missingParts, true);
                              if (mounted && ctx.mounted) {
                                setState(() => _recomputeReports());
                                Navigator.pop(ctx);
                                final updated = _reports.firstWhere((rep) => rep.song.id == r.song.id);
                                _showSongDetailsModal(updated);
                              }
                            },
                          ),
                        ),
                      ),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.rose.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.rose.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _getSortedMissingParts(r.missingParts).map((m) {
                          final isTarget = _selectedInstrument != 'Alle Instrumente' &&
                              m.toLowerCase().contains(_selectedInstrument.toLowerCase());

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Icon(
                                  isTarget ? Icons.star_rounded : Icons.close_rounded,
                                  size: 16,
                                  color: isTarget ? AppTheme.amber : AppTheme.rose,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    m,
                                    style: TextStyle(
                                      color: isTarget ? AppTheme.amber : Colors.white,
                                      fontWeight: isTarget ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (isTarget ? AppTheme.amber : AppTheme.rose).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: isTarget ? Border.all(color: AppTheme.amber.withValues(alpha: 0.5)) : null,
                                  ),
                                  child: Text(
                                    isTarget ? 'Ausgewähltes Instrument' : 'Noch einscannen',
                                    style: TextStyle(
                                      color: isTarget ? AppTheme.amber : AppTheme.rose,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.visibility_off_outlined, size: 16, color: AppTheme.darkTextMuted),
                                  tooltip: 'Nicht im Original vorhanden (ausblenden)',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  onPressed: () async {
                                    await widget.storageService.setPartIgnored(r.song.id, m, true);
                                    if (mounted && ctx.mounted) {
                                      setState(() => _recomputeReports());
                                      Navigator.pop(ctx);
                                      final updated = _reports.firstWhere((rep) => rep.song.id == r.song.id);
                                      _showSongDetailsModal(updated);
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Ignored parts section (marked as "nicht im Original vorhanden")
                  if (r.ignoredParts.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.visibility_off_rounded, color: AppTheme.darkTextMuted, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'NICHT IM ORIGINALSATZ VORHANDEN (${r.ignoredParts.length})',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.darkTextMuted, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.darkBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: r.ignoredParts.map((ign) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.check_rounded, size: 14, color: AppTheme.darkTextMuted),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(ign, style: const TextStyle(color: AppTheme.darkTextMuted, fontSize: 12)),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () async {
                                    await widget.storageService.setPartIgnored(r.song.id, ign, false);
                                    if (mounted && ctx.mounted) {
                                      setState(() => _recomputeReports());
                                      Navigator.pop(ctx);
                                      final updated = _reports.firstWhere((rep) => rep.song.id == r.song.id);
                                      _showSongDetailsModal(updated);
                                    }
                                  },
                                  child: const Text('Wiederherstellen', style: TextStyle(fontSize: 11, color: AppTheme.primaryLight)),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Present section
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'VORHANDENE STIMMEN (${r.presentParts.length})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.emerald, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.darkBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: r.presentParts.map((p) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              const Icon(Icons.check_rounded, size: 16, color: AppTheme.emerald),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(p, style: const TextStyle(color: AppTheme.darkTextSecondary, fontSize: 12)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredReports;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        foregroundColor: AppTheme.darkTextPrimary,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Digitalisierungs-Check', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Fehlende Noten & Lücken-Erkennung', style: TextStyle(fontSize: 12, color: AppTheme.darkTextMuted)),
          ],
        ),
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryLight),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync_rounded, color: AppTheme.primaryLight),
              tooltip: 'Mit Nextcloud synchronisieren',
              onPressed: _syncWithCloud,
            ),
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryLight),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.share_rounded, color: AppTheme.primaryLight),
              tooltip: 'Digitalisierungs-Liste exportieren',
              onPressed: _showExportModal,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _syncWithCloud,
        color: AppTheme.primaryLight,
        backgroundColor: AppTheme.darkSurface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (_isSyncing)
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation(AppTheme.primaryLight),
                    ),
                    if (_syncMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                        color: AppTheme.primaryLight.withValues(alpha: 0.15),
                        child: Text(
                          _syncMessage!,
                          style: const TextStyle(fontSize: 11, color: AppTheme.primaryLight, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),

            // Header Section: Stats, Modes, Priorities, Search & Filters
            SliverToBoxAdapter(
              child: _buildHeaderControls(isLandscape),
            ),

            // Empty state or Songs List
            if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, color: AppTheme.emerald, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          _statusFilter == AuditStatusFilter.incomplete
                              ? 'Keine fehlenden Noten in dieser Auswahl gefunden!'
                              : (_statusFilter == AuditStatusFilter.complete
                                  ? 'Keine vollständig digitalisierten Stücke in dieser Auswahl.'
                                  : 'Keine Stücke gefunden.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.darkTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                sliver: SliverList.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, index) {
                    final r = filtered[index];
                    return _buildSongAuditCard(r);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderControls(bool isLandscape) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Overall Score & Stats Card
        _buildStatsSection(isLandscape),

        // 2. Mode Selector Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              ChoiceChip(
                selected: _mode == AuditMode.smartBesetzung,
                label: const Text('Smart-Besetzung (Auto)'),
                onSelected: (sel) {
                  if (sel) {
                    setState(() {
                      _mode = AuditMode.smartBesetzung;
                      _recomputeReports();
                    });
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                selected: _mode == AuditMode.standardBesetzung,
                label: const Text('Klassisch (18 Kernstimmen)'),
                onSelected: (sel) {
                  if (sel) {
                    setState(() {
                      _mode = AuditMode.standardBesetzung;
                      _recomputeReports();
                    });
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                selected: _mode == AuditMode.vollbesetzung,
                label: const Text('Großes Blasorchester'),
                onSelected: (sel) {
                  if (sel) {
                    setState(() {
                      _mode = AuditMode.vollbesetzung;
                      _recomputeReports();
                    });
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                selected: _mode == AuditMode.registerLuecken,
                label: const Text('Nur Register-Lücken'),
                onSelected: (sel) {
                  if (sel) {
                    setState(() {
                      _mode = AuditMode.registerLuecken;
                      _recomputeReports();
                    });
                  }
                },
              ),
            ],
          ),
        ),

        // 2.5 Priority Recommendations Carousel ("Nächste Digitalisierungs-Ziele")
        if (_summary.priorities.isNotEmpty) _buildPriorityCarousel(),

        // 3. Search Bar, Sort & Category/Instrument Filters
        _buildSearchAndFilters(isLandscape),
      ],
    );
  }

  Widget _buildScoreCard() {
    final pct = _summary.overallPercentage;
    final color = pct >= 80 ? AppTheme.emerald : (pct >= 50 ? AppTheme.amber : AppTheme.rose);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.pie_chart_rounded,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: Text(
                        'Gesamt-Digitalisierungsscore',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (pct / 100.0).clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(bool isLandscape) {
    final statRow = Row(
      children: [
        _buildStatItem('Stücke', '${_summary.totalSongs}', Colors.white,
            isSelected: _statusFilter == AuditStatusFilter.all,
            onTap: () => setState(() => _statusFilter = AuditStatusFilter.all)),
        _buildStatItem('Vollständig', '${_summary.completeSongs}', AppTheme.emerald,
            isSelected: _statusFilter == AuditStatusFilter.complete,
            onTap: () => setState(() => _statusFilter = AuditStatusFilter.complete)),
        _buildStatItem('Unvollständig', '${_summary.incompleteSongs}', AppTheme.amber,
            isSelected: _statusFilter == AuditStatusFilter.incomplete,
            onTap: () => setState(() => _statusFilter = AuditStatusFilter.incomplete)),
        _buildStatItem('Fehlt gesamt', '${_summary.totalMissingParts}', AppTheme.rose),
      ],
    );

    return Container(
      padding: EdgeInsets.fromLTRB(16, isLandscape ? 8 : 12, 16, isLandscape ? 10 : 14),
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        border: Border(bottom: BorderSide(color: AppTheme.darkBorder)),
      ),
      child: isLandscape
          ? Row(
              children: [
                Expanded(flex: 5, child: _buildScoreCard()),
                const SizedBox(width: 14),
                Expanded(flex: 6, child: statRow),
              ],
            )
          : Column(
              children: [
                _buildScoreCard(),
                const SizedBox(height: 10),
                statRow,
              ],
            ),
    );
  }

  Widget _buildPriorityCarousel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryLight.withValues(alpha: 0.12),
              AppTheme.darkCard,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: AppTheme.amber, size: 16),
                const SizedBox(width: 6),
                const Text(
                  'Empfohlene nächste Digitalisierungs-Ziele',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Tippen zum Filtern',
                  style: TextStyle(fontSize: 10, color: AppTheme.darkTextMuted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _summary.priorities.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final p = _summary.priorities[idx];
                  final root = p.instrumentOrVoice.split(' ').first;
                  final isSelected = _selectedInstrument == root;

                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedInstrument = 'Alle Instrumente';
                        } else {
                          _selectedInstrument = _instrumentsWithMissingParts.contains(root)
                              ? root
                              : 'Alle Instrumente';
                        }
                      });
                    },
                    child: Container(
                      width: 190,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.amber.withValues(alpha: 0.22)
                            : AppTheme.darkSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? AppTheme.amber : AppTheme.darkBorder,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Text(
                                '#${idx + 1}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.amber,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  p.instrumentOrVoice,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Fehlt in ${p.missingCount} Stücken',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10, color: AppTheme.rose),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${p.completionRate.round()}%',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: p.completionRate >= 50 ? AppTheme.amber : AppTheme.rose,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters(bool isLandscape) {
    final searchField = TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Stück, Verlag oder Stimme suchen...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 16),
                onPressed: () => _searchController.clear(),
              )
            : null,
      ),
    );

    final sortDropdown = Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.sort_rounded, size: 18, color: AppTheme.primaryLight),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AuditSortOption>(
                value: _sortOption,
                isExpanded: true,
                dropdownColor: AppTheme.darkCard,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                items: const [
                  DropdownMenuItem(
                    value: AuditSortOption.percentAsc,
                    child: Text('Sortierung: % aufsteigend (Dringendste zuerst)', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: AuditSortOption.percentDesc,
                    child: Text('Sortierung: % absteigend (Fast fertige zuerst)', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: AuditSortOption.nameAsc,
                    child: Text('Sortierung: Name (A – Z)', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: AuditSortOption.nameDesc,
                    child: Text('Sortierung: Name (Z – A)', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: AuditSortOption.missingDesc,
                    child: Text('Sortierung: Meiste fehlende Stimmen', overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (opt) {
                  if (opt != null) setState(() => _sortOption = opt);
                },
              ),
            ),
          ),
        ],
      ),
    );

    final categoryDropdown = Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          dropdownColor: AppTheme.darkCard,
          style: const TextStyle(fontSize: 12, color: Colors.white),
          items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (cat) {
            if (cat != null) setState(() => _selectedCategory = cat);
          },
        ),
      ),
    );

    final instrumentDropdown = Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedInstrument,
          isExpanded: true,
          dropdownColor: AppTheme.darkCard,
          style: const TextStyle(fontSize: 12, color: Colors.white),
          items: _instrumentsWithMissingParts
              .map((i) => DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (inst) {
            if (inst != null) setState(() => _selectedInstrument = inst);
          },
        ),
      ),
    );

    if (isLandscape) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(flex: 3, child: searchField),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: sortDropdown),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: categoryDropdown),
                const SizedBox(width: 10),
                Expanded(child: instrumentDropdown),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: searchField,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: sortDropdown,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(child: categoryDropdown),
              const SizedBox(width: 10),
              Expanded(child: instrumentDropdown),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, Color color,
      {bool isSelected = false, VoidCallback? onTap}) {
    final item = Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? color.withValues(alpha: 0.5) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              if (isSelected) ...[
                const SizedBox(width: 3),
                Icon(Icons.check_rounded, size: 14, color: color),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isSelected ? color : AppTheme.darkTextMuted,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );

    return Expanded(
      child: onTap != null
          ? InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: item,
            )
          : item,
    );
  }

  Widget _buildSongAuditCard(SongDigitizationReport r) {
    final pct = r.completionPercentage.round();
    final isComplete = r.isComplete;
    final edition = EditionLookupService.getEdition(r.song.title);

    final subtitleParts = <String>[r.song.category];
    if (edition != null && edition.publisher.isNotEmpty) {
      subtitleParts.add(edition.publisher);
    }
    subtitleParts.add('${r.totalPresent} Stimmen digitalisiert');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppTheme.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isComplete ? AppTheme.emerald.withValues(alpha: 0.45) : AppTheme.darkBorder,
          width: isComplete ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showSongDetailsModal(r),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.song.title,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitleParts.join(' • '),
                          style: const TextStyle(fontSize: 11, color: AppTheme.darkTextMuted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isComplete
                          ? AppTheme.emerald.withValues(alpha: 0.18)
                          : (pct >= 75
                              ? AppTheme.amber.withValues(alpha: 0.18)
                              : AppTheme.rose.withValues(alpha: 0.18)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isComplete ? '100% ✓' : '$pct%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isComplete ? AppTheme.emerald : (pct >= 75 ? AppTheme.amber : AppTheme.rose),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Linear progress indicator
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: r.completionPercentage / 100.0,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(
                    isComplete ? AppTheme.emerald : (pct >= 75 ? AppTheme.amber : AppTheme.rose),
                  ),
                  minHeight: 5,
                ),
              ),

              const SizedBox(height: 8),

              // Quick footer row: Online link on the right, status on the left
              Row(
                children: [
                  if (isComplete)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.emerald),
                        SizedBox(width: 4),
                        Text(
                          'Alle Stimmen vollständig!',
                          style: TextStyle(color: AppTheme.emerald, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    )
                  else
                    const SizedBox.shrink(),
                  if (edition != null && edition.hasDirectUrl) ...[
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => launchUrl(
                        Uri.parse(edition.directUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              edition.publisher.isNotEmpty ? edition.publisher : 'Verlagsausgabe',
                              style: const TextStyle(fontSize: 10, color: AppTheme.primaryLight, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.open_in_new_rounded, size: 11, color: AppTheme.primaryLight),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              if (r.missingParts.isNotEmpty) ...[
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final sortedMissing = _getSortedMissingParts(r.missingParts);
                    final isInstrumentFiltered = _selectedInstrument != 'Alle Instrumente';
                    final visibleMissing = sortedMissing.take(6).toList();
                    final remainingCount = sortedMissing.length - visibleMissing.length;

                    return Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...visibleMissing.map((m) {
                          final isTarget = isInstrumentFiltered &&
                              m.toLowerCase().contains(_selectedInstrument.toLowerCase());

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isTarget
                                  ? AppTheme.amber.withValues(alpha: 0.22)
                                  : AppTheme.rose.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isTarget
                                    ? AppTheme.amber
                                    : AppTheme.rose.withValues(alpha: 0.3),
                                width: isTarget ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isTarget) ...[
                                  const Icon(Icons.star_rounded, size: 12, color: AppTheme.amber),
                                  const SizedBox(width: 3),
                                ],
                                Text(
                                  'Fehlt: $m',
                                  style: TextStyle(
                                    color: isTarget ? AppTheme.amber : AppTheme.rose,
                                    fontSize: 10,
                                    fontWeight: isTarget ? FontWeight.bold : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (remainingCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '+$remainingCount weitere',
                              style: const TextStyle(color: AppTheme.darkTextMuted, fontSize: 10),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
