import '../models/musician_profile.dart';
import '../models/song.dart';

class MatchResult {
  final PartFile part;
  final int score; // 0 to 100
  final String reason;

  const MatchResult({
    required this.part,
    required this.score,
    required this.reason,
  });
}

enum MatchQuality {
  exact, // Matches requested voice (or combined voice containing it)
  fallback, // Requested voice does not exist; using available alternative
}

class DetailedMatch {
  final PartFile part;
  final MatchQuality quality;
  final int requestedVoice;
  final int actualVoice;
  final String reason;

  const DetailedMatch({
    required this.part,
    required this.quality,
    required this.requestedVoice,
    required this.actualVoice,
    required this.reason,
  });

  bool get isExact => quality == MatchQuality.exact;
  bool get isFallback => quality == MatchQuality.fallback;
}

class VoiceMatcher {
  /// Normalize a string for comparison (removes umlauts, punctuation, lowercase)
  static String normalize(String input) {
    var s = input.toLowerCase();
    s = s.replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue').replaceAll('ß', 'ss');
    s = s.replaceAll(RegExp(r'[\._\-\+,;]'), ' ');
    return s.trim();
  }

  /// Map common instrument synonyms to a standardized canonical instrument name
  static final Map<String, List<String>> _instrumentAliases = {
    'flöte': ['floete', 'flute', 'querfloete', 'c floete', 'c flöte'],
    'piccoloflöte': ['piccolo', 'piccolofloete', 'picc'],
    'oboe': ['oboe', 'hautbois'],
    'fagott': ['fagott', 'bassoon', 'fagotto'],
    'es-klarinette': ['es klarinette', 'eb clarinet', 'klarinette in es'],
    'klarinette': ['klarinette', 'klarinnete', 'clarinet', 'clarinette', 'b klarinette', 'bb clarinet'],
    'bassklarinette': ['bassklarinette', 'bass clarinet'],
    'sopransaxophon': ['sopran-sax', 'sopransax', 'sopran sax', 'soprano sax', 'soprano saxophone'],
    'altsaxophon': ['altsaxophon', 'altsax', 'alt sax', 'alto saxophone', 'alto sax', 'es altsaxophon'],
    'tenorsaxophon': ['tenorsaxophon', 'tenorsax', 'tenor sax', 'tenor saxophone', 'b tenorsaxophon'],
    'baritonsaxophon': ['baritonsaxophon', 'baritonsax', 'bariton sax', 'baritone sax', 'baritone saxophone'],
    'trompete': ['trompete', 'trompe', 'trumpet', 'trompette', 'b trompete', 'bb trumpet', 'trpt'],
    'flügelhorn': ['fluegelhorn', 'flugelhorn', 'fluegel', 'b fluegelhorn'],
    'kornett': ['kornett', 'cornet', 'cornett'],
    'waldhorn': ['waldhorn', 'horn', 'f horn', 'french horn', 'es horn'],
    'posaune': ['posaune', 'posauen', 'trombone', 'tbne', 'bassposaune', 'tenorposaune'],
    'tenorhorn': ['tenorhorn', 'tenor horn', 'tenorhorn in b'],
    'bariton': ['bariton', 'baritone', 'bariton in b', 'bariton in c'],
    'euphonium': ['euphonium', 'euph'],
    'tuba': ['tuba', 'tuben', 'baesse', 'bässe', 'b tuba', 'c tuba', 'es tuba', 'f tuba', 'sousaphon'],
    'percussion': [
      'percussion', 'perkussion', 'perc', 'perk',
      'schlagzeug', 'drums', 'drum set', 'drumset', 'drum-set', 'batterie', 'snare', 'kleine trommel', 'grosse trommel', 'bass drum',
      'pauken', 'pauke', 'timpani', 'timp', 'kettledrums',
      'mallets', 'mallet', 'mellods', 'mellod',
      'glockenspiel', 'glsp', 'xylophon', 'xylophone', 'xylo', 'marimba', 'marimbaphon', 'vibraphon', 'vibraphone', 'vibes', 'bells', 'orchestra bells', 'chimes', 'tubular bells', 'roehrenglocken', 'schellen',
      'becken', 'cymbals', 'crash', 'ride', 'triangel', 'triangle', 'tambourin', 'tambourine', 'tamburin',
      'conga', 'congas', 'bongo', 'bongos', 'shaker', 'claves', 'castanets', 'kastagnetten', 'tam tam', 'tamtam', 'gong', 'woodblock', 'cowbell', 'kuhglocke',
    ],
    'klavier': ['klavier', 'piano', 'keyboard'],
    'gitarre': ['gitarre', 'guitar', 'e gitarre', 'egitarre', 'akustikgitarre', 'acoustic guitar'],
    'e-bass': ['e bass', 'ebass', 'electric bass', 'bassgitarre'],
    'gesang': ['gesang', 'vocal', 'vocals', 'solo & chor', 'chor', 'voice'],
    'harfe': ['harfe', 'harp'],
    'violine': ['violine', 'geige', 'violin', 'violino'],
    'viola': ['viola', 'bratsche'],
    'violoncello': ['violoncello', 'cello'],
    'kontrabass': ['kontrabass', 'double bass', 'string bass'],
    'partitur': ['partitur', 'patitur', 'patitiur', 'full score', 'score', 'condensed score', 'gesamt', 'stimmen tutti', 'tutti'],
    'direktion': ['direktion', 'direktion in c', 'direktion in b', 'conductor', 'lead sheet'],
  };

  /// Aliases for specific percussion sub-instruments (Schlagzeug, Pauken, Mallets).
  /// Note: Percussion, Perkussion, Drums etc. all map to Schlagzeug!
  static const Map<String, List<String>> percussionSubAliases = {
    'pauken': [
      'pauken', 'pauke', 'timpani', 'timp', 'kettledrums',
    ],
    'mallets': [
      'mallets', 'mallet', 'mellods', 'mellod', 'glockenspiel', 'glsp', 'xylophon', 'xylophone',
      'xylo', 'marimba', 'marimbaphon', 'vibraphon', 'vibraphone', 'vibes', 'bells', 'orchestra bells',
      'chimes', 'tubular bells', 'roehrenglocken', 'schellen',
    ],
    'schlagzeug': [
      'schlagzeug', 'drums', 'drum set', 'drumset', 'drum-set', 'batterie', 'snare', 'kleine trommel',
      'grosse trommel', 'bass drum', 'percussion', 'perkussion', 'perc', 'perk', 'becken', 'cymbals',
      'crash', 'ride', 'triangel', 'triangle', 'tambourin', 'tambourine', 'tamburin', 'conga', 'congas',
      'bongo', 'bongos', 'shaker', 'claves', 'castanets', 'kastagnetten', 'tam tam', 'tamtam',
      'gong', 'woodblock', 'cowbell', 'kuhglocke',
    ],
  };

  /// Detects which specific percussion sub-instrument a part or file name represents.
  /// Parts with "Percussion", "Drums", etc. map to "Schlagzeug".
  static String detectPercussionSubInstrument(String fileName) {
    final norm = normalize(fileName);
    for (final entry in percussionSubAliases.entries) {
      for (final alias in entry.value) {
        if (norm.contains(alias)) {
          switch (entry.key) {
            case 'pauken':
              return 'Pauken';
            case 'mallets':
              return 'Mallets';
            case 'schlagzeug':
              return 'Schlagzeug';
          }
        }
      }
    }
    return 'Schlagzeug';
  }

  /// Canonical display names with correct capitalization and hyphens
  static const Map<String, String> canonicalDisplayNames = {
    'flöte': 'Flöte',
    'piccoloflöte': 'Piccoloflöte',
    'oboe': 'Oboe',
    'fagott': 'Fagott',
    'es-klarinette': 'Es-Klarinette',
    'klarinette': 'Klarinette',
    'bassklarinette': 'Bassklarinette',
    'sopransaxophon': 'Sopransaxophon',
    'altsaxophon': 'Altsaxophon',
    'tenorsaxophon': 'Tenorsaxophon',
    'baritonsaxophon': 'Baritonsaxophon',
    'trompete': 'Trompete',
    'flügelhorn': 'Flügelhorn',
    'kornett': 'Kornett',
    'waldhorn': 'Waldhorn',
    'posaune': 'Posaune',
    'tenorhorn': 'Tenorhorn',
    'bariton': 'Bariton',
    'euphonium': 'Euphonium',
    'tuba': 'Tuba',
    'percussion': 'Percussion',
    'klavier': 'Klavier',
    'gitarre': 'Gitarre',
    'e-bass': 'E-Bass',
    'gesang': 'Gesang',
    'harfe': 'Harfe',
    'violine': 'Violine',
    'viola': 'Viola',
    'violoncello': 'Violoncello',
    'kontrabass': 'Kontrabass',
    'partitur': 'Partitur',
    'direktion': 'Direktion',
  };

  /// Set of verified, genuine orchestral instruments selectable by musicians
  static const Set<String> knownRealInstruments = {
    'Piccoloflöte',
    'Flöte',
    'Oboe',
    'Fagott',
    'Es-Klarinette',
    'Klarinette',
    'Bassklarinette',
    'Sopransaxophon',
    'Altsaxophon',
    'Tenorsaxophon',
    'Baritonsaxophon',
    'Trompete',
    'Flügelhorn',
    'Kornett',
    'Waldhorn',
    'Tenorhorn',
    'Bariton',
    'Euphonium',
    'Posaune',
    'Tuba',
    'E-Bass',
    'Kontrabass',
    'Percussion',
    'Klavier',
    'Gitarre',
    'Gesang',
    'Harfe',
    'Violine',
    'Viola',
    'Violoncello',
  };

  /// Analyzes a PDF file name and detects instrument, voice number, and key.
  /// An optional [instrumentHint] (e.g. from a parent instrument subfolder like "Trumpet")
  /// helps disambiguate files named simply "1. Trumpet.pdf" or "1.pdf".
  static PartFile parsePartFileName(
    String fileName,
    String songId,
    String remotePath, {
    String instrumentHint = '',
  }) {
    final cleanName = fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    final lowerClean = cleanName.toLowerCase();
    final norm = normalize(cleanName);
    final normHint = normalize(instrumentHint);

    // 1. Detect voice numbers
    int voice = 0;
    bool isCombined = false;

    // Check combined patterns on lowerClean: "1-2", "1_2", "1+2", "1 u 2", "1&2", "1/2"
    if (RegExp(r'(?:^|[^0-9])1\s*[-+&_u/]\s*2(?:$|[^0-9])').hasMatch(lowerClean) ||
        RegExp(r'(?:^|[^0-9])3\s*[-+&_u/]\s*4(?:$|[^0-9])').hasMatch(lowerClean)) {
      isCombined = true;
      if (lowerClean.contains('1')) voice = 1;
      if (lowerClean.contains('3')) voice = 3;
    } else {
      // Roman numerals
      if (RegExp(r'\biv\b').hasMatch(norm)) {
        voice = 4;
      } else if (RegExp(r'\biii\b').hasMatch(norm)) {
        voice = 3;
      } else if (RegExp(r'\bii\b').hasMatch(norm)) {
        voice = 2;
      } else if (RegExp(r'\bi\b').hasMatch(norm)) {
        voice = 1;
      } else {
        // Arabic numerals
        final match = RegExp(r'\b([1-9])(?:\.|\s*st|\s*nd|\s*rd|\s*th)?\b').firstMatch(norm);
        if (match != null) {
          voice = int.tryParse(match.group(1)!) ?? 0;
        }
      }
    }

    // 2. Detect key/transposition
    String detectedKey = '';
    final combinedKeySearch = '$norm $normHint';
    if (RegExp(r'\b(in\s+)?(bb|b)\b').hasMatch(combinedKeySearch)) {
      detectedKey = 'Bb';
    } else if (RegExp(r'\b(in\s+)?(eb|es)\b').hasMatch(combinedKeySearch)) {
      detectedKey = 'Eb';
    } else if (RegExp(r'\b(in\s+)?f\b').hasMatch(combinedKeySearch)) {
      detectedKey = 'F';
    } else if (RegExp(r'\b(in\s+)?c\b').hasMatch(combinedKeySearch)) {
      detectedKey = 'C';
    } else if (combinedKeySearch.contains('bass') && !combinedKeySearch.contains('bassklarinette')) {
      detectedKey = 'Bass';
    }

    // 3. Detect instrument canonical name
    String detectedInstrument = '';
    // First try the file name
    for (final entry in _instrumentAliases.entries) {
      for (final alias in entry.value) {
        if (norm.contains(alias)) {
          detectedInstrument = entry.key;
          break;
        }
      }
      if (detectedInstrument.isNotEmpty) break;
    }

    // If file name had no instrument alias, use instrumentHint from parent folder!
    if (detectedInstrument.isEmpty && normHint.isNotEmpty) {
      for (final entry in _instrumentAliases.entries) {
        for (final alias in entry.value) {
          if (normHint.contains(alias)) {
            detectedInstrument = entry.key;
            break;
          }
        }
        if (detectedInstrument.isNotEmpty) break;
      }
    }

    // MUST be a recognized canonical instrument, otherwise Zusatzstimme (never random titles/hints!)
    final displayInstrument = detectedInstrument.isNotEmpty
        ? (canonicalDisplayNames[detectedInstrument] ??
            detectedInstrument[0].toUpperCase() + detectedInstrument.substring(1))
        : 'Zusatzstimme';

    return PartFile(
      id: '$songId-$cleanName',
      songId: songId,
      fileName: fileName,
      remotePath: remotePath,
      detectedInstrument: displayInstrument,
      detectedVoice: voice,
      detectedKey: detectedKey,
      isCombinedVoice: isCombined,
    );
  }

  /// Calculates a match score (0 - 100) between a user profile and a part file
  static MatchResult scorePart(PartFile part, MusicianProfile profile) {
    final normPartInst = normalize(part.detectedInstrument);
    final normProfInst = normalize(profile.instrument);

    // Check if the instruments match (or are aliases of each other)
    bool instrumentMatches = normPartInst == normProfInst;
    if (!instrumentMatches) {
      for (final entry in _instrumentAliases.entries) {
        final matchesPart = entry.key == normPartInst || entry.value.contains(normPartInst);
        final matchesProf = entry.key == normProfInst || entry.value.contains(normProfInst);
        if (matchesPart && matchesProf) {
          instrumentMatches = true;
          break;
        }
      }
    }

    // Special check for Partitur / Conductor
    if (normProfInst.contains('partitur') || normProfInst.contains('direktion')) {
      if (normPartInst.contains('partitur') || normPartInst.contains('direktion')) {
        return MatchResult(part: part, score: 100, reason: 'Partitur/Direktion Übereinstimmung');
      }
      return MatchResult(part: part, score: 0, reason: 'Keine Partitur');
    }

    if (!instrumentMatches) {
      // If user profile is not found at all, but part is Partitur, keep as emergency fallback
      if (normPartInst.contains('partitur') || normPartInst.contains('direktion')) {
        return MatchResult(part: part, score: 15, reason: 'Partitur-Fallback');
      }
      return MatchResult(part: part, score: 0, reason: 'Anderes Instrument');
    }

    // Instrument matches! Now check voice and key
    int score = 60; // Base score for matching instrument
    String reason = 'Instrument stimmt überein';

    // Voice match
    if (profile.voiceNumber > 0) {
      if (part.detectedVoice == profile.voiceNumber) {
        score += 25;
        reason = 'Instrument und Stimme ($profile.voiceNumber) stimmen überein';
      } else if (part.isCombinedVoice) {
        score += 20;
        reason = 'Kombinierte Stimme enthält deine Stimme';
      } else if (part.detectedVoice == 0) {
        score += 10;
        reason = 'Einzelstimme ohne Stimmennummer';
      } else {
        // Different voice number (e.g. 2nd trumpet instead of 1st)
        score -= 20;
        reason = 'Andere Stimme (${part.detectedVoice}. statt ${profile.voiceNumber}.)';
      }
    } else {
      // User didn't specify voice number
      score += 20;
    }

    // Key match
    if (profile.keyOrClef.isNotEmpty) {
      final normKey = profile.keyOrClef.toLowerCase();
      final partKey = part.detectedKey.toLowerCase();
      if (partKey.isNotEmpty) {
        if (partKey == normKey) {
          score += 15;
          reason += ' (${profile.keyOrClef})';
        } else {
          score -= 10;
        }
      }
    }

    // Percussion sub-instrument match (Schlagzeug, Pauken, Mallets, Percussion)
    if (profile.instrument == 'Percussion' &&
        profile.percussionInstrument.isNotEmpty &&
        profile.percussionInstrument != 'Alle') {
      final partSub = detectPercussionSubInstrument(part.fileName);
      final reqSub = profile.percussionInstrument;
      if (partSub.toLowerCase() == reqSub.toLowerCase()) {
        score += 30;
        reason = '$reqSub ($reason)';
      } else {
        score -= 20;
        reason = 'Ausweichstimme ($partSub statt $reqSub)';
      }
    }

    return MatchResult(
      part: part,
      score: score.clamp(0, 100),
      reason: reason,
    );
  }

  /// Finds the best matching part file with match quality details (exact vs fallback).
  static DetailedMatch? findDetailedMatch(List<PartFile> parts, MusicianProfile profile) {
    if (parts.isEmpty) return null;

    final scored = parts
        .map((p) => scorePart(p, profile))
        .where((r) => r.score >= 40)
        .toList();

    if (scored.isEmpty) {
      return null;
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final best = scored.first;

    bool isExact = profile.voiceNumber == 0 ||
        best.part.detectedVoice == profile.voiceNumber ||
        best.part.isCombinedVoice ||
        best.part.detectedVoice == 0;

    if (profile.instrument == 'Percussion' &&
        profile.percussionInstrument.isNotEmpty &&
        profile.percussionInstrument != 'Alle') {
      final partSub = detectPercussionSubInstrument(best.part.fileName);
      if (partSub.toLowerCase() != profile.percussionInstrument.toLowerCase()) {
        isExact = false;
      }
    }

    return DetailedMatch(
      part: best.part,
      quality: isExact ? MatchQuality.exact : MatchQuality.fallback,
      requestedVoice: profile.voiceNumber,
      actualVoice: best.part.detectedVoice,
      reason: best.reason,
    );
  }

  /// Finds the best matching part file for a given song and profile.
  /// Returns null if no compatible part for this instrument/voice exists.
  static PartFile? findBestMatch(List<PartFile> parts, MusicianProfile profile) {
    return findDetailedMatch(parts, profile)?.part;
  }

  /// Finds the best matching part file for a song.
  /// If the song is a general list/document (e.g. from "Listen und Co"),
  /// it is always treated as an exact match for all musicians without instrument distinction.
  static DetailedMatch? findDetailedMatchForSong(Song song, MusicianProfile profile) {
    if (song.parts.isEmpty) return null;
    if (song.isDocumentOrList) {
      return DetailedMatch(
        part: song.parts.first,
        quality: MatchQuality.exact,
        requestedVoice: profile.voiceNumber,
        actualVoice: 0,
        reason: 'Dokument / Liste für alle Stimmen',
      );
    }
    return findDetailedMatch(song.parts, profile);
  }

  static PartFile? findBestMatchForSong(Song song, MusicianProfile profile) {
    return findDetailedMatchForSong(song, profile)?.part;
  }

  /// Extracts all distinct instruments present in the library,
  /// ordered by orchestral score order.
  static List<String> getAvailableInstruments(List<Song> songs) {
    final discovered = <String>{};
    for (final s in songs) {
      for (final p in s.parts) {
        final inst = p.detectedInstrument.trim();
        // Strict verification: ONLY include verified real instruments!
        if (knownRealInstruments.contains(inst)) {
          discovered.add(inst);
        }
      }
    }

    if (discovered.isEmpty) {
      return [
        'Flöte',
        'Klarinette',
        'Altsaxophon',
        'Tenorsaxophon',
        'Baritonsaxophon',
        'Trompete',
        'Flügelhorn',
        'Waldhorn',
        'Tenorhorn',
        'Bariton',
        'Posaune',
        'Tuba',
        'Percussion',
      ];
    }

    const standardOrder = [
      'Piccoloflöte', 'Flöte', 'Oboe', 'Fagott',
      'Es-Klarinette', 'Klarinette', 'Bassklarinette',
      'Sopransaxophon', 'Altsaxophon', 'Tenorsaxophon', 'Baritonsaxophon',
      'Trompete', 'Flügelhorn', 'Kornett',
      'Waldhorn',
      'Tenorhorn', 'Bariton', 'Euphonium',
      'Posaune',
      'Tuba', 'E-Bass', 'Kontrabass',
      'Percussion',
      'Klavier', 'Gitarre', 'Gesang', 'Harfe',
      'Violine', 'Viola', 'Violoncello',
    ];

    final sorted = discovered.toList()
      ..sort((a, b) {
        final idxA = standardOrder.indexOf(a);
        final idxB = standardOrder.indexOf(b);
        if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
        if (idxA != -1) return -1;
        if (idxB != -1) return 1;
        return a.compareTo(b);
      });

    return sorted;
  }
}
