import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/musician_profile.dart';
import '../../models/setlist.dart';
import '../../services/annotation_service.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
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
  }

  void _loadSetlists() {
    setState(() {
      _setlists = widget.storageService.getLocalSetlists();
      _setlists.sort((a, b) => b.date.compareTo(a.date));
    });
  }

  Future<void> _syncSetlistsWithCloud() async {
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${remoteSetlists.length} Setlisten von Nextcloud synchronisiert!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
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

  void _createNewSetlist() {
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Neue Setlist erstellen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Titel / Anlass',
                  hintText: 'z.B. Sommerfest 2026',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text('Datum: ${DateFormat('dd.MM.yyyy').format(selectedDate)}'),
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
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) return;

                final newSetlist = Setlist.create(
                  title: title,
                  date: selectedDate,
                );

                await widget.storageService.upsertSetlist(newSetlist);
                _loadSetlists();
                if (mounted) {
                  Navigator.pop(ctx);
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
    final dateFormat = DateFormat('dd.MM.yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Setlisten & Auftritte', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Setlisten von Nextcloud laden',
            onPressed: _isSyncing ? null : _syncSetlistsWithCloud,
          ),
        ],
      ),
      body: _setlists.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.format_list_bulleted, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'Noch keine Setlisten vorhanden',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _createNewSetlist,
                    icon: const Icon(Icons.add),
                    label: const Text('Erste Setlist erstellen'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _syncSetlistsWithCloud,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _setlists.length,
                separatorBuilder: (ctx, i) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final setlist = _setlists[index];
                  final playableSongs = setlist.items.where((i) => !i.isIntermission).length;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.12),
                      foregroundColor: Theme.of(context).primaryColor,
                      child: const Icon(Icons.event_note),
                    ),
                    title: Text(
                      setlist.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Row(
                      children: [
                        Text(dateFormat.format(setlist.date)),
                        const SizedBox(width: 8),
                        const Text('•'),
                        const SizedBox(width: 8),
                        Text('$playableSongs Stücke'),
                        if (setlist.isSyncedWithCloud) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.cloud_done, size: 14, color: Colors.green),
                        ],
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () => _openSetlist(setlist),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewSetlist,
        icon: const Icon(Icons.add),
        label: const Text('Neue Setlist'),
      ),
    );
  }
}
