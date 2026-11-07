import 'package:flutter/material.dart';
import '../../models/musician_profile.dart';
import '../../models/song.dart';
import '../../services/voice_matcher.dart';
import '../theme/app_theme.dart';

class InstrumentFilterSheet extends StatefulWidget {
  final MusicianProfile currentProfile;
  final List<Song> allSongs;
  final bool onlyMyVoice;
  final Function(MusicianProfile updatedProfile, bool onlyMyVoice, bool savePermanently) onApply;

  const InstrumentFilterSheet({
    super.key,
    required this.currentProfile,
    required this.allSongs,
    required this.onlyMyVoice,
    required this.onApply,
  });

  @override
  State<InstrumentFilterSheet> createState() => _InstrumentFilterSheetState();
}

class _InstrumentFilterSheetState extends State<InstrumentFilterSheet> {
  late String _selectedInstrument;
  late int _selectedVoice;
  late String _selectedKey;
  late String _selectedPercussionInstrument;
  late bool _onlyMyVoice;
  bool _saveAsDefault = false;

  @override
  void initState() {
    super.initState();
    _selectedInstrument = widget.currentProfile.instrument;
    _selectedVoice = widget.currentProfile.voiceNumber;
    _selectedKey = widget.currentProfile.keyOrClef;
    final perc = widget.currentProfile.percussionInstrument;
    _selectedPercussionInstrument = perc.isEmpty
        ? 'Alle'
        : (perc == 'Percussion' ? 'Schlagzeug' : perc);
    _onlyMyVoice = widget.onlyMyVoice;
  }

  @override
  Widget build(BuildContext context) {
    // Dynamically discover all instruments from cloud library!
    final dynamicInstruments = VoiceMatcher.getAvailableInstruments(widget.allSongs);
    final availableInstruments = dynamicInstruments.isNotEmpty
        ? dynamicInstruments
        : MusicianProfile.standardInstruments;

    // If current selected instrument is not in list, add it
    final displayInstruments = [
      ...availableInstruments,
      if (!availableInstruments.contains(_selectedInstrument)) _selectedInstrument,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grab Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tune_rounded, color: AppTheme.primaryLight, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Instrument & Stimme wählen',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkTextPrimary,
                        ),
                      ),
                      Text(
                        'Filtert Noten nach deinem Register',
                        style: TextStyle(fontSize: 12, color: AppTheme.darkTextSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.darkTextMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Instrument Section (Dynamic from Nextcloud)
            Row(
              children: [
                const Text(
                  'INSTRUMENT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: AppTheme.darkTextSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.emerald.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${displayInstruments.length} in Cloud gefunden',
                    style: const TextStyle(fontSize: 10, color: AppTheme.emerald, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: displayInstruments.map((inst) {
                final isSelected = _selectedInstrument.toLowerCase() == inst.toLowerCase();
                return ChoiceChip(
                  label: Text(inst),
                  selected: isSelected,
                  selectedColor: AppTheme.primary,
                  backgroundColor: AppTheme.darkCard,
                  side: BorderSide(
                    color: isSelected ? AppTheme.primaryLight : AppTheme.darkBorder,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : AppTheme.darkTextPrimary,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      final def = MusicianProfile.getDefinition(inst);
                      var newKey = _selectedKey;
                      if (def.validKeys.isEmpty) {
                        newKey = '';
                      } else if (newKey.isNotEmpty && !def.validKeys.any((k) => k.key.toLowerCase() == newKey.toLowerCase())) {
                        newKey = def.defaultKey;
                      }

                      var newVoice = _selectedVoice;
                      if (newVoice != 0 && !def.validVoices.contains(newVoice)) {
                        newVoice = def.defaultVoice;
                      }

                      setState(() {
                        _selectedInstrument = inst;
                        _selectedKey = newKey;
                        _selectedVoice = newVoice;
                      });
                    }
                  },
                );
              }).toList(),
            ),

            // Percussion Sub-Instrument Section (only shown when Percussion is selected)
            if (_selectedInstrument == 'Percussion') ...[
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(Icons.album_rounded, size: 16, color: AppTheme.primaryLight),
                  SizedBox(width: 6),
                  Text(
                    'GESPIELTES SCHLAGWERK-INSTRUMENT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: AppTheme.primaryLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: MusicianProfile.percussionInstruments.map((sub) {
                    final isSelected = _selectedPercussionInstrument.toLowerCase() == sub.toLowerCase();
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(sub == 'Alle' ? 'Alle / Flexibel' : sub),
                        selected: isSelected,
                        selectedColor: AppTheme.primary,
                        backgroundColor: AppTheme.darkCard,
                        side: BorderSide(
                          color: isSelected ? AppTheme.primaryLight : AppTheme.darkBorder,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : AppTheme.darkTextPrimary,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedPercussionInstrument = sub;
                            });
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Voice Number Section
            Builder(
              builder: (context) {
                final validVoices = MusicianProfile.getValidVoices(_selectedInstrument);
                final voiceList = [
                  (0, 'Alle'),
                  ...validVoices.where((v) => v > 0).map((v) => (v, '$v. Stimme')),
                ];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'STIMMEN-NUMMER',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: AppTheme.darkTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: voiceList.map((v) {
                          final isSelected = _selectedVoice == v.$1;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(v.$2),
                              selected: isSelected,
                              selectedColor: AppTheme.primary,
                              backgroundColor: AppTheme.darkCard,
                              side: BorderSide(
                                color: isSelected ? AppTheme.primaryLight : AppTheme.darkBorder,
                              ),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Colors.white : AppTheme.darkTextPrimary,
                              ),
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _selectedVoice = v.$1;
                                  });
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),

            // Key / Clef Section (only shown if instrument has valid keys!)
            Builder(
              builder: (context) {
                final validKeys = MusicianProfile.getValidKeys(_selectedInstrument);
                if (validKeys.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'STIMMUNG / SCHLÜSSEL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: AppTheme.darkTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          if (validKeys.length > 1)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: const Text('Alle'),
                                selected: _selectedKey.isEmpty,
                                selectedColor: AppTheme.primary,
                                backgroundColor: AppTheme.darkCard,
                                side: BorderSide(
                                  color: _selectedKey.isEmpty ? AppTheme.primaryLight : AppTheme.darkBorder,
                                ),
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: _selectedKey.isEmpty ? FontWeight.bold : FontWeight.normal,
                                  color: _selectedKey.isEmpty ? Colors.white : AppTheme.darkTextPrimary,
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedKey = '';
                                    });
                                  }
                                },
                              ),
                            ),
                          ...validKeys.map((k) {
                            final isSelected = _selectedKey.toLowerCase() == k.key.toLowerCase();
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(k.label),
                                selected: isSelected,
                                selectedColor: AppTheme.primary,
                                backgroundColor: AppTheme.darkCard,
                                side: BorderSide(
                                  color: isSelected ? AppTheme.primaryLight : AppTheme.darkBorder,
                                ),
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.white : AppTheme.darkTextPrimary,
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedKey = k.key;
                                    });
                                  }
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),
            const Divider(color: AppTheme.darkBorder),
            const SizedBox(height: 8),

            // Only My Voice Switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Nur meine Stimme anzeigen',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.darkTextPrimary),
              ),
              subtitle: const Text(
                'Stücke ohne dieses Register ausblenden',
                style: TextStyle(fontSize: 12, color: AppTheme.darkTextSecondary),
              ),
              value: _onlyMyVoice,
              activeThumbColor: AppTheme.primaryLight,
              onChanged: (val) => setState(() => _onlyMyVoice = val),
            ),

            // Save Permanently Switch
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Als mein Standard-Profil festlegen',
                style: TextStyle(fontSize: 14, color: AppTheme.darkTextPrimary),
              ),
              subtitle: const Text(
                'Dauerhaft in den Einstellungen speichern',
                style: TextStyle(fontSize: 12, color: AppTheme.darkTextSecondary),
              ),
              value: _saveAsDefault,
              activeColor: AppTheme.primaryLight,
              onChanged: (val) => setState(() => _saveAsDefault = val ?? false),
            ),

            const SizedBox(height: 18),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.darkTextSecondary,
                      side: const BorderSide(color: AppTheme.darkBorder),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      final updatedProfile = widget.currentProfile.copyWith(
                        instrument: _selectedInstrument,
                        voiceNumber: _selectedVoice,
                        keyOrClef: _selectedKey,
                        percussionInstrument: _selectedInstrument == 'Percussion'
                            ? _selectedPercussionInstrument
                            : '',
                      );
                      widget.onApply(updatedProfile, _onlyMyVoice, _saveAsDefault);
                      Navigator.pop(context);
                    },
                    child: const Text('Filter anwenden', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
