import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/musician_profile.dart';
import '../../models/setlist.dart';
import '../../services/annotation_service.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/setlist_export_sheet.dart';
import 'setlist_detail_screen.dart';

class SetlistsScreen extends StatefulWidget {
  final StorageService storageService;
  final AnnotationService annotationService;
  final NextcloudService? nextcloudService;
  final MusicianProfile profile;

  const SetlistsScreen({
    super.key,
    required this.storageService,
    required this.annotationService,
    this.nextcloudService,
    required this.profile,
  });

  @override
  State<SetlistsScreen> createState() => _SetlistsScreenState();
}

class _SetlistsScreenState extends State<SetlistsScreen> {
  List<Setlist> _setlists = [];
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadSetlists();
    if (widget.nextcloudService != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncSetlistsWithCloud(silent: true);
      });
    }
  }

  void _loadSetlists() {
    setState(() {
      _setlists = widget.storageService.getLocalSetlists();
      _setlists.sort((a, b) => b.date.compareTo(a.date));
    });
  }

  Future<void> _syncSetlistsWithCloud({bool silent = false}) async {
    if (widget.nextcloudService == null) return;

    setState(() {
      _isSyncing = true;
    });

    try {
      final remoteSetlists = await widget.nextcloudService!.fetchSetlists();
      for (final remote in remoteSetlists) {
        await widget.storageService.upsertSetlist(remote);
      }
      _loadSetlists();

      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.emerald,
            content: Text('${remoteSetlists.length} Setlisten von Nextcloud synchronisiert!'),
          ),
        );
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.rose,
            content: Text('Fehler beim Abrufen der Setlisten: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  void _deleteSetlist(Setlist setlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Setlist löschen?'),
        content: Text('Möchtest du "${setlist.title}" wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen', style: TextStyle(color: AppTheme.darkTextMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.rose, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.storageService.deleteSetlist(setlist.id);
      if (widget.nextcloudService != null && setlist.isSyncedWithCloud) {
        widget.nextcloudService!.deleteSetlist(setlist.id).catchError((_) => false);
      }
      _loadSetlists();

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2D2E30),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.darkBorder),
            ),
            content: Row(
              children: [
                const Icon(Icons.event_note_rounded, color: AppTheme.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Setlist "${setlist.title}" gelöscht',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'ZURÜCKHOLEN',
              textColor: AppTheme.amber,
              onPressed: () async {
                await widget.storageService.upsertSetlist(setlist);
                if (widget.nextcloudService != null && setlist.isSyncedWithCloud) {
                  widget.nextcloudService!.uploadSetlist(setlist).catchError((_) => false);
                }
                _loadSetlists();
              },
            ),
          ),
        );
      }
    }
  }

  void _createNewSetlist() {
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Neue Setlist erstellen', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Titel / Anlass',
                  hintText: 'z.B. Frühjahrskonzert 2027',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: AppTheme.primaryLight),
                ),
                title: Text('Datum: ${DateFormat('dd. MMMM yyyy', 'de_DE').format(selectedDate)}'),
                trailing: TextButton(
                  child: const Text('Ändern'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedDate = picked;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) return;

                var newSetlist = Setlist.create(
                  title: title,
                  date: selectedDate,
                );

                if (widget.nextcloudService != null) {
                  final uploaded = await widget.nextcloudService!.uploadSetlist(newSetlist);
                  if (uploaded) {
                    newSetlist = newSetlist.copyWith(isSyncedWithCloud: true);
                  }
                }

                await widget.storageService.upsertSetlist(newSetlist);
                _loadSetlists();
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  _openSetlist(newSetlist);
                }
              },
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSetlist(Setlist setlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => SetlistDetailScreen(
          setlist: setlist,
          storageService: widget.storageService,
          annotationService: widget.annotationService,
          nextcloudService: widget.nextcloudService,
          profile: widget.profile,
          onSetlistUpdated: (updated) {
            _loadSetlists();
          },
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
                  colors: [AppTheme.amber, Color(0xFFF97316)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.event_note_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Setlisten & Auftritte',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amber),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'Setlisten von Nextcloud laden',
            onPressed: _isSyncing ? null : _syncSetlistsWithCloud,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _setlists.isEmpty
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
                      Icons.format_list_bulleted_rounded,
                      size: 48,
                      color: isDark ? AppTheme.darkTextMuted : Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Noch keine Setlisten vorhanden',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Erstelle eine Setlist für deine nächsten Konzerte',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _createNewSetlist,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Erste Setlist anlegen'),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _setlists.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final setlist = _setlists[index];
                final playableSongs = setlist.items.where((i) => !i.isIntermission).length;
                final monthStr = DateFormat('MMM', 'de_DE').format(setlist.date).toUpperCase();
                final dayStr = DateFormat('dd').format(setlist.date);

                return Material(
                  color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openSetlist(setlist),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Calendar Badge Square
                          Container(
                            width: 52,
                            height: 56,
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkSurface : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  monthStr,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.amber,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  dayStr,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Setlist Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  setlist.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      '$playableSongs ${playableSongs == 1 ? "Stück" : "Stücke"}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                      ),
                                    ),
                                    if (setlist.isSyncedWithCloud)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.emerald.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.cloud_done_rounded, size: 12, color: AppTheme.emerald),
                                            SizedBox(width: 4),
                                            Text(
                                              'Nextcloud',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.emerald,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark ? AppTheme.darkSurface : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'Lokal',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: isDark ? AppTheme.darkTextMuted : Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // More options / delete
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert_rounded,
                              size: 18,
                              color: isDark ? AppTheme.darkTextMuted : Colors.grey.shade400,
                            ),
                            color: AppTheme.darkCard,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onSelected: (val) {
                              if (val == 'share') {
                                SetlistExportSheet.show(
                                  context,
                                  setlist: setlist,
                                  currentProfile: widget.profile,
                                  storageService: widget.storageService,
                                  nextcloudService: widget.nextcloudService,
                                );
                              } else if (val == 'delete') {
                                _deleteSetlist(setlist);
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'share',
                                child: Row(
                                  children: [
                                    Icon(Icons.share_rounded, color: AppTheme.amber, size: 18),
                                    SizedBox(width: 8),
                                    Text('Als PDF teilen / Aushilfe'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline_rounded, color: AppTheme.rose, size: 18),
                                    SizedBox(width: 8),
                                    Text('Setlist löschen', style: TextStyle(color: AppTheme.rose)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 4),

                          // Chevron
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewSetlist,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Neue Setlist', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
