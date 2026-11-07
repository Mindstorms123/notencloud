import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/konzertmeister_appointment.dart';
import 'storage_service.dart';

class KonzertmeisterService {
  static const String defaultUrl =
      'https://rest.konzertmeister.app/api/v3/org/OALS_97300be2-6785-4047-b6f7-69d78c27a97b/upcomingappointments?showDescription=false&onlyPublicsite=true&limit=5&display=light&lang=de&hash=178e1a86f7a4f47ac79d26cbf617077cbe8308753d35cd6496c0e6d9e88d4543';

  final StorageService storageService;
  final http.Client client;

  KonzertmeisterService({
    required this.storageService,
    http.Client? client,
  }) : client = client ?? http.Client();

  /// Fetches upcoming appointments from the Konzertmeister widget URL.
  /// Falls back to cached appointments if offline or upon network error.
  Future<List<KonzertmeisterAppointment>> fetchAppointments({
    bool forceRefresh = false,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!storageService.isKonzertmeisterEnabled()) {
      return [];
    }

    final url = storageService.getKonzertmeisterUrl();

    try {
      final response = await client.get(Uri.parse(url)).timeout(timeout);
      if (response.statusCode == 200) {
        final appointments = parseHtml(response.body);
        if (appointments.isNotEmpty || response.body.contains('km-appointment-list')) {
          await storageService.saveKonzertmeisterAppointments(appointments);
          await storageService.setKonzertmeisterLastSync(DateTime.now());
          return appointments;
        }
      }
    } catch (_) {
      // Fallback to cache on network failure or timeout
    }

    return storageService.getCachedKonzertmeisterAppointments();
  }

  /// Parses the HTML returned by the Konzertmeister upcomingappointments widget.
  static List<KonzertmeisterAppointment> parseHtml(String htmlContent) {
    if (!htmlContent.contains('km-list-item')) {
      return [];
    }

    final items = <KonzertmeisterAppointment>[];
    final parts = htmlContent.split(RegExp(r'<div class="[^"]*km-list-item[^"]*"'));

    for (int i = 1; i < parts.length; i++) {
      final chunk = parts[i].split('<a href="https://konzertmeister.app"').first;

      // Extract iCal URL & ID
      final icalMatch = RegExp(r'href="([^"]*ical/app/([^"?]+)[^"]*)"').firstMatch(chunk);
      final icalUrl = icalMatch?.group(1) ?? '';
      var id = icalMatch?.group(2) ?? '';
      if (id.isEmpty) {
        final idMatch = RegExp(r'(SHAP_[a-zA-Z0-9\-]+)').firstMatch(chunk);
        id = idMatch?.group(1) ?? 'km_item_$i';
      }

      // Extract Title
      final titleMatch = RegExp(r'class="km-appointment-name"[^>]*title="([^"]+)"').firstMatch(chunk) ??
          RegExp(r'class="km-appointment-name"[^>]*>\s*([\s\S]*?)\s*</div>').firstMatch(chunk);
      final rawTitle = titleMatch?.group(1)?.trim() ?? 'Auftritt';
      final title = _unescapeHtml(rawTitle);

      // Extract Type
      final typeMatch = RegExp(r'class="km-appointment-type"[^>]*>\s*([\s\S]*?)\s*</div>').firstMatch(chunk);
      final rawType = typeMatch?.group(1)?.trim() ?? 'Auftritt';
      final type = _unescapeHtml(rawType);

      // Extract Day
      final dayMatch = RegExp(r'class="km-date"[^>]*>\s*(\d+)\s*</div>').firstMatch(chunk);
      final day = int.tryParse(dayMatch?.group(1) ?? '1') ?? 1;

      // Extract Month
      final monthMatch = RegExp(r'class="km-month"[^>]*>\s*([^<]+)\s*</div>').firstMatch(chunk);
      final rawMonth = monthMatch?.group(1)?.trim() ?? '';
      final monthNum = _parseMonth(rawMonth);

      // Extract Year
      final yearMatch = RegExp(r'class="km-year"[^>]*>\s*(\d{4})\s*</div>').firstMatch(chunk);
      final now = DateTime.now();
      int year;
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1)!) ?? now.year;
      } else {
        // If appointment month is earlier in the year than current month, assume next year
        year = (monthNum < now.month) ? now.year + 1 : now.year;
      }

      // Extract Weekday
      final weekdayMatch = RegExp(r'class="km-week-day[^"]*"[^>]*>[\s\S]*?<div>([A-Za-z]+)</div>').firstMatch(chunk);
      final weekday = weekdayMatch?.group(1)?.trim() ?? '';

      // Extract Time
      final timeMatch = RegExp(r'class="km-time"[^>]*>\s*([\s\S]*?)\s*</div>').firstMatch(chunk);
      final timeStr = (timeMatch?.group(1) ?? '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      // Check if cancelled
      final isCancelled = chunk.contains('km-app-date cancelled') || chunk.contains('cancelled');

      // Extract Location & Google Maps
      final locMatch = RegExp(r'class="km-location"[^>]*>[\s\S]*?<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>').firstMatch(chunk);
      String location = '';
      String mapsUrl = '';
      if (locMatch != null) {
        mapsUrl = locMatch.group(1)?.trim() ?? '';
        location = _unescapeHtml(locMatch.group(2)?.trim() ?? '');
      } else {
        final fallbackLoc = RegExp(r'class="km-location"[^>]*>([\s\S]*?)</div>').firstMatch(chunk);
        if (fallbackLoc != null) {
          location = _unescapeHtml(fallbackLoc.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim());
        }
      }

      // Parse start and end times
      final times = _parseTimeRange(timeStr);
      final startHour = times.$1;
      final startMinute = times.$2;
      final endHour = times.$3;
      final endMinute = times.$4;

      final dateTime = DateTime(year, monthNum, day, startHour, startMinute);
      final endDateTime = (endHour != null && endMinute != null)
          ? DateTime(year, monthNum, day, endHour, endMinute)
          : null;

      final dateString = '$day. $rawMonth $year';

      items.add(
        KonzertmeisterAppointment(
          id: id,
          title: title,
          type: type,
          dateTime: dateTime,
          endDateTime: endDateTime,
          dateString: dateString,
          timeString: timeStr,
          weekday: weekday,
          location: location,
          mapsUrl: mapsUrl,
          icalUrl: icalUrl,
          isCancelled: isCancelled,
        ),
      );
    }

    // Sort by dateTime ascending
    items.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return items;
  }

  static (int, int, int?, int?) _parseTimeRange(String timeStr) {
    // Example: "16:45 - 18:00" or "19:30"
    final regex = RegExp(r'(\d{1,2}):(\d{2})(?:\s*-\s*(\d{1,2}):(\d{2}))?');
    final m = regex.firstMatch(timeStr);
    if (m != null) {
      final sh = int.tryParse(m.group(1) ?? '0') ?? 0;
      final sm = int.tryParse(m.group(2) ?? '0') ?? 0;
      final eh = m.group(3) != null ? int.tryParse(m.group(3)!) : null;
      final em = m.group(4) != null ? int.tryParse(m.group(4)!) : null;
      return (sh, sm, eh, em);
    }
    return (0, 0, null, null);
  }

  static int _parseMonth(String monthStr) {
    final lower = monthStr.toLowerCase().replaceAll('.', '').trim();
    if (lower.startsWith('jan')) return 1;
    if (lower.startsWith('feb')) return 2;
    if (lower.startsWith('mär') || lower.startsWith('mrz')) return 3;
    if (lower.startsWith('apr')) return 4;
    if (lower.startsWith('mai')) return 5;
    if (lower.startsWith('jun')) return 6;
    if (lower.startsWith('jul')) return 7;
    if (lower.startsWith('aug')) return 8;
    if (lower.startsWith('sep')) return 9;
    if (lower.startsWith('okt')) return 10;
    if (lower.startsWith('nov')) return 11;
    if (lower.startsWith('dez')) return 12;
    return DateTime.now().month;
  }

  static String _unescapeHtml(String text) {
    var s = text
        .replaceAll('&auml;', 'ä')
        .replaceAll('&Auml;', 'Ä')
        .replaceAll('&ouml;', 'ö')
        .replaceAll('&Ouml;', 'Ö')
        .replaceAll('&uuml;', 'ü')
        .replaceAll('&Uuml;', 'Ü')
        .replaceAll('&szlig;', 'ß')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
