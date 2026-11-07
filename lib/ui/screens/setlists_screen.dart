import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/konzertmeister_appointment.dart';
import '../../models/musician_profile.dart';
import '../../models/setlist.dart';
import '../../services/annotation_service.dart';
import '../../services/konzertmeister_service.dart';
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
  late final KonzertmeisterService _kmService;
  List<Setlist> _setlists = [];
  List<KonzertmeisterAppointment> _kmAppointments = [];
  Map<String, String> _kmAssignments = {};
  bool _isSyncing = false;
  bool _isLoadingKm = false;

  @override
  void initState() {
    super.initState();
    _kmService = KonzertmeisterService(storageService: widget.storageService);
    _loadSetlists();
    _loadKmData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.nextcloudService != null) {
        _syncSetlistsWithCloud(silent: true);
      }
      _refreshKmAppointments(silent: true);
    });
  }

  void _loadSetlists() {
    setState(() {
      _setlists = widget.storageService.getLocalSetlists();
      _setlists.sort((a, b) => b.date.compareTo(a.date));
    });
  }

  void _loadKmData() {
    setState(() {
      _kmAppointments = widget.storageService.getCachedKonzertmeisterAppointments();
      _kmAssignments = widget.storageService.getKonzertmeisterSetlistAssignments();
    });
  }

  Future<void> _refreshKmAppointments({bool silent = false}) async {
    if (!widget.storageService.isKonzertmeisterEnabled()) return;
    if (mounted) {
      setState(() => _isLoadingKm = true);
    }

    try {
      final fresh = await _kmService.fetchAppointments(forceRefresh: true);
      if (mounted) {
        setState(() {
          _kmAppointments = fresh;
          _kmAssignments = widget.storageService.getKonzertmeisterSetlistAssignments();
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF0284C7),
              content: Text('${fresh.length} Konzertmeister Auftritte aktualisiert'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.rose,
            content: Text('Fehler beim Konzertmeister-Abruf: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingKm = false);
      }
    }
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
        // If setlist has a linked Konzertmeister appointment, register the mapping locally
        if (remote.konzertmeisterAppointmentId != null &&
            remote.konzertmeisterAppointmentId!.isNotEmpty) {
          await widget.storageService.setKonzertmeisterSetlistAssignment(
            remote.konzertmeisterAppointmentId!,
            remote.id,
          );
        }
      }

      // Also fetch dedicated shared assignments table from Nextcloud
      final remoteAssignments =
          await widget.nextcloudService!.fetchKonzertmeisterAssignments();
      for (final entry in remoteAssignments.entries) {
        await widget.storageService.setKonzertmeisterSetlistAssignment(
          entry.key,
          entry.value,
        );
      }

      _loadSetlists();
      _loadKmData();

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
      // Remove any appointment assignment referencing this setlist
      final assignedAppId = widget.storageService.getAssignedAppointmentIdForSetlist(setlist.id);
      if (assignedAppId != null) {
        await widget.storageService.setKonzertmeisterSetlistAssignment(assignedAppId, null);
      }

      await widget.storageService.deleteSetlist(setlist.id);
      if (widget.nextcloudService != null && setlist.isSyncedWithCloud) {
        widget.nextcloudService!.deleteSetlist(setlist.id).catchError((_) => false);
        widget.nextcloudService!.uploadKonzertmeisterAssignments(
          widget.storageService.getKonzertmeisterSetlistAssignments(),
        ).catchError((_) => false);
      }
      _loadSetlists();
      _loadKmData();

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
                if (assignedAppId != null) {
                  await widget.storageService.setKonzertmeisterSetlistAssignment(assignedAppId, setlist.id);
                }
                if (widget.nextcloudService != null && setlist.isSyncedWithCloud) {
                  widget.nextcloudService!.uploadSetlist(setlist).catchError((_) => false);
                }
                _loadSetlists();
                _loadKmData();
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

  Future<void> _createSetlistForAppointment(KonzertmeisterAppointment appointment) async {
    var newSetlist = Setlist.create(
      title: appointment.title,
      date: appointment.dateTime,
      konzertmeisterAppointmentId: appointment.id,
    );

    await widget.storageService.upsertSetlist(newSetlist);
    await widget.storageService.setKonzertmeisterSetlistAssignment(appointment.id, newSetlist.id);

    if (widget.nextcloudService != null) {
      final uploaded = await widget.nextcloudService!.uploadSetlist(newSetlist);
      if (uploaded) {
        newSetlist = newSetlist.copyWith(isSyncedWithCloud: true);
        await widget.storageService.upsertSetlist(newSetlist);
      }
      // Upload shared assignments to Nextcloud for all band members
      await widget.nextcloudService!.uploadKonzertmeisterAssignments(
        widget.storageService.getKonzertmeisterSetlistAssignments(),
      );
    }

    _loadSetlists();
    _loadKmData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0284C7),
          content: Text('Setliste "${newSetlist.title}" erstellt und auf Nextcloud synchronisiert!'),
        ),
      );
      _openSetlist(newSetlist);
    }
  }

  void _showAssignSetlistSheet(KonzertmeisterAppointment appointment) {
    final assignedId = _kmAssignments[appointment.id];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.event_available_rounded, color: Color(0xFF0284C7), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Setliste zuweisen',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${appointment.title} (${appointment.dateString})',
                              style: const TextStyle(fontSize: 12, color: AppTheme.darkTextMuted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Action 1: Create New Setlist prefilled for this gig
                  Material(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _createSetlistForAppointment(appointment);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.add_circle_outline_rounded, color: AppTheme.primaryLight, size: 22),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '+ Neue Setliste für diesen Auftritt anlegen',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppTheme.primaryLight,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Übernimmt automatisch Titel & Datum des Auftritts',
                                    style: TextStyle(fontSize: 11, color: AppTheme.darkTextSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'Oder bestehende Setliste verknüpfen:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.darkTextMuted),
                  ),
                  const SizedBox(height: 8),

                  Expanded(
                    child: _setlists.isEmpty
                        ? const Center(
                            child: Text(
                              'Keine bestehenden Setlisten vorhanden',
                              style: TextStyle(color: AppTheme.darkTextMuted),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: _setlists.length,
                            separatorBuilder: (c, i) => const Divider(height: 1, color: AppTheme.darkBorder),
                            itemBuilder: (c, idx) {
                              final sl = _setlists[idx];
                              final isCurrent = sl.id == assignedId;
                              final count = sl.items.where((i) => !i.isIntermission).length;
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                                        : AppTheme.darkSurface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isCurrent ? const Color(0xFF0284C7) : AppTheme.darkBorder,
                                    ),
                                  ),
                                  child: Icon(
                                    isCurrent ? Icons.check_circle_rounded : Icons.playlist_play_rounded,
                                    color: isCurrent ? const Color(0xFF0284C7) : AppTheme.darkTextMuted,
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  sl.title,
                                  style: TextStyle(
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                    color: isCurrent ? const Color(0xFF0284C7) : Colors.white,
                                  ),
                                ),
                                subtitle: Text(
                                  '${DateFormat('dd.MM.yyyy').format(sl.date)} • $count Stücke',
                                  style: const TextStyle(fontSize: 11, color: AppTheme.darkTextMuted),
                                ),
                                trailing: isCurrent
                                    ? TextButton(
                                        onPressed: () async {
                                          final nav = Navigator.of(ctx);
                                          await widget.storageService
                                              .setKonzertmeisterSetlistAssignment(appointment.id, null);
                                          final cleared = sl.copyWith(clearKonzertmeisterAppointmentId: true);
                                          await widget.storageService.upsertSetlist(cleared);
                                          if (widget.nextcloudService != null) {
                                            if (cleared.isSyncedWithCloud) {
                                              await widget.nextcloudService!.uploadSetlist(cleared);
                                            }
                                            await widget.nextcloudService!.uploadKonzertmeisterAssignments(
                                              widget.storageService.getKonzertmeisterSetlistAssignments(),
                                            );
                                          }
                                          _loadSetlists();
                                          _loadKmData();
                                          nav.pop();
                                        },
                                        child: const Text('Lösen', style: TextStyle(color: AppTheme.rose, fontSize: 12)),
                                      )
                                    : const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.darkTextMuted),
                                onTap: () async {
                                  final nav = Navigator.of(ctx);
                                  final messenger = ScaffoldMessenger.of(context);
                                  await widget.storageService
                                      .setKonzertmeisterSetlistAssignment(appointment.id, sl.id);
                                  var updated = sl.copyWith(konzertmeisterAppointmentId: appointment.id);
                                  await widget.storageService.upsertSetlist(updated);

                                  if (widget.nextcloudService != null) {
                                    final uploaded = await widget.nextcloudService!.uploadSetlist(updated);
                                    if (uploaded) {
                                      updated = updated.copyWith(isSyncedWithCloud: true);
                                      await widget.storageService.upsertSetlist(updated);
                                    }
                                    await widget.nextcloudService!.uploadKonzertmeisterAssignments(
                                      widget.storageService.getKonzertmeisterSetlistAssignments(),
                                    );
                                  }

                                  _loadSetlists();
                                  _loadKmData();
                                  nav.pop();
                                  messenger.showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFF0284C7),
                                      content: Text('Setliste "${sl.title}" verknüpft und auf Nextcloud synchronisiert!'),
                                    ),
                                  );
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
    );
  }

  void _unlinkKmSetlist(KonzertmeisterAppointment appointment) async {
    final assignedId = widget.storageService.getAssignedSetlistIdForAppointment(appointment.id);
    await widget.storageService.setKonzertmeisterSetlistAssignment(appointment.id, null);

    if (assignedId != null) {
      final existing = _setlists.where((s) => s.id == assignedId).firstOrNull;
      if (existing != null) {
        final cleared = existing.copyWith(clearKonzertmeisterAppointmentId: true);
        await widget.storageService.upsertSetlist(cleared);
        if (widget.nextcloudService != null && cleared.isSyncedWithCloud) {
          await widget.nextcloudService!.uploadSetlist(cleared);
        }
      }
    }

    if (widget.nextcloudService != null) {
      await widget.nextcloudService!.uploadKonzertmeisterAssignments(
        widget.storageService.getKonzertmeisterSetlistAssignments(),
      );
    }

    _loadSetlists();
    _loadKmData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.amber,
          content: Text('Setlist-Verknüpfung gelöst und auf Nextcloud synchronisiert.'),
        ),
      );
    }
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

  Widget _buildKonzertmeisterSection(bool isDark) {
    if (!widget.storageService.isKonzertmeisterEnabled()) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF2BA9E0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.event_available_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kommende Auftritte (Konzertmeister)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: -0.2),
                  ),
                  Text(
                    'Aus dem Vereinskalender synchronisiert',
                    style: TextStyle(fontSize: 11, color: AppTheme.darkTextMuted),
                  ),
                ],
              ),
            ),
            if (_isLoadingKm)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2BA9E0)),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: 'Auftritte von Konzertmeister neu laden',
                visualDensity: VisualDensity.compact,
                onPressed: () => _refreshKmAppointments(silent: false),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_kmAppointments.isEmpty && !_isLoadingKm)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_busy_rounded,
                  color: isDark ? AppTheme.darkTextMuted : Colors.grey.shade400,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Keine anstehenden öffentlichen Auftritte im Kalender.',
                    style: TextStyle(fontSize: 13, color: AppTheme.darkTextMuted),
                  ),
                ),
              ],
            ),
          )
        else
          ..._kmAppointments.map((app) => _buildKonzertmeisterCard(app, isDark)),
        const SizedBox(height: 24),
        Row(
          children: [
            const Text(
              'Setlisten',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_setlists.length}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.darkTextMuted : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildKonzertmeisterCard(KonzertmeisterAppointment app, bool isDark) {
    final assignedId = _kmAssignments[app.id];
    final assignedSetlist = assignedId != null
        ? _setlists.where((s) => s.id == assignedId).firstOrNull
        : null;

    final monthStr = app.dateString.split('.').length > 1
        ? app.dateString.split('.')[1].replaceAll(RegExp(r'\d'), '').trim().toUpperCase()
        : 'TERMIN';
    final dayStr = app.dateTime.day.toString().padLeft(2, '0');
    final weekdayStr = app.weekday.isNotEmpty
        ? app.weekday
        : DateFormat('E', 'de_DE').format(app.dateTime);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: assignedSetlist != null
              ? const Color(0xFF0284C7).withValues(alpha: 0.4)
              : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Badge Square
                Container(
                  width: 52,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0284C7), Color(0xFF2BA9E0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        weekdayStr.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        dayStr,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        monthStr,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Appointment Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              app.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: app.isCancelled
                                  ? AppTheme.rose.withValues(alpha: 0.15)
                                  : const Color(0xFF0284C7).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              app.isCancelled ? 'Abgesagt' : app.type,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: app.isCancelled ? AppTheme.rose : const Color(0xFF0284C7),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Time
                      if (app.timeString.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded, size: 13, color: AppTheme.amber),
                            const SizedBox(width: 5),
                            Text(
                              app.timeString,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],

                      // Location (tappable for Google Maps)
                      if (app.location.isNotEmpty) ...[
                        InkWell(
                          onTap: app.mapsUrl.isNotEmpty
                              ? () => launchUrl(Uri.parse(app.mapsUrl), mode: LaunchMode.externalApplication)
                              : null,
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            children: [
                              const Icon(Icons.place_rounded, size: 13, color: Color(0xFF2BA9E0)),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  app.location,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF2BA9E0),
                                    decoration: TextDecoration.underline,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Assignment Footer Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: assignedSetlist != null
                  ? const Color(0xFF0284C7).withValues(alpha: 0.08)
                  : (isDark ? AppTheme.darkSurface.withValues(alpha: 0.5) : Colors.grey.shade50),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
              border: Border(
                top: BorderSide(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
              ),
            ),
            child: assignedSetlist != null
                ? Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.playlist_play_rounded, color: Color(0xFF0284C7), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              assignedSetlist.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${assignedSetlist.items.where((i) => !i.isIntermission).length} Stücke zugewiesen',
                              style: const TextStyle(fontSize: 11, color: AppTheme.darkTextMuted),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _openSetlist(assignedSetlist),
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: const Text('Öffnen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppTheme.darkTextMuted),
                        color: AppTheme.darkCard,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (val) {
                          if (val == 'change') {
                            _showAssignSetlistSheet(app);
                          } else if (val == 'unlink') {
                            _unlinkKmSetlist(app);
                          }
                        },
                        itemBuilder: (c) => [
                          const PopupMenuItem(
                            value: 'change',
                            child: Row(
                              children: [
                                Icon(Icons.swap_horiz_rounded, color: Color(0xFF0284C7), size: 18),
                                SizedBox(width: 8),
                                Text('Setliste ändern'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'unlink',
                            child: Row(
                              children: [
                                Icon(Icons.link_off_rounded, color: AppTheme.rose, size: 18),
                                SizedBox(width: 8),
                                Text('Zuweisung lösen', style: TextStyle(color: AppTheme.rose)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const Icon(Icons.playlist_add_rounded, size: 18, color: AppTheme.darkTextMuted),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Noch keine Setliste zugewiesen',
                          style: TextStyle(fontSize: 12, color: AppTheme.darkTextMuted),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0284C7),
                          side: const BorderSide(color: Color(0xFF0284C7)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _showAssignSetlistSheet(app),
                        icon: const Icon(Icons.add_link_rounded, size: 16),
                        label: const Text('Setliste zuweisen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
          ),
        ],
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
            onPressed: _isSyncing ? null : () => _syncSetlistsWithCloud(silent: false),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            _syncSetlistsWithCloud(silent: true),
            _refreshKmAppointments(silent: true),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Konzertmeister Section (if enabled)
            _buildKonzertmeisterSection(isDark),

            // Setlists List or Empty State
            if (_setlists.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkSurface : Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.format_list_bulleted_rounded,
                        size: 40,
                        color: isDark ? AppTheme.darkTextMuted : Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Noch keine eigenen Setlisten',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Erstelle eine neue Setliste oder weise oben einem Auftritt eine zu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _createNewSetlist,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Erste Setlist anlegen'),
                    ),
                  ],
                ),
              )
            else
              ..._setlists.map((setlist) {
                final playableSongs = setlist.items.where((i) => !i.isIntermission).length;
                final monthStr = DateFormat('MMM', 'de_DE').format(setlist.date).toUpperCase();
                final dayStr = DateFormat('dd').format(setlist.date);

                // Check if linked to a Konzertmeister appointment
                final linkedAppointmentId = _kmAssignments.entries
                    .where((e) => e.value == setlist.id)
                    .map((e) => e.key)
                    .firstOrNull;
                final linkedAppointment = linkedAppointmentId != null
                    ? _kmAppointments.where((a) => a.id == linkedAppointmentId).firstOrNull
                    : null;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Material(
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
                                      if (linkedAppointment != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.event_available_rounded, size: 12, color: Color(0xFF0284C7)),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Auftritt: ${linkedAppointment.dateString}',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF0284C7),
                                                ),
                                              ),
                                            ],
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
                  ),
                );
              }),
            const SizedBox(height: 60), // Extra space for FAB
          ],
        ),
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
