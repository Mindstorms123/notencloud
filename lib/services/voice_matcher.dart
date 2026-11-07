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
    'klarinette': ['klarinette', 'clarinet', 'clarinette', 'b klarinette', 'bb clarinet'],
    'bassklarinette': ['bassklarinette', 'bass clarinet'],
    'altsaxophon': ['altsaxophon', 'altsax', 'alt sax', 'alto saxophone', 'alto sax', 'es altsaxophon'],
    'tenorsaxophon': ['tenorsaxophon', 'tenorsax', 'tenor sax', 'tenor saxophone', 'b tenorsaxophon'],
    'baritonsaxophon': ['baritonsaxophon', 'baritonsax', 'bariton sax', 'baritone sax', 'baritone saxophone'],
    'trompete': ['trompete', 'trumpet', 'trompette', 'b trompete', 'bb trumpet', 'trpt'],
    'flügelhorn': ['fluegelhorn', 'flugelhorn', 'fluegel', 'b fluegelhorn'],
    'waldhorn': ['waldhorn', 'horn', 'f horn', 'french horn', 'es horn', 'in f', 'in es'],
    'posaune': ['posaune', 'trombone', 'tbne', 'bassposaune', 'tenorposaune'],
    'tenorhorn': ['tenorhorn', 'tenor horn', 'tenorhorn in b'],
    'bariton': ['bariton', 'baritone', 'bariton in b', 'bariton in c'],
    'euphonium': ['euphonium', 'euph'],
    'tuba': ['tuba', 'bass', 'baesse', 'bässe', 'b tuba', 'c tuba', 'es tuba', 'f tuba', 'sousaphon'],
    'schlagzeug': ['schlagzeug', 'drums', 'drum set', 'drumset', 'batterie'],
    'pauken': ['pauken', 'timpani', 'kettledrums'],
    'percussion': ['percussion', 'perkussion', 'mallets', 'becken', 'grosse trommel', 'triangel'],
    'glockenspiel': ['glockenspiel', 'xylophon', 'marimba', 'vibraphon', 'bells'],
    'klavier': ['klavier', 'piano', 'keyboard'],
    'e-bass': ['e bass', 'ebass', 'electric bass', 'bassgitarre'],
    'violine': ['violine', 'geige', 'violin', 'violino'],
    'viola': ['viola', 'bratsche'],
    'violoncello': ['violoncello', 'cello'],
    'kontrabass': ['kontrabass', 'double bass', 'string bass'],
    'partitur': ['partitur', 'full score', 'score', 'condensed score'],
    'direktion': ['direktion', 'direktion in c', 'direktion in b', 'conductor', 'lead sheet'],
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

    // Capitalize canonical instrument for display
    final displayInstrument = detectedInstrument.isNotEmpty
        ? detectedInstrument[0].toUpperCase() + detectedInstrument.substring(1)
        : (instrumentHint.isNotEmpty ? instrumentHint : cleanName);

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

    return MatchResult(
      part: part,
      score: score.clamp(0, 100),
      reason: reason,
    );
  }

  /// Finds the best matching part file for a given song and profile
  static PartFile? findBestMatch(List<PartFile> parts, MusicianProfile profile) {
    if (parts.isEmpty) return null;

    final scored = parts
        .map((p) => scorePart(p, profile))
        .where((r) => r.score > 30)
        .toList();

    if (scored.isEmpty) {
      return parts.first;
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.first.part;
  }
}
