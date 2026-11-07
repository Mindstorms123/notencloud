import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notencloud/models/musician_profile.dart';
import 'package:notencloud/models/nextcloud_account.dart';
import 'package:notencloud/models/setlist.dart';
import 'package:notencloud/models/song.dart';
import 'package:notencloud/services/nextcloud_service.dart';
import 'package:notencloud/services/voice_matcher.dart';

void main() {
  group('Setlist Cloud Folder & Sync Tests', () {
    test('ensureSetlistFolderExists checks and creates _Setlisten folder via MKCOL', () async {
      final List<String> requestedMethods = [];
      final List<String> requestedUrls = [];

      final mockClient = MockClient((request) async {
        requestedMethods.add(request.method);
        requestedUrls.add(request.url.path);

        if (request.method == 'PROPFIND') {
          // Simulate 404 Not Found so it attempts MKCOL
          return http.Response('', 404);
        } else if (request.method == 'MKCOL') {
          // Successfully created folder
          return http.Response('', 201);
        }
        return http.Response('', 200);
      });

      final account = NextcloudAccount(
        serverUrl: 'https://cloud.blasorchester-1862.de',
        username: 'musiker1',
        password: 'secret_password',
        rootFolder: '/Noten',
      );

      final service = NextcloudService(account, mockClient);
      final success = await service.ensureSetlistFolderExists();

      expect(success, isTrue);
      expect(requestedMethods, contains('PROPFIND'));
      expect(requestedMethods, contains('MKCOL'));
      expect(requestedUrls.any((url) => url.contains('_Setlisten')), isTrue);
    });

    test('Each musician sees their own instrument and voice on the same shared setlist', () {
      final setlist = Setlist.create(
        title: 'Frühjahrskonzert 2027',
        date: DateTime(2027, 4, 15),
      ).copyWith(
        items: [
          const SetlistItem(
            id: 'item-1',
            songId: 'song-alte-kameraden',
            songTitle: 'Alte Kameraden',
            songFolderName: 'Alte Kameraden',
            order: 1,
          ),
          const SetlistItem(
            id: 'item-2',
            songId: 'song-ablauf',
            songTitle: 'Ablaufplan',
            songFolderName: 'Ablaufplan',
            order: 2,
          ),
        ],
      );
      expect(setlist.items.length, 2);

      final alteKameraden = Song(
        id: 'song-alte-kameraden',
        title: 'Alte Kameraden',
        folderName: 'Alte Kameraden',
        remoteFolderPath: '/Noten/Alte Kameraden',
        parts: [
          PartFile(
            id: 'ak-trp1',
            songId: 'song-alte-kameraden',
            fileName: 'Trompete 1 in Bb.pdf',
            remotePath: '/Noten/Alte Kameraden/Trompete 1 in Bb.pdf',
            detectedInstrument: 'Trompete',
            detectedVoice: 1,
            detectedKey: 'Bb',
          ),
          PartFile(
            id: 'ak-tuba',
            songId: 'song-alte-kameraden',
            fileName: 'Tuba in C.pdf',
            remotePath: '/Noten/Alte Kameraden/Tuba in C.pdf',
            detectedInstrument: 'Tuba',
            detectedVoice: 1,
            detectedKey: 'C',
          ),
          PartFile(
            id: 'ak-schlagzeug',
            songId: 'song-alte-kameraden',
            fileName: 'Schlagzeug.pdf',
            remotePath: '/Noten/Alte Kameraden/Schlagzeug.pdf',
            detectedInstrument: 'Percussion',
            detectedVoice: 1,
          ),
        ],
      );
      expect(setlist.items.length, 2);

      final ablaufPlan = Song(
        id: 'song-ablauf',
        title: 'Ablaufplan',
        folderName: 'Ablaufplan',
        category: 'Listen und Co',
        remoteFolderPath: '/Noten/Listen und Co/Ablaufplan',
        parts: [
          PartFile(
            id: 'ablauf-doc',
            songId: 'song-ablauf',
            fileName: 'Ablaufplan.pdf',
            remotePath: '/Noten/Ablaufplan/Ablaufplan.pdf',
            detectedInstrument: 'Zusatzstimme',
          ),
        ],
      );
      expect(setlist.items.length, 2);

      // 1. Musician Profile: Trompete 1
      const profileTrompete1 = MusicianProfile(
        instrument: 'Trompete',
        voiceNumber: 1,
        keyOrClef: 'Bb',
      );
      final matchTrp = VoiceMatcher.findBestMatchForSong(alteKameraden, profileTrompete1);
      expect(matchTrp?.fileName, 'Trompete 1 in Bb.pdf');

      // 2. Musician Profile: Tuba
      const profileTuba = MusicianProfile(
        instrument: 'Tuba',
        voiceNumber: 1,
        keyOrClef: 'C',
      );
      final matchTuba = VoiceMatcher.findBestMatchForSong(alteKameraden, profileTuba);
      expect(matchTuba?.fileName, 'Tuba in C.pdf');

      // 3. Musician Profile: Schlagzeug
      const profileSchlagzeug = MusicianProfile(
        instrument: 'Percussion',
        percussionInstrument: 'Schlagzeug',
      );
      final matchPerc = VoiceMatcher.findBestMatchForSong(alteKameraden, profileSchlagzeug);
      expect(matchPerc?.fileName, 'Schlagzeug.pdf');

      // 4. Musician Profile: Trompete 2 (fallback to Trompete 1)
      const profileTrompete2 = MusicianProfile(
        instrument: 'Trompete',
        voiceNumber: 2,
        keyOrClef: 'Bb',
      );
      final matchTrp2 = VoiceMatcher.findDetailedMatchForSong(alteKameraden, profileTrompete2);
      expect(matchTrp2?.isFallback, isTrue);
      expect(matchTrp2?.part.fileName, 'Trompete 1 in Bb.pdf');

      // 5. General document / Ablaufplan matches all musicians equally
      final docMatchTrp = VoiceMatcher.findDetailedMatchForSong(ablaufPlan, profileTrompete1);
      final docMatchTuba = VoiceMatcher.findDetailedMatchForSong(ablaufPlan, profileTuba);
      expect(docMatchTrp?.part.fileName, 'Ablaufplan.pdf');
      expect(docMatchTuba?.part.fileName, 'Ablaufplan.pdf');
      expect(docMatchTrp?.isFallback, isFalse);
    });
  });
}
