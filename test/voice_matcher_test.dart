import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/models/musician_profile.dart';
import 'package:notencloud/models/song.dart';
import 'package:notencloud/services/edition_lookup_service.dart';
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

    test('parses Trumpet Cornet I and slash combinations', () {
      final part1 = VoiceMatcher.parsePartFileName('LIFE ON MARS - Bb Trumpet Cornet I.pdf', 's1', '/p1');
      expect(part1.detectedInstrument, 'Trompete');
      expect(part1.detectedVoice, 1);
      expect(part1.detectedKey, 'Bb');

      final part2 = VoiceMatcher.parsePartFileName('LIFE ON MARS - Bb Trumpet/Cornet 1.pdf', 's1', '/p2');
      expect(part2.detectedInstrument, 'Trompete');
      expect(part2.detectedVoice, 1);
      expect(part2.detectedKey, 'Bb');

      final part3 = VoiceMatcher.parsePartFileName('Trumpet / Cornet 1.pdf', 's1', '/p3');
      expect(part3.detectedInstrument, 'Trompete');
      expect(part3.detectedVoice, 1);
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
      expect(VoiceMatcher.detectPercussionSubInstrument('Percussion_1.pdf'), 'Schlagzeug');
      expect(VoiceMatcher.detectPercussionSubInstrument('Becken_Triangel.pdf'), 'Schlagzeug');
      expect(VoiceMatcher.detectPercussionSubInstrument('Pauken.pdf'), 'Pauken');
      expect(VoiceMatcher.detectPercussionSubInstrument('Timpani_in_F.pdf'), 'Pauken');
      expect(VoiceMatcher.detectPercussionSubInstrument('Mallets.pdf'), 'Mallets');
      expect(VoiceMatcher.detectPercussionSubInstrument('Glockenspiel.pdf'), 'Mallets');
      expect(VoiceMatcher.detectPercussionSubInstrument('Mellods_1.pdf'), 'Mallets');
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

    test('matches Percussion.pdf as exact match when Schlagzeug is selected', () {
      const schlagzeugProfile = MusicianProfile(
        instrument: 'Percussion',
        percussionInstrument: 'Schlagzeug',
      );
      final parts = [
        VoiceMatcher.parsePartFileName('01_Partitur.pdf', 's', '/1'),
        VoiceMatcher.parsePartFileName('Percussion.pdf', 's', '/2'),
        VoiceMatcher.parsePartFileName('Pauken.pdf', 's', '/3'),
      ];

      final match = VoiceMatcher.findDetailedMatch(parts, schlagzeugProfile);
      expect(match, isNotNull);
      expect(match!.part.fileName, 'Percussion.pdf');
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

    test('English titles containing "I" do not distort Arabic voice numbers like Trompete 2', () {
      final tpt1 = VoiceMatcher.parsePartFileName('And I Love Her - Trompete 1.pdf', 's', '/p1');
      final tpt2 = VoiceMatcher.parsePartFileName('And I Love Her - Trompete 2 in Bb.pdf', 's', '/p2');

      expect(tpt1.detectedInstrument, 'Trompete');
      expect(tpt1.detectedVoice, 1);

      expect(tpt2.detectedInstrument, 'Trompete');
      expect(tpt2.detectedVoice, 2);
      expect(tpt2.detectedKey, 'Bb');

      const profileTpt1 = MusicianProfile(
        instrument: 'Trompete',
        voiceNumber: 1,
        keyOrClef: 'Bb',
      );

      final bestMatch = VoiceMatcher.findDetailedMatch([tpt1, tpt2], profileTpt1);
      expect(bestMatch, isNotNull);
      expect(bestMatch!.part.fileName, 'And I Love Her - Trompete 1.pdf');
      expect(bestMatch.quality, MatchQuality.exact);
    });
  });

  group('Song title cleaning and EditionLookup tests', () {
    test('cleanTitleFromFolder preserves titles starting with numbers like 80er or 99', () {
      expect(Song.cleanTitleFromFolder('80er Kulttour 2'), '80er Kulttour 2');
      expect(Song.cleanTitleFromFolder('80er KULT(tour)'), '80er KULT(tour)');
      expect(Song.cleanTitleFromFolder('99 Luftballons'), '99 Luftballons');
      expect(Song.cleanTitleFromFolder('7 Nation Army'), '7 Nation Army');
      expect(Song.cleanTitleFromFolder('1984'), '1984');

      // But still cleans ordering prefixes
      expect(Song.cleanTitleFromFolder('01_Aktuelle Noten'), 'Aktuelle Noten');
      expect(Song.cleanTitleFromFolder('001 - Alte Kameraden'), 'Alte Kameraden');
      expect(Song.cleanTitleFromFolder('02. Florentiner Marsch'), 'Florentiner Marsch');
      expect(Song.cleanTitleFromFolder('03 Florentiner Marsch'), 'Florentiner Marsch');
    });

    test('EditionLookupService finds verified Rundel edition for 80er Kulttour', () {
      final ed1 = EditionLookupService.getEdition('80er KULT(tour)');
      expect(ed1, isNotNull);
      expect(ed1!.publisher, contains('RUNDEL'));
      expect(ed1.orderNumber, 'MVSR 2956');
      expect(ed1.directUrl, contains('rundel.de'));

      final ed2 = EditionLookupService.getEdition('80er Kulttour 2');
      expect(ed2, isNotNull);
      expect(ed2!.publisher, contains('RUNDEL'));
      expect(ed2.orderNumber, 'MVSR 3236');
      expect(ed2.directUrl, 'https://www.rundel.de/de/artikel/80er_kult_tour_2/MVSR3236');
    });
  });
}
