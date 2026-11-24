import 'package:flutter/material.dart';
import '../../models/musician_profile.dart';
import '../../services/storage_service.dart';
import '../../services/voice_matcher.dart';
import '../theme/app_theme.dart';

/// Abfrage von Instrument und Stimme nach der ersten Anmeldung.
///
/// Ohne diese Angabe kann die App nicht wissen, welche Stimme sie je Stück
/// öffnen soll, und würde stillschweigend das Standardprofil verwenden.
class ProfileSetupDialog extends StatefulWidget {
  final StorageService storageService;

  const ProfileSetupDialog({super.key, required this.storageService});

  /// Zeigt den Dialog, solange noch kein Profil gespeichert wurde.
  static Future<void> showIfNeeded(BuildContext context, StorageService storageService) async {
    if (storageService.hasSavedProfile()) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProfileSetupDialog(storageService: storageService),
    );
  }

  @override
  State<ProfileSetupDialog> createState() => _ProfileSetupDialogState();
}

class _ProfileSetupDialogState extends State<ProfileSetupDialog> {
  late MusicianProfile _profile;
  late List<String> _instruments;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.storageService.getProfile();
    final available = VoiceMatcher.getAvailableInstruments(widget.storageService.getCachedSongs());
    _instruments = [
      ...available,
      if (!available.contains(_profile.instrument)) _profile.instrument,
    ];
  }

  void _selectInstrument(String instrument) {
    final def = MusicianProfile.getDefinition(instrument);
    var key = _profile.keyOrClef;
    if (def.validKeys.isEmpty) {
      key = '';
    } else if (!def.validKeys.any((k) => k.key == key)) {
      key = def.defaultKey;
    }
    final voice = def.validVoices.contains(_profile.voiceNumber) ? _profile.voiceNumber : def.defaultVoice;
    setState(() {
      _profile = _profile.copyWith(
        instrument: instrument,
        keyOrClef: key,
        voiceNumber: voice,
        percussionInstrument: instrument == 'Percussion' ? 'Alle' : '',
      );
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await widget.storageService.saveProfile(_profile);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final validVoices = MusicianProfile.getValidVoices(_profile.instrument);
    final voice = validVoices.contains(_profile.voiceNumber) ? _profile.voiceNumber : validVoices.first;
    final validKeys = MusicianProfile.getValidKeys(_profile.instrument);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.person_rounded, color: AppTheme.emerald, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Was spielst du?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wähle dein Instrument und deine Stimme. Die App öffnet dann bei jedem Stück automatisch die passenden Noten.',
                  style: TextStyle(fontSize: 13, color: AppTheme.darkTextSecondary, height: 1.4),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  key: ValueKey('setup_inst_${_profile.instrument}'),
                  initialValue: _profile.instrument,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Instrument',
                    prefixIcon: Icon(Icons.music_note_rounded),
                  ),
                  items: _instruments
                      .map((inst) => DropdownMenuItem(value: inst, child: Text(inst)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) _selectInstrument(val);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  key: ValueKey('setup_voice_${_profile.instrument}_$voice'),
                  initialValue: voice,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Stimme'),
                  items: validVoices
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(v == 0 ? 'Keine / Alle' : '$v. Stimme'),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _profile = _profile.copyWith(voiceNumber: val));
                    }
                  },
                ),
                if (validKeys.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey('setup_key_${_profile.instrument}_${_profile.keyOrClef}'),
                    initialValue: validKeys.any((k) => k.key == _profile.keyOrClef)
                        ? _profile.keyOrClef
                        : validKeys.first.key,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Stimmung'),
                    items: validKeys
                        .map((k) => DropdownMenuItem(value: k.key, child: Text(k.label)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _profile = _profile.copyWith(keyOrClef: val));
                      }
                    },
                  ),
                ],
                if (_profile.instrument == 'Percussion') ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey('setup_perc_${_profile.percussionInstrument}'),
                    initialValue:
                        _profile.percussionInstrument.isEmpty ? 'Alle' : _profile.percussionInstrument,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Schlagwerk-Instrument',
                      prefixIcon: Icon(Icons.album_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Alle', child: Text('Alle / Flexibel')),
                      DropdownMenuItem(value: 'Schlagzeug', child: Text('Schlagzeug')),
                      DropdownMenuItem(value: 'Pauken', child: Text('Pauken')),
                      DropdownMenuItem(value: 'Mallets', child: Text('Mallets')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _profile = _profile.copyWith(percussionInstrument: val));
                      }
                    },
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Du kannst das später jederzeit unter Einstellungen › Dein Musiker-Profil ändern.',
                  style: TextStyle(fontSize: 12, color: AppTheme.darkTextMuted, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Speichern und loslegen'),
          ),
        ],
      ),
    );
  }
}
