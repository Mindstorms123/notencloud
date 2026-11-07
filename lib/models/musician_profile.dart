/// Represents a musician's configured profile (instrument, voice, key/clef)
class MusicianProfile {
  final String instrument;
  final int voiceNumber; // 1 for 1. Stimme, 2 for 2. Stimme, etc. (0 if not applicable)
  final String keyOrClef; // e.g. "Bb", "C", "Eb", "F", "Bass", "Treble"
  final String customVoiceName; // Optional custom name

  const MusicianProfile({
    required this.instrument,
    this.voiceNumber = 1,
    this.keyOrClef = '',
    this.customVoiceName = '',
  });

  /// Default profile when starting the app for the first time
  factory MusicianProfile.defaultProfile() {
    return const MusicianProfile(
      instrument: 'Trompete',
      voiceNumber: 1,
      keyOrClef: 'Bb',
    );
  }

  String get displayName {
    if (customVoiceName.isNotEmpty) return customVoiceName;
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
      };

  factory MusicianProfile.fromJson(Map<String, dynamic> json) {
    return MusicianProfile(
      instrument: json['instrument'] as String? ?? 'Trompete',
      voiceNumber: json['voiceNumber'] as int? ?? 1,
      keyOrClef: json['keyOrClef'] as String? ?? '',
      customVoiceName: json['customVoiceName'] as String? ?? '',
    );
  }

  MusicianProfile copyWith({
    String? instrument,
    int? voiceNumber,
    String? keyOrClef,
    String? customVoiceName,
  }) {
    return MusicianProfile(
      instrument: instrument ?? this.instrument,
      voiceNumber: voiceNumber ?? this.voiceNumber,
      keyOrClef: keyOrClef ?? this.keyOrClef,
      customVoiceName: customVoiceName ?? this.customVoiceName,
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
}
