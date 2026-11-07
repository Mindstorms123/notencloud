import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notencloud/models/musician_profile.dart';
import 'package:notencloud/models/nextcloud_account.dart';
import 'package:notencloud/models/setlist.dart';
import 'package:notencloud/services/annotation_service.dart';
import 'package:notencloud/services/konzertmeister_service.dart';
import 'package:notencloud/services/nextcloud_service.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:notencloud/ui/screens/setlists_screen.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE', null);
  });

  const sampleHtml = '''
<!DOCTYPE html>
<html>
<body class="light">
<div class="km-appointment-list" id="kmAppointmentList">
    <div class="km-list-item">
        <a class="km-app-date list-item-link"
           href="https://rest.konzertmeister.app/api/v1/ical/app/SHAP_aa8fc51e-4140-49fa-9178-efb5fa185245?excludeMeetingPoints=true">
            <div class="km-week-day-date">
                <div class="km-week-day km-different-year">
                    <div class="km-year">2026</div>
                    <div>Sa</div>
                </div>
                <div class="km-date-month">
                    <div class="km-date">12</div>
                    <div class="km-month">Dez.</div>
                </div>
            </div>
            <div class="km-time">
                16:45 - 18:00
            </div>
        </a>
        <div class="km-app-main km-attendance-indicator">
            <div class="km-appointment-header">
                <div class="km-appointment-name" title="Begleitung Vorabendmesse Herz-Jesu">
                    Begleitung Vorabendmesse Herz-Jesu
                </div>
                <div class="km-appointment-type">
                    Auftritt
                </div>
            </div>
            <div class="km-location">
                <a href="https://www.google.com/maps/search/?api=1&query=52.2074694,8.036315199999999" target="_blank"
                   rel="noopener noreferrer">Ulmenstra&szlig;e, 49124 Georgsmarienh&uuml;tte, Deutschland</a>
            </div>
        </div>
    </div>
</div>
</body>
</html>
''';

  const multiHtml = '''
<div class="km-appointment-list">
    <div class="km-list-item">
        <a class="km-app-date list-item-link" href="https://rest.konzertmeister.app/api/v1/ical/app/SHAP_111">
            <div class="km-week-day-date">
                <div class="km-week-day"><div>So</div></div>
                <div class="km-date-month">
                    <div class="km-date">15</div>
                    <div class="km-month">März</div>
                </div>
            </div>
            <div class="km-time">14:00 - 17:00</div>
        </a>
        <div class="km-app-main">
            <div class="km-appointment-header">
                <div class="km-appointment-name">Frühjahrskonzert &amp; Gala</div>
                <div class="km-appointment-type">Konzert</div>
            </div>
            <div class="km-location">
                <a href="https://maps.google.com/?q=Stadthalle">Stadthalle Georgsmarienhütte</a>
            </div>
        </div>
    </div>
    <div class="km-list-item">
        <a class="km-app-date list-item-link cancelled" href="https://rest.konzertmeister.app/api/v1/ical/app/SHAP_222">
            <div class="km-week-day-date">
                <div class="km-week-day"><div>Fr</div></div>
                <div class="km-date-month">
                    <div class="km-date">20</div>
                    <div class="km-month">Nov.</div>
                </div>
            </div>
            <div class="km-time">19:30</div>
        </a>
        <div class="km-app-main">
            <div class="km-appointment-header">
                <div class="km-appointment-name">Schützenfest Ausmarsch</div>
                <div class="km-appointment-type">Auftritt</div>
            </div>
        </div>
    </div>
</div>
''';

  group('Konzertmeister HTML Parser', () {
    test('parses real website sample HTML correctly', () {
      final items = KonzertmeisterService.parseHtml(sampleHtml);
      expect(items.length, 1);

      final gig = items.first;
      expect(gig.id, 'SHAP_aa8fc51e-4140-49fa-9178-efb5fa185245');
      expect(gig.title, 'Begleitung Vorabendmesse Herz-Jesu');
      expect(gig.type, 'Auftritt');
      expect(gig.weekday, 'Sa');
      expect(gig.dateTime.year, 2026);
      expect(gig.dateTime.month, 12);
      expect(gig.dateTime.day, 12);
      expect(gig.dateTime.hour, 16);
      expect(gig.dateTime.minute, 45);
      expect(gig.endDateTime?.hour, 18);
      expect(gig.endDateTime?.minute, 0);
      expect(gig.timeString, '16:45 - 18:00');
      expect(gig.location, 'Ulmenstraße, 49124 Georgsmarienhütte, Deutschland');
      expect(gig.mapsUrl, contains('52.2074694'));
      expect(gig.icalUrl, contains('SHAP_aa8fc51e-4140-49fa-9178-efb5fa185245'));
      expect(gig.isCancelled, false);
    });

    test('parses multiple events and decodes entities & handles cancelled state', () {
      final items = KonzertmeisterService.parseHtml(multiHtml);
      expect(items.length, 2);

      final gala = items.firstWhere((i) => i.id == 'SHAP_111');
      expect(gala.title, 'Frühjahrskonzert & Gala');
      expect(gala.type, 'Konzert');
      expect(gala.dateTime.month, 3);
      expect(gala.dateTime.day, 15);
      expect(gala.isCancelled, false);

      final cancelledGig = items.firstWhere((i) => i.id == 'SHAP_222');
      expect(cancelledGig.title, 'Schützenfest Ausmarsch');
      expect(cancelledGig.dateTime.hour, 19);
      expect(cancelledGig.dateTime.minute, 30);
      expect(cancelledGig.endDateTime, isNull);
      expect(cancelledGig.isCancelled, true);
    });

    test('handles empty or malformed HTML gracefully', () {
      expect(KonzertmeisterService.parseHtml(''), isEmpty);
      expect(KonzertmeisterService.parseHtml('<html><body>No events</body></html>'), isEmpty);
    });
  });

  group('Konzertmeister Storage & Setlist Linking', () {
    test('saves and loads cached appointments & setlist mappings', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      expect(storage.isKonzertmeisterEnabled(), true);
      expect(storage.getCachedKonzertmeisterAppointments(), isEmpty);
      expect(storage.getKonzertmeisterSetlistAssignments(), isEmpty);

      final appointments = KonzertmeisterService.parseHtml(sampleHtml);
      await storage.saveKonzertmeisterAppointments(appointments);

      final loaded = storage.getCachedKonzertmeisterAppointments();
      expect(loaded.length, 1);
      expect(loaded.first.title, 'Begleitung Vorabendmesse Herz-Jesu');

      const appointmentId = 'SHAP_aa8fc51e-4140-49fa-9178-efb5fa185245';
      const setlistId = 'setlist_12345';

      await storage.setKonzertmeisterSetlistAssignment(appointmentId, setlistId);
      expect(storage.getAssignedSetlistIdForAppointment(appointmentId), setlistId);
      expect(storage.getAssignedAppointmentIdForSetlist(setlistId), appointmentId);

      await storage.setKonzertmeisterSetlistAssignment(appointmentId, null);
      expect(storage.getAssignedSetlistIdForAppointment(appointmentId), isNull);
      expect(storage.getAssignedAppointmentIdForSetlist(setlistId), isNull);
    });
  });

  group('Konzertmeister UI Widget Tests', () {
    testWidgets('SetlistsScreen displays upcoming Konzertmeister Auftritt and allows assignment', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      // Pre-seed an appointment and an existing setlist
      final appointments = KonzertmeisterService.parseHtml(sampleHtml);
      await storage.saveKonzertmeisterAppointments(appointments);

      final testSetlist = Setlist.create(
        title: 'Kirchenmusik Herz-Jesu',
        date: DateTime(2026, 12, 12),
      );
      await storage.upsertSetlist(testSetlist);

      final annotationService = AnnotationService(storage);
      const profile = MusicianProfile(instrument: 'Trompete', voiceNumber: 1, keyOrClef: 'Bb');

      await tester.pumpWidget(
        MaterialApp(
          home: SetlistsScreen(
            storageService: storage,
            annotationService: annotationService,
            profile: profile,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Konzertmeister header is visible
      expect(find.text('Kommende Auftritte (Konzertmeister)'), findsOneWidget);
      expect(find.text('Begleitung Vorabendmesse Herz-Jesu'), findsOneWidget);
      expect(find.text('16:45 - 18:00'), findsOneWidget);
      expect(find.text('Setliste zuweisen'), findsOneWidget);

      // Tap 'Setliste zuweisen'
      await tester.tap(find.text('Setliste zuweisen'));
      await tester.pumpAndSettle();

      // Verify bottom sheet options
      expect(find.text('+ Neue Setliste für diesen Auftritt anlegen'), findsOneWidget);
      expect(find.text('Kirchenmusik Herz-Jesu'), findsWidgets);

      // Tap the existing setlist in bottom sheet to assign it
      await tester.tap(find.text('Kirchenmusik Herz-Jesu').last);
      await tester.pumpAndSettle();

      // Verify the assignment was saved
      expect(storage.getAssignedSetlistIdForAppointment(appointments.first.id), testSetlist.id);

      // Verify the card now shows the assigned setlist and open button
      expect(find.text('Öffnen'), findsOneWidget);
      expect(find.text('Auftritt: 12. Dez. 2026'), findsOneWidget);
    });
  });

  group('Konzertmeister Nextcloud Sync Tests', () {
    test('Setlist retains konzertmeisterAppointmentId across JSON serialization', () {
      final setlist = Setlist.create(
        title: 'Vorabendmesse',
        date: DateTime(2026, 12, 12),
        konzertmeisterAppointmentId: 'SHAP_12345',
      );

      final json = setlist.toJson();
      expect(json['konzertmeisterAppointmentId'], 'SHAP_12345');

      final restored = Setlist.fromJson(json);
      expect(restored.konzertmeisterAppointmentId, 'SHAP_12345');
    });

    test('NextcloudService uploads and fetches shared Konzertmeister assignments', () async {
      String? uploadedJson;

      final mockClient = MockClient((request) async {
        if (request.method == 'PUT' && request.url.path.contains('konzertmeister_assignments.json')) {
          uploadedJson = request.body;
          return http.Response('', 201);
        } else if (request.method == 'GET' && request.url.path.contains('konzertmeister_assignments.json')) {
          final body = uploadedJson ??
              jsonEncode({
                'version': 1,
                'assignments': {'SHAP_123': 'setlist_abc'}
              });
          return http.Response(body, 200);
        } else if (request.method == 'PROPFIND') {
          return http.Response('', 200);
        }
        return http.Response('', 200);
      });

      const account = NextcloudAccount(
        serverUrl: 'https://cloud.blasorchester-1862.de',
        username: 'dirigent',
        password: 'pw',
        rootFolder: '/Noten',
      );

      final ncService = NextcloudService(account, mockClient);

      // 1. One person uploads assignment
      final success = await ncService.uploadKonzertmeisterAssignments({'SHAP_123': 'setlist_abc'});
      expect(success, isTrue);
      expect(uploadedJson, contains('SHAP_123'));
      expect(uploadedJson, contains('setlist_abc'));

      // 2. Another musician fetches the assignments
      final fetched = await ncService.fetchKonzertmeisterAssignments();
      expect(fetched['SHAP_123'], 'setlist_abc');
    });
  });
}
