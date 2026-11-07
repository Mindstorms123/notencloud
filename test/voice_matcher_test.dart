import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/models/musician_profile.dart';
import 'package:notencloud/services/voice_matcher.dart';

void main() {
  group('VoiceMatcher file name parsing', () {
    test('parses standard German naming format', () {
      final part = VoiceMatcher.parsePartFileName('Trompete_1_Bb.pdf', 'song1', '/path');
      expect(part.detectedInstrument.toLowerCase(), contains('trompete'));
      expect(part.detectedVoice, 1);
      expect(part.detectedKey, 'Bb');
      expect(part.isCombinedVoice, false);
    });

    test('parses roman numerals', () {
      final part = VoiceMatcher.parsePartFileName('Flöte_II.pdf', 'song1', '/path');
      expect(part.detectedInstrument.toLowerCase(), contains('flöte'));
      expect(part.detectedVoice, 2);
    });

    test('parses combined voices (1-2)', () {
      final part = VoiceMatcher.parsePartFileName('Horn_1-2_in_F.pdf', 'song1', '/path');
      expect(part.isCombinedVoice, true);
      expect(part.detectedVoice, 1);
      expect(part.detectedKey, 'F');
    });

    test('parses Alto Saxophone in Eb', () {
      final part = VoiceMatcher.parsePartFileName('Altsaxophon_1_Eb.pdf', 'song1', '/path');
      expect(part.detectedInstrument.toLowerCase(), contains('altsax'));
      expect(part.detectedVoice, 1);
      expect(part.detectedKey, 'Eb');
    });

    test('parses Partitur / Conductor', () {
      final part = VoiceMatcher.parsePartFileName('01_Partitur.pdf', 'song1', '/path');
      expect(part.detectedInstrument.toLowerCase(), contains('partitur'));
    });
  });

  group('VoiceMatcher scoring and best match', () {
    final profileTrompete1 = const MusicianProfile(
      instrument: 'Trompete',
      voiceNumber: 1,
      keyOrClef: 'Bb',
    );

    final partList = [
      VoiceMatcher.parsePartFileName('Partitur.pdf', 'song1', '/p1'),
      VoiceMatcher.parsePartFileName('Flöte_1.pdf', 'song1', '/p2'),
      VoiceMatcher.parsePartFileName('Klarinette_1_Bb.pdf', 'song1', '/p3'),
      VoiceMatcher.parsePartFileName('Trompete_2_Bb.pdf', 'song1', '/p4'),
      VoiceMatcher.parsePartFileName('Trompete_1_Bb.pdf', 'song1', '/p5'),
      VoiceMatcher.parsePartFileName('Tuba_in_C.pdf', 'song1', '/p6'),
    ];

    test('finds exact match for Trompete 1 (Bb)', () {
      final best = VoiceMatcher.findBestMatch(partList, profileTrompete1);
      expect(best, isNotNull);
      expect(best!.fileName, 'Trompete_1_Bb.pdf');
    });

    test('falls back to combined voice if exact voice is missing', () {
      final listWithCombined = [
        VoiceMatcher.parsePartFileName('Flöte_1.pdf', 'song2', '/p1'),
        VoiceMatcher.parsePartFileName('Trompete_1-2_Bb.pdf', 'song2', '/p2'),
      ];
      final best = VoiceMatcher.findBestMatch(listWithCombined, profileTrompete1);
      expect(best, isNotNull);
      expect(best!.fileName, 'Trompete_1-2_Bb.pdf');
    });
  });
}
