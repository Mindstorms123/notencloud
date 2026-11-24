import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/musician_profile.dart';
import '../../models/song.dart';
import '../../services/storage_service.dart';
import '../../services/voice_matcher.dart';
import '../theme/app_theme.dart';

/// Lädt das Notenarchiv und meldet den Fortschritt (aktuell, gesamt).
typedef LibraryLoader = Future<List<Song>> Function(void Function(int current, int total) onProgress);

/// Führung nach der ersten Anmeldung.
///
/// Geht in vier Schritten durch das, was sonst in den Einstellungen gesucht
/// werden müsste: Notenarchiv laden, Instrument und Stimme wählen, Startordner
/// festlegen, und zum Schluss die wichtigsten Handgriffe.
class FirstRunGuide extends StatefulWidget {
  final StorageService storageService;
  final LibraryLoader? loadLibrary;

  const FirstRunGuide({super.key, required this.storageService, this.loadLibrary});

  /// Zeigt die Führung, solange noch kein Profil gespeichert wurde.
  static Future<void> showIfNeeded(
    BuildContext context,
    StorageService storageService, {
    LibraryLoader? loadLibrary,
  }) async {
    if (storageService.hasSavedProfile()) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FirstRunGuide(storageService: storageService, loadLibrary: loadLibrary),
    );
  }

  @override
  State<FirstRunGuide> createState() => _FirstRunGuideState();
}

enum _Step { library, profile, category, tips }

class _FirstRunGuideState extends State<FirstRunGuide> {
  _Step _step = _Step.library;

  // Schritt 1: Notenarchiv
  int _loaded = 0;
  int _total = 0;
  String? _libraryError;

  // Schritt 2: Profil
  late MusicianProfile _profile;
  List<String> _instruments = const [];

  // Schritt 3: Startordner
  List<String> _categories = const [];
  String _category = 'Alle';

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.storageService.getProfile();
    if (widget.loadLibrary != null && widget.storageService.getCachedSongs().isEmpty) {
      _loadLibrary();
    } else {
      _enterProfileStep();
    }
  }

  Future<void> _loadLibrary() async {
    setState(() {
      _step = _Step.library;
      _libraryError = null;
    });
    try {
      final songs = await widget.loadLibrary!((current, total) {
        if (mounted) {
          setState(() {
            _loaded = current;
            _total = total;
          });
        }
      });
      await widget.storageService.saveCachedSongs(songs);
      if (mounted) _enterProfileStep();
    } catch (e) {
      if (mounted) {
        setState(() {
          _libraryError = '$e';
        });
      }
    }
  }

  void _enterProfileStep() {
    final songs = widget.storageService.getCachedSongs();
    final available = VoiceMatcher.getAvailableInstruments(songs);
    final categories = songs.map((s) => s.category).where((c) => c.isNotEmpty).toSet().toList()..sort();
    setState(() {
      _instruments = [
        ...available,
        if (!available.contains(_profile.instrument)) _profile.instrument,
      ];
      _categories = categories;
      _category = categories.contains('Aktuelle Noten')
          ? 'Aktuelle Noten'
          : (categories.isNotEmpty ? categories.first : 'Alle');
      _step = _Step.profile;
    });
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

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    await widget.storageService.saveProfile(_profile);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      // Bei nur einem Ordner gibt es nichts zu wählen.
      _step = _categories.length > 1 ? _Step.category : _Step.tips;
    });
  }

  Future<void> _saveCategory() async {
    setState(() => _isSaving = true);
    await widget.storageService.setDefaultCategory(_category);
    await widget.storageService.setLastActiveCategory(_category);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _step = _Step.tips;
    });
  }

  int get _stepNumber => switch (_step) {
        _Step.library => 1,
        _Step.profile => 2,
        _Step.category => 3,
        _Step.tips => 4,
      };

  String get _title => switch (_step) {
        _Step.library => 'Notenarchiv laden',
        _Step.profile => 'Was spielst du?',
        _Step.category => 'Womit soll die App starten?',
        _Step.tips => 'Fertig eingerichtet',
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Schritt $_stepNumber von 4',
              style: const TextStyle(fontSize: 12, color: AppTheme.darkTextMuted, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(_title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: switch (_step) {
              _Step.library => _buildLibraryStep(),
              _Step.profile => _buildProfileStep(),
              _Step.category => _buildCategoryStep(),
              _Step.tips => _buildTipsStep(),
            },
          ),
        ),
        actions: _buildActions(),
      ),
    );
  }

  List<Widget> _buildActions() {
    switch (_step) {
      case _Step.library:
        return [
          if (_libraryError != null)
            TextButton(onPressed: _loadLibrary, child: const Text('Erneut versuchen')),
          TextButton(
            onPressed: _enterProfileStep,
            child: Text(_libraryError != null ? 'Ohne Archiv weiter' : 'Überspringen'),
          ),
        ];
      case _Step.profile:
        return [
          FilledButton(onPressed: _isSaving ? null : _saveProfile, child: const Text('Weiter')),
        ];
      case _Step.category:
        return [
          FilledButton(onPressed: _isSaving ? null : _saveCategory, child: const Text('Weiter')),
        ];
      case _Step.tips:
        return [
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Loslegen'),
          ),
        ];
    }
  }

  static const _bodyStyle = TextStyle(fontSize: 13, color: AppTheme.darkTextSecondary, height: 1.4);

  Widget _buildLibraryStep() {
    if (_libraryError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Das Notenarchiv konnte nicht geladen werden. Du kannst es erneut versuchen oder ohne Archiv weitermachen und später im Bereich „Noten“ synchronisieren.',
            style: _bodyStyle,
          ),
          const SizedBox(height: 12),
          Text(_libraryError!, style: const TextStyle(fontSize: 12, color: AppTheme.rose)),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Die App liest jetzt einmal das Notenarchiv deines Vereins aus der Nextcloud. Danach kennt sie alle Stücke und Stimmen.',
          style: _bodyStyle,
        ),
        const SizedBox(height: 18),
        LinearProgressIndicator(
          value: _total > 0 ? (_loaded / _total).clamp(0.0, 1.0) : null,
          color: AppTheme.primaryLight,
          backgroundColor: AppTheme.darkBorder,
        ),
        const SizedBox(height: 10),
        Text(
          _total > 0 ? '$_loaded von $_total Stücken gelesen' : 'Verbinde mit der Nextcloud...',
          style: const TextStyle(fontSize: 12, color: AppTheme.darkTextMuted),
        ),
      ],
    );
  }

  Widget _buildProfileStep() {
    final validVoices = MusicianProfile.getValidVoices(_profile.instrument);
    final voice = validVoices.contains(_profile.voiceNumber) ? _profile.voiceNumber : validVoices.first;
    final validKeys = MusicianProfile.getValidKeys(_profile.instrument);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Wähle dein Instrument und deine Stimme. Die App öffnet dann bei jedem Stück automatisch die passenden Noten.',
          style: _bodyStyle,
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
          items: _instruments.map((inst) => DropdownMenuItem(value: inst, child: Text(inst))).toList(),
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
              .map((v) => DropdownMenuItem(value: v, child: Text(v == 0 ? 'Keine / Alle' : '$v. Stimme')))
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _profile = _profile.copyWith(voiceNumber: val));
          },
        ),
        if (validKeys.isNotEmpty) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey('setup_key_${_profile.instrument}_${_profile.keyOrClef}'),
            initialValue:
                validKeys.any((k) => k.key == _profile.keyOrClef) ? _profile.keyOrClef : validKeys.first.key,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Stimmung'),
            items: validKeys.map((k) => DropdownMenuItem(value: k.key, child: Text(k.label))).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _profile = _profile.copyWith(keyOrClef: val));
            },
          ),
        ],
        if (_profile.instrument == 'Percussion') ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey('setup_perc_${_profile.percussionInstrument}'),
            initialValue: _profile.percussionInstrument.isEmpty ? 'Alle' : _profile.percussionInstrument,
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
              if (val != null) setState(() => _profile = _profile.copyWith(percussionInstrument: val));
            },
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryStep() {
    final options = ['Alle', ..._categories];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Euer Archiv hat mehrere Ordner. Wähle, welchen die App beim Öffnen zeigt. Wechseln kannst du jederzeit über die Knöpfe oben im Bereich „Noten“.',
          style: _bodyStyle,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option),
                selected: option == _category,
                selectedColor: AppTheme.primary,
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: option == _category ? FontWeight.bold : FontWeight.w500,
                  color: option == _category ? Colors.white : AppTheme.darkTextPrimary,
                ),
                onSelected: (_) => setState(() => _category = option),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTipsStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Du spielst ${_profile.displayName}. Drei Dinge, die du kennen solltest:', style: _bodyStyle),
        const SizedBox(height: 14),
        const _Tip(
          icon: Icons.download_for_offline_rounded,
          title: 'Noten für die Bühne laden',
          text: 'Im Bereich „Noten“ lädt der Knopf mit dem Pfeil nach unten alle deine Stimmen aufs Gerät. Danach brauchst du kein Internet mehr.',
        ),
        const _Tip(
          icon: Icons.queue_music_rounded,
          title: 'Setlisten und Bühnenmodus',
          text: 'Im Bereich „Setlisten“ findest du die Programme für Auftritte. Dort blätterst du Stück für Stück durch deine Noten.',
        ),
        const _Tip(
          icon: Icons.settings_rounded,
          title: 'Später etwas ändern',
          text: 'Instrument, Startordner, Fußpedal und Kalender stehen im Bereich „Einstellungen“.',
        ),
        if (kIsWeb)
          const _Tip(
            icon: Icons.add_to_home_screen_rounded,
            title: 'Auf den Home-Bildschirm legen',
            text: 'iPad: In Safari auf Teilen und dann „Zum Home-Bildschirm“. So startet die App wie eine normale App, auch ohne Internet.',
          ),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _Tip({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppTheme.primaryLight),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(fontSize: 13, color: AppTheme.darkTextSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
