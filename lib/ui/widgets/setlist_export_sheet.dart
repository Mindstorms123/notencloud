import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/musician_profile.dart';
import '../../models/setlist.dart';
import '../../services/nextcloud_service.dart';
import '../../services/setlist_pdf_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_matcher.dart';
import '../theme/app_theme.dart';

class SetlistExportSheet extends StatefulWidget {
  final Setlist setlist;
  final MusicianProfile currentProfile;
  final StorageService storageService;
  final NextcloudService? nextcloudService;

  const SetlistExportSheet({
    super.key,
    required this.setlist,
    required this.currentProfile,
    required this.storageService,
    this.nextcloudService,
  });

  static Future<void> show(
    BuildContext context, {
    required Setlist setlist,
    required MusicianProfile currentProfile,
    required StorageService storageService,
    NextcloudService? nextcloudService,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SetlistExportSheet(
        setlist: setlist,
        currentProfile: currentProfile,
        storageService: storageService,
        nextcloudService: nextcloudService,
      ),
    );
  }

  @override
  State<SetlistExportSheet> createState() => _SetlistExportSheetState();
}

class _SetlistExportSheetState extends State<SetlistExportSheet> {
  bool _isGeneratingOverview = false;
  bool _isGeneratingAushilfe = false;

  late String _selectedInstrument;
  late int _selectedVoice;
  late String _selectedKey;
  late String _selectedPercussion;

  @override
  void initState() {
    super.initState();
    _selectedInstrument = widget.currentProfile.instrument;
    _selectedVoice = widget.currentProfile.voiceNumber;
    _selectedKey = widget.currentProfile.keyOrClef;
    _selectedPercussion = widget.currentProfile.percussionInstrument;
  }

  MusicianProfile get _aushilfeProfile => MusicianProfile(
        instrument: _selectedInstrument,
        voiceNumber: _selectedVoice,
        keyOrClef: _selectedKey,
        percussionInstrument: _selectedPercussion,
      );

  Future<void> _shareOverviewPdf() async {
    setState(() => _isGeneratingOverview = true);
    try {
      final file = await SetlistPdfService.generateSetlistOverviewPdf(widget.setlist);
      if (mounted) {
        setState(() => _isGeneratingOverview = false);
        Navigator.pop(context); // Close sheet
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'Setliste & Ablaufplan: ${widget.setlist.title}',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingOverview = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppTheme.rose, content: Text('Fehler beim Erstellen der PDF: $e')),
        );
      }
    }
  }

  Future<void> _shareAushilfeBooklet() async {
    setState(() => _isGeneratingAushilfe = true);
    Navigator.pop(context); // Close sheet to show full-screen progress dialog

    int currentPiece = 0;
    int totalPieces = widget.setlist.items.length;
    String statusText = 'Bereite Noten vor...';
    StateSetter? dialogState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          dialogState = setDialogState;
          final progress = totalPieces > 0 ? (currentPiece / totalPieces).clamp(0.0, 1.0) : 0.0;

          return AlertDialog(
            backgroundColor: AppTheme.darkCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.emerald.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_stories_rounded, color: AppTheme.emerald, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Notenheft erstellen',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stimme: ${_aushilfeProfile.displayName}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.emerald, fontSize: 13),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: AppTheme.darkSurface,
                    color: AppTheme.emerald,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  statusText,
                  style: const TextStyle(fontSize: 12, color: AppTheme.darkTextSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      final file = await SetlistPdfService.generateAushilfeBookletPdf(
        setlist: widget.setlist,
        aushilfeProfile: _aushilfeProfile,
        storageService: widget.storageService,
        nextcloudService: widget.nextcloudService,
        onProgress: (current, total, status) {
          currentPiece = current;
          totalPieces = total;
          statusText = status;
          dialogState?.call(() {});
        },
      );

      if (mounted) {
        Navigator.pop(context); // Close progress dialog

        // Show completed dialog with Share & Open options
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.darkCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 24),
                SizedBox(width: 10),
                Text('Notenheft fertig!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Das Notenheft für "${_aushilfeProfile.displayName}" wurde erfolgreich mit allen Stücken als zusammenhängendes PDF erstellt.',
                  style: const TextStyle(fontSize: 13, color: AppTheme.darkTextSecondary),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.darkBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.rose, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.path.split('/').last,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('Ansehen'),
                onPressed: () {
                  Navigator.pop(ctx);
                  OpenFilex.open(file.path);
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.emerald,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Jetzt teilen'),
                onPressed: () {
                  Navigator.pop(ctx);
                  SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(file.path)],
                      text: 'Notenheft für ${_aushilfeProfile.displayName} • ${widget.setlist.title}',
                    ),
                  );
                },
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppTheme.rose, content: Text('Fehler beim Erstellen des Notenhefts: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playableCount = widget.setlist.items.where((i) => !i.isIntermission).length;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
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

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.ios_share_rounded, color: AppTheme.primaryLight, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Setliste teilen & exportieren',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(
                      '${widget.setlist.title} • $playableCount Stücke',
                      style: const TextStyle(fontSize: 12, color: AppTheme.darkTextMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Option 1: Overview PDF Card
          Material(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _isGeneratingOverview ? null : _shareOverviewPdf,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(Icons.picture_as_pdf_rounded, color: AppTheme.amber, size: 24),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Programm / Ablaufplan (PDF)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Übersicht aller Stücke, Pausen & Notizen zum Ausdrucken oder Verschicken.',
                            style: TextStyle(color: AppTheme.darkTextSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isGeneratingOverview)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amber),
                      )
                    else
                      const Icon(Icons.chevron_right_rounded, color: AppTheme.darkTextMuted),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Option 2: Aushilfe Booklet Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(Icons.auto_stories_rounded, color: AppTheme.emerald, size: 24),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Notenheft für Aushilfe (PDF)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Kombiniert Inhaltsverzeichnis & alle Noten dieser Setliste in einer PDF.',
                            style: TextStyle(color: AppTheme.darkTextSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppTheme.darkBorder, height: 1),
                const SizedBox(height: 14),

                const Text(
                  'Stimme für Aushilfe auswählen:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkTextSecondary),
                ),
                const SizedBox(height: 10),

                // Instrument & Voice Selection Row
                Row(
                  children: [
                    // Instrument Dropdown
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.darkBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: VoiceMatcher.knownRealInstruments.contains(_selectedInstrument)
                                ? _selectedInstrument
                                : VoiceMatcher.knownRealInstruments.first,
                            isExpanded: true,
                            dropdownColor: AppTheme.darkCard,
                            items: VoiceMatcher.knownRealInstruments.map((inst) {
                              return DropdownMenuItem(
                                value: inst,
                                child: Text(inst, style: const TextStyle(fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedInstrument = val;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Voice Number Dropdown (if not percussion)
                    if (_selectedInstrument != 'Percussion') ...[
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.darkSurface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.darkBorder),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _selectedVoice,
                              isExpanded: true,
                              dropdownColor: AppTheme.darkCard,
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('Alle', style: TextStyle(fontSize: 13))),
                                DropdownMenuItem(value: 1, child: Text('1. St.', style: TextStyle(fontSize: 13))),
                                DropdownMenuItem(value: 2, child: Text('2. St.', style: TextStyle(fontSize: 13))),
                                DropdownMenuItem(value: 3, child: Text('3. St.', style: TextStyle(fontSize: 13))),
                                DropdownMenuItem(value: 4, child: Text('4. St.', style: TextStyle(fontSize: 13))),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedVoice = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Key Dropdown
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.darkSurface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.darkBorder),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: ['Bb', 'C', 'Es', 'F', ''].contains(_selectedKey)
                                  ? _selectedKey
                                  : '',
                              isExpanded: true,
                              dropdownColor: AppTheme.darkCard,
                              items: const [
                                DropdownMenuItem(value: '', child: Text('–', style: TextStyle(fontSize: 13))),
                                DropdownMenuItem(value: 'Bb', child: Text('in Bb', style: TextStyle(fontSize: 13))),
                                DropdownMenuItem(value: 'C', child: Text('in C', style: TextStyle(fontSize: 13))),
                                DropdownMenuItem(value: 'Es', child: Text('in Es', style: TextStyle(fontSize: 13))),
                                DropdownMenuItem(value: 'F', child: Text('in F', style: TextStyle(fontSize: 13))),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedKey = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Percussion sub-instrument picker
                      Expanded(
                        flex: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.darkSurface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.darkBorder),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: VoiceMatcher.percussionSubInstruments.contains(_selectedPercussion)
                                  ? _selectedPercussion
                                  : 'Alle',
                              isExpanded: true,
                              dropdownColor: AppTheme.darkCard,
                              items: VoiceMatcher.percussionSubInstruments.map((sub) {
                                return DropdownMenuItem(
                                  value: sub,
                                  child: Text(sub, style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedPercussion = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // Button to create and share Aushilfe booklet
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emerald,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isGeneratingAushilfe ? null : _shareAushilfeBooklet,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: Text(
                      'Notenheft für ${_aushilfeProfile.displayName} erstellen & teilen',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
