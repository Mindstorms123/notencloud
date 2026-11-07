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

    test('consolidates all drums, timpani, and mallets/mellods to Percussion', () {
      final drumPart = VoiceMatcher.parsePartFileName('Schlagzeug.pdf', 's1', '/p1');
      final malletPart = VoiceMatcher.parsePartFileName('Song - Mallets.pdf', 's1', '/p2');
      final mellodPart = VoiceMatcher.parsePartFileName('Mellods_1.pdf', 's1', '/p3');
      final paukenPart = VoiceMatcher.parsePartFileName('Pauken.pdf', 's1', '/p4');
      final glspPart = VoiceMatcher.parsePartFileName('Glockenspiel.pdf', 's1', '/p5');
      final percPart = VoiceMatcher.parsePartFileName('Percussion.pdf', 's1', '/p6');

      expect(drumPart.detectedInstrument, 'Percussion');
      expect(malletPart.detectedInstrument, 'Percussion');
      expect(mellodPart.detectedInstrument, 'Percussion');
      expect(paukenPart.detectedInstrument, 'Percussion');
      expect(glspPart.detectedInstrument, 'Percussion');
      expect(percPart.detectedInstrument, 'Percussion');
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

    test('finds percussion match for drums / mallets / timpani part with Percussion profile', () {
      const profilePercussion = MusicianProfile(
        instrument: 'Percussion',
        voiceNumber: 1,
      );
      final percussionParts = [
        VoiceMatcher.parsePartFileName('Flöte_1.pdf', 'song3', '/p1'),
        VoiceMatcher.parsePartFileName('Schlagzeug.pdf', 'song3', '/p2'),
      ];
      final best = VoiceMatcher.findBestMatch(percussionParts, profilePercussion);
      expect(best, isNotNull);
      expect(best!.fileName, 'Schlagzeug.pdf');
    });

    test('detects specific percussion sub-instruments correctly', () {
      expect(VoiceMatcher.detectPercussionSubInstrument('Schlagzeug.pdf'), 'Schlagzeug');
      expect(VoiceMatcher.detectPercussionSubInstrument('Song - Drums.pdf'), 'Schlagzeug');
      expect(VoiceMatcher.detectPercussionSubInstrument('Pauken.pdf'), 'Pauken');
      expect(VoiceMatcher.detectPercussionSubInstrument('Timpani_in_F.pdf'), 'Pauken');
      expect(VoiceMatcher.detectPercussionSubInstrument('Mallets.pdf'), 'Mallets');
      expect(VoiceMatcher.detectPercussionSubInstrument('Glockenspiel.pdf'), 'Mallets');
      expect(VoiceMatcher.detectPercussionSubInstrument('Mellods_1.pdf'), 'Mallets');
      expect(VoiceMatcher.detectPercussionSubInstrument('Percussion_1.pdf'), 'Percussion');
      expect(VoiceMatcher.detectPercussionSubInstrument('Becken_Triangel.pdf'), 'Percussion');
    });

    test('prioritizes selected percussion sub-instrument (e.g. Pauken)', () {
      const paukenProfile = MusicianProfile(
        instrument: 'Percussion',
        percussionInstrument: 'Pauken',
      );
      final parts = [
        VoiceMatcher.parsePartFileName('01_Partitur.pdf', 's', '/1'),
        VoiceMatcher.parsePartFileName('Schlagzeug.pdf', 's', '/2'),
        VoiceMatcher.parsePartFileName('Pauken.pdf', 's', '/3'),
        VoiceMatcher.parsePartFileName('Mallets.pdf', 's', '/4'),
      ];

      final match = VoiceMatcher.findDetailedMatch(parts, paukenProfile);
      expect(match, isNotNull);
      expect(match!.part.fileName, 'Pauken.pdf');
      expect(match.quality, MatchQuality.exact);
    });

    test('falls back with warning when requested percussion sub-instrument is missing', () {
      const malletsProfile = MusicianProfile(
        instrument: 'Percussion',
        percussionInstrument: 'Mallets',
      );
      final parts = [
        VoiceMatcher.parsePartFileName('01_Partitur.pdf', 's', '/1'),
        VoiceMatcher.parsePartFileName('Schlagzeug.pdf', 's', '/2'),
      ];

      final match = VoiceMatcher.findDetailedMatch(parts, malletsProfile);
      expect(match, isNotNull);
      expect(match!.part.fileName, 'Schlagzeug.pdf');
      expect(match.quality, MatchQuality.fallback);
    });
  });
}
