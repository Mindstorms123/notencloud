/// Represents a musician's configured profile (instrument, voice, key/clef)
class MusicianProfile {
  final String instrument;
  final int voiceNumber; // 1 for 1. Stimme, 2 for 2. Stimme, etc. (0 if not applicable)
  final String keyOrClef; // e.g. "Bb", "C", "Eb", "F", "Bass", "Treble"
  final String customVoiceName; // Optional custom name
  final String percussionInstrument; // e.g. "Alle", "Schlagzeug", "Pauken", "Mallets", "Percussion"

  const MusicianProfile({
    required this.instrument,
    this.voiceNumber = 1,
    this.keyOrClef = '',
    this.customVoiceName = '',
    this.percussionInstrument = '',
  });

  static const List<String> percussionInstruments = [
    'Alle',
    'Schlagzeug',
    'Pauken',
    'Mallets',
  ];

  /// Default profile when starting the app for the first time
  factory MusicianProfile.defaultProfile() {
    return const MusicianProfile(
      instrument: 'Trompete',
      voiceNumber: 1,
      keyOrClef: 'Bb',
      percussionInstrument: '',
    );
  }

  String get displayName {
    if (customVoiceName.isNotEmpty) return customVoiceName;
    if (instrument == 'Percussion') {
      if (percussionInstrument.isNotEmpty && percussionInstrument != 'Alle') {
        final buffer = StringBuffer('Percussion ($percussionInstrument)');
        if (voiceNumber > 0) buffer.write(' $voiceNumber');
        return buffer.toString();
      }
      if (voiceNumber > 0) return 'Percussion $voiceNumber';
      return 'Percussion';
    }
    final buffer = StringBuffer(instrument);
    if (voiceNumber > 0) buffer.write(' $voiceNumber');
    if (keyOrClef.isNotEmpty) buffer.write(' ($keyOrClef)');
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'instrument': instrument,
        'voiceNumber': voiceNumber,
        'keyOrClef': keyOrClef,
        'customVoiceName': customVoiceName,
        'percussionInstrument': percussionInstrument,
      };

  factory MusicianProfile.fromJson(Map<String, dynamic> json) {
    var perc = json['percussionInstrument'] as String? ?? '';
    if (perc == 'Percussion') perc = 'Schlagzeug';
    return MusicianProfile(
      instrument: json['instrument'] as String? ?? 'Trompete',
      voiceNumber: json['voiceNumber'] as int? ?? 1,
      keyOrClef: json['keyOrClef'] as String? ?? '',
      customVoiceName: json['customVoiceName'] as String? ?? '',
      percussionInstrument: perc,
    );
  }

  MusicianProfile copyWith({
    String? instrument,
    int? voiceNumber,
    String? keyOrClef,
    String? customVoiceName,
    String? percussionInstrument,
  }) {
    return MusicianProfile(
      instrument: instrument ?? this.instrument,
      voiceNumber: voiceNumber ?? this.voiceNumber,
      keyOrClef: keyOrClef ?? this.keyOrClef,
      customVoiceName: customVoiceName ?? this.customVoiceName,
      percussionInstrument: percussionInstrument ?? this.percussionInstrument,
    );
  }

  /// List of standard instruments for quick selection
  static const List<String> standardInstruments = [
    'Partitur',
    'Direktion',
    'Flöte',
    'Piccoloflöte',
    'Oboe',
    'Fagott',
    'Klarinette',
    'Es-Klarinette',
    'Bassklarinette',
    'Altsaxophon',
    'Tenorsaxophon',
    'Baritonsaxophon',
    'Trompete',
    'Flügelhorn',
    'Waldhorn',
    'Posaune',
    'Tenorhorn',
    'Bariton',
    'Euphonium',
    'Tuba',
    'Percussion',
    'Klavier',
    'E-Bass',
    'Violine',
    'Viola',
    'Violoncello',
    'Kontrabass',
  ];

  static const List<String> standardKeys = [
    'C',
    'Bb',
    'Eb',
    'F',
    'Bass',
    'Violin',
  ];

  static const Map<String, InstrumentDefinition> _instrumentDefinitions = {
    'Trompete': InstrumentDefinition(
      name: 'Trompete',
      validKeys: [InstrumentKeyOption('Bb', 'in B'), InstrumentKeyOption('C', 'in C')],
      defaultKey: 'Bb',
      validVoices: [1, 2, 3, 4],
    ),
    'Flügelhorn': InstrumentDefinition(
      name: 'Flügelhorn',
      validKeys: [InstrumentKeyOption('Bb', 'in B'), InstrumentKeyOption('C', 'in C')],
      defaultKey: 'Bb',
      validVoices: [1, 2],
    ),
    'Kornett': InstrumentDefinition(
      name: 'Kornett',
      validKeys: [InstrumentKeyOption('Bb', 'in B')],
      defaultKey: 'Bb',
      validVoices: [1, 2],
    ),
    'Klarinette': InstrumentDefinition(
      name: 'Klarinette',
      validKeys: [InstrumentKeyOption('Bb', 'in B'), InstrumentKeyOption('C', 'in C')],
      defaultKey: 'Bb',
      validVoices: [1, 2, 3, 4],
    ),
    'Es-Klarinette': InstrumentDefinition(
      name: 'Es-Klarinette',
      validKeys: [InstrumentKeyOption('Eb', 'in Es')],
      defaultKey: 'Eb',
      validVoices: [1],
    ),
    'Bassklarinette': InstrumentDefinition(
      name: 'Bassklarinette',
      validKeys: [InstrumentKeyOption('Bb', 'in B')],
      defaultKey: 'Bb',
      validVoices: [1],
    ),
    'Altsaxophon': InstrumentDefinition(
      name: 'Altsaxophon',
      validKeys: [InstrumentKeyOption('Eb', 'in Es')],
      defaultKey: 'Eb',
      validVoices: [1, 2],
    ),
    'Tenorsaxophon': InstrumentDefinition(
      name: 'Tenorsaxophon',
      validKeys: [InstrumentKeyOption('Bb', 'in B')],
      defaultKey: 'Bb',
      validVoices: [1, 2],
    ),
    'Baritonsaxophon': InstrumentDefinition(
      name: 'Baritonsaxophon',
      validKeys: [InstrumentKeyOption('Eb', 'in Es')],
      defaultKey: 'Eb',
      validVoices: [1],
    ),
    'Sopransaxophon': InstrumentDefinition(
      name: 'Sopransaxophon',
      validKeys: [InstrumentKeyOption('Bb', 'in B')],
      defaultKey: 'Bb',
      validVoices: [1],
    ),
    'Waldhorn': InstrumentDefinition(
      name: 'Waldhorn',
      validKeys: [InstrumentKeyOption('F', 'in F'), InstrumentKeyOption('Eb', 'in Es')],
      defaultKey: 'F',
      validVoices: [1, 2, 3, 4],
    ),
    'Tenorhorn': InstrumentDefinition(
      name: 'Tenorhorn',
      validKeys: [InstrumentKeyOption('Bb', 'in B'), InstrumentKeyOption('C', 'in C')],
      defaultKey: 'Bb',
      validVoices: [1, 2, 3],
    ),
    'Bariton': InstrumentDefinition(
      name: 'Bariton',
      validKeys: [InstrumentKeyOption('C', 'in C (Bass)'), InstrumentKeyOption('Bb', 'in B (Violin)')],
      defaultKey: 'C',
      validVoices: [1, 2],
    ),
    'Euphonium': InstrumentDefinition(
      name: 'Euphonium',
      validKeys: [InstrumentKeyOption('C', 'in C (Bass)'), InstrumentKeyOption('Bb', 'in B (Violin)')],
      defaultKey: 'C',
      validVoices: [1, 2],
    ),
    'Posaune': InstrumentDefinition(
      name: 'Posaune',
      validKeys: [InstrumentKeyOption('C', 'in C (Bass)'), InstrumentKeyOption('Bb', 'in B (Violin)')],
      defaultKey: 'C',
      validVoices: [1, 2, 3],
    ),
    'Bassposaune': InstrumentDefinition(
      name: 'Bassposaune',
      validKeys: [InstrumentKeyOption('C', 'in C (Bass)')],
      defaultKey: 'C',
      validVoices: [1],
    ),
    'Tuba': InstrumentDefinition(
      name: 'Tuba',
      validKeys: [
        InstrumentKeyOption('C', 'in C (Bass)'),
        InstrumentKeyOption('Bb', 'in B'),
        InstrumentKeyOption('Eb', 'in Es'),
      ],
      defaultKey: 'C',
      validVoices: [1, 2],
    ),
    'Flöte': InstrumentDefinition(
      name: 'Flöte',
      validKeys: [InstrumentKeyOption('C', 'in C')],
      defaultKey: 'C',
      validVoices: [1, 2],
    ),
    'Piccoloflöte': InstrumentDefinition(
      name: 'Piccoloflöte',
      validKeys: [InstrumentKeyOption('C', 'in C')],
      defaultKey: 'C',
      validVoices: [1],
    ),
    'Oboe': InstrumentDefinition(
      name: 'Oboe',
      validKeys: [InstrumentKeyOption('C', 'in C')],
      defaultKey: 'C',
      validVoices: [1, 2],
    ),
    'Fagott': InstrumentDefinition(
      name: 'Fagott',
      validKeys: [InstrumentKeyOption('C', 'in C (Bass)')],
      defaultKey: 'C',
      validVoices: [1, 2],
    ),
    'Percussion': InstrumentDefinition(
      name: 'Percussion',
      validKeys: [],
      defaultKey: '',
      validVoices: [0, 1, 2],
      defaultVoice: 0,
    ),
    'Partitur': InstrumentDefinition(
      name: 'Partitur',
      validKeys: [],
      defaultKey: '',
      validVoices: [0],
      defaultVoice: 0,
    ),
    'Direktion': InstrumentDefinition(
      name: 'Direktion',
      validKeys: [],
      defaultKey: '',
      validVoices: [0],
      defaultVoice: 0,
    ),
    'Klavier': InstrumentDefinition(
      name: 'Klavier',
      validKeys: [InstrumentKeyOption('C', 'in C')],
      defaultKey: 'C',
      validVoices: [0],
      defaultVoice: 0,
    ),
    'E-Bass': InstrumentDefinition(
      name: 'E-Bass',
      validKeys: [InstrumentKeyOption('C', 'in C (Bass)')],
      defaultKey: 'C',
      validVoices: [1],
    ),
    'Kontrabass': InstrumentDefinition(
      name: 'Kontrabass',
      validKeys: [InstrumentKeyOption('C', 'in C (Bass)')],
      defaultKey: 'C',
      validVoices: [1],
    ),
    'Violine': InstrumentDefinition(
      name: 'Violine',
      validKeys: [InstrumentKeyOption('C', 'in C')],
      defaultKey: 'C',
      validVoices: [1, 2],
    ),
    'Viola': InstrumentDefinition(
      name: 'Viola',
      validKeys: [InstrumentKeyOption('C', 'in C')],
      defaultKey: 'C',
      validVoices: [1],
    ),
    'Violoncello': InstrumentDefinition(
      name: 'Violoncello',
      validKeys: [InstrumentKeyOption('C', 'in C (Bass)')],
      defaultKey: 'C',
      validVoices: [1],
    ),
  };

  static InstrumentDefinition getDefinition(String instrument) {
    return _instrumentDefinitions[instrument] ??
        const InstrumentDefinition(
          name: '',
          validKeys: [
            InstrumentKeyOption('Bb', 'in B'),
            InstrumentKeyOption('C', 'in C'),
            InstrumentKeyOption('Eb', 'in Es'),
            InstrumentKeyOption('F', 'in F'),
          ],
          defaultKey: 'Bb',
          validVoices: [1, 2, 3, 4],
          defaultVoice: 1,
        );
  }

  static List<InstrumentKeyOption> getValidKeys(String instrument) {
    return getDefinition(instrument).validKeys;
  }

  static List<int> getValidVoices(String instrument) {
    return getDefinition(instrument).validVoices;
  }

  static String getDefaultKey(String instrument) {
    return getDefinition(instrument).defaultKey;
  }

  static int getDefaultVoice(String instrument) {
    return getDefinition(instrument).defaultVoice;
  }
}

class InstrumentKeyOption {
  final String key;
  final String label;

  const InstrumentKeyOption(this.key, this.label);
}

class InstrumentDefinition {
  final String name;
  final List<InstrumentKeyOption> validKeys;
  final String defaultKey;
  final List<int> validVoices;
  final int defaultVoice;

  const InstrumentDefinition({
    required this.name,
    required this.validKeys,
    required this.defaultKey,
    this.validVoices = const [1, 2, 3, 4],
    this.defaultVoice = 1,
  });
}
