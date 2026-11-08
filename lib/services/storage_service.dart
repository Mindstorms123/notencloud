import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/musician_profile.dart';
import '../models/nextcloud_account.dart';
import '../models/pedal_settings.dart';
import '../models/song.dart';
import '../models/setlist.dart';
import '../models/konzertmeister_appointment.dart';
import 'konzertmeister_service.dart';
import 'voice_matcher.dart';

class StorageService {
  static const _prefProfileKey = 'musician_profile';
  static const _prefAccountKey = 'nextcloud_account';
  static const _prefSongsCacheKey = 'cached_songs_index';
  static const _prefLocalSetlistsKey = 'local_setlists';
  static const _prefDefaultCategoryKey = 'default_repertoire_category';
  static const _prefLastActiveCategoryKey = 'last_active_repertoire_category';
  static const _prefPedalSettingsKey = 'pedal_settings';
  static const _prefIgnoredPartsKey = 'ignored_missing_parts';
  static const _prefAuditStatusFilterKey = 'audit_filter_status';
  static const _prefAuditCategoryKey = 'audit_filter_category';
  static const _prefAuditInstrumentKey = 'audit_filter_instrument';
  static const _prefAuditSortOptionKey = 'audit_filter_sort_option';
  static const _prefAuditModeKey = 'audit_filter_mode';
  static const _prefKonzertmeisterAppointmentsKey = 'konzertmeister_appointments';
  static const _prefKonzertmeisterAssignmentsKey = 'konzertmeister_setlist_assignments';
  static const _prefKonzertmeisterEnabledKey = 'konzertmeister_enabled';
  static const _prefKonzertmeisterUrlKey = 'konzertmeister_widget_url';
  static const _prefKonzertmeisterLastSyncKey = 'konzertmeister_last_sync';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // --- Digitization Audit Filter Preferences ---

  String? getAuditStatusFilter() => _prefs.getString(_prefAuditStatusFilterKey);
  Future<void> setAuditStatusFilter(String value) => _prefs.setString(_prefAuditStatusFilterKey, value);

  String? getAuditCategory() => _prefs.getString(_prefAuditCategoryKey);
  Future<void> setAuditCategory(String value) => _prefs.setString(_prefAuditCategoryKey, value);

  String? getAuditInstrument() => _prefs.getString(_prefAuditInstrumentKey);
  Future<void> setAuditInstrument(String value) => _prefs.setString(_prefAuditInstrumentKey, value);

  String? getAuditSortOption() => _prefs.getString(_prefAuditSortOptionKey);
  Future<void> setAuditSortOption(String value) => _prefs.setString(_prefAuditSortOptionKey, value);

  String? getAuditMode() => _prefs.getString(_prefAuditModeKey);
  Future<void> setAuditMode(String value) => _prefs.setString(_prefAuditModeKey, value);

  // --- Category Preferences ---

  String getDefaultCategory() {
    return _prefs.getString(_prefDefaultCategoryKey) ?? 'Aktuelle Noten';
  }

  Future<void> setDefaultCategory(String category) async {
    await _prefs.setString(_prefDefaultCategoryKey, category);
  }

  String getLastActiveCategory() {
    return _prefs.getString(_prefLastActiveCategoryKey) ?? getDefaultCategory();
  }

  Future<void> setLastActiveCategory(String category) async {
    await _prefs.setString(_prefLastActiveCategoryKey, category);
  }

  // --- Profile ---

  MusicianProfile getProfile() {
    final jsonStr = _prefs.getString(_prefProfileKey);
    if (jsonStr == null) return MusicianProfile.defaultProfile();
    try {
      final profile = MusicianProfile.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      if (profile.instrument == 'Schlagzeug' ||
          profile.instrument == 'Pauken' ||
          profile.instrument == 'Glockenspiel') {
        final migrated = profile.copyWith(instrument: 'Percussion');
        saveProfile(migrated);
        return migrated;
      }
      return profile;
    } catch (_) {
      return MusicianProfile.defaultProfile();
    }
  }

  Future<void> saveProfile(MusicianProfile profile) async {
    await _prefs.setString(_prefProfileKey, jsonEncode(profile.toJson()));
  }

  // --- Nextcloud Account ---

  NextcloudAccount getAccount() {
    final jsonStr = _prefs.getString(_prefAccountKey);
    if (jsonStr == null) {
      return const NextcloudAccount(
        serverUrl: '',
        username: '',
        password: '',
      );
    }
    try {
      return NextcloudAccount.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return const NextcloudAccount(serverUrl: '', username: '', password: '');
    }
  }

  Future<void> saveAccount(NextcloudAccount account) async {
    await _prefs.setString(_prefAccountKey, jsonEncode(account.toJson()));
  }

  // --- Web-safe in-memory score cache ---
  final Map<String, Uint8List> _webScoreCache = {};

  void cachePartBytes(String songId, String fileName, Uint8List bytes) {
    _webScoreCache['${songId}_$fileName'] = bytes;
  }

  Uint8List? getCachedPartBytes(String songId, String fileName) {
    return _webScoreCache['${songId}_$fileName'];
  }

  bool hasCachedPartBytes(String songId, String fileName) {
    return _webScoreCache.containsKey('${songId}_$fileName');
  }

  String? getWebAnnotation(String songId, String partId, int pageIndex) {
    return _prefs.getString('web_ann_${songId}_${partId}_$pageIndex');
  }

  Future<void> saveWebAnnotation(String songId, String partId, int pageIndex, String jsonStr) async {
    await _prefs.setString('web_ann_${songId}_${partId}_$pageIndex', jsonStr);
  }

  Future<void> deleteWebAnnotation(String songId, String partId, int pageIndex) async {
    await _prefs.remove('web_ann_${songId}_${partId}_$pageIndex');
  }

  // --- Offline Directory paths ---

  Future<Directory> getAppDocsDir() async {
    if (kIsWeb) {
      throw UnsupportedError('Local filesystem paths not supported on web directly');
    }
    return await getApplicationDocumentsDirectory();
  }

  Future<String> getLocalPdfPath(String songId, String fileName, {PartFile? part}) async {
    if (kIsWeb) {
      return 'web://$songId/$fileName';
    }
    final docs = await getAppDocsDir();
    final safeSongId = songId.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final safeFileName = fileName.replaceAll(RegExp(r'[^\w\s-\.]'), '_');
    final dir = Directory('${docs.path}/scores/$safeSongId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final targetPath = '${dir.path}/$safeFileName';
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      return targetPath;
    }

    // Auto-migration & legacy resolver:
    // If the exact target file doesn't exist yet, check if there's an older/alternate
    // downloaded file in this song's directory that matches this part.
    try {
      final existingFiles = dir.listSync().whereType<File>().toList();
      for (final f in existingFiles) {
        if (!f.path.toLowerCase().endsWith('.pdf')) continue;
        final base = f.path.split(Platform.pathSeparator).last;
        if (base == safeFileName) continue;

        // 1. Direct suffix match (e.g. "SongTitle - Trompete 1 in Bb.pdf" -> "Trompete 1 in Bb.pdf")
        if (base.toLowerCase().endsWith(safeFileName.toLowerCase())) {
          await f.rename(targetPath);
          return targetPath;
        }

        // 2. VoiceMatcher parsed match
        final expected = part ?? VoiceMatcher.parsePartFileName(fileName, songId, '');
        if (expected.detectedInstrument.isNotEmpty && expected.detectedInstrument != 'Zusatzstimme') {
          final candidate = VoiceMatcher.parsePartFileName(base, songId, '');
          if (candidate.detectedInstrument == expected.detectedInstrument) {
            final voiceMatches = candidate.detectedVoice == expected.detectedVoice ||
                (expected.detectedVoice <= 1 && candidate.detectedVoice <= 1);
            if (voiceMatches) {
              await f.rename(targetPath);
              return targetPath;
            }
          }
        }
      }
    } catch (_) {}

    return targetPath;
  }

  /// Checks if a part is already downloaded locally, resolving legacy filenames if needed.
  Future<bool> isPartDownloaded(String songId, String fileName, {PartFile? part}) async {
    if (kIsWeb) {
      return hasCachedPartBytes(songId, fileName);
    }
    try {
      final path = await getLocalPdfPath(songId, fileName, part: part);
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// Scans offline score directories to rename legacy files and delete redundant duplicates.
  Future<int> migrateAndDeduplicateScores(List<Song> songs) async {
    if (kIsWeb) return 0;
    int count = 0;
    try {
      final docs = await getAppDocsDir();
      final scoresDir = Directory('${docs.path}/scores');
      if (!await scoresDir.exists()) return 0;

      for (final song in songs) {
        final safeSongId = song.id.replaceAll(RegExp(r'[^\w\s-]'), '_');
        final songDir = Directory('${scoresDir.path}/$safeSongId');
        if (!await songDir.exists()) continue;

        final existingFiles = songDir.listSync().whereType<File>().toList();
        final pdfFiles = existingFiles.where((f) => f.path.toLowerCase().endsWith('.pdf')).toList();
        if (pdfFiles.isEmpty) continue;

        for (final part in song.parts) {
          final safeFileName = part.fileName.replaceAll(RegExp(r'[^\w\s-\.]'), '_');
          final targetPath = '${songDir.path}/$safeFileName';
          final targetFile = File(targetPath);
          final targetExists = await targetFile.exists();

          for (final f in List<File>.from(pdfFiles)) {
            final base = f.path.split(Platform.pathSeparator).last;
            if (base == safeFileName) continue;

            final isCandidate = base.toLowerCase().endsWith(safeFileName.toLowerCase()) ||
                (() {
                  final parsed = VoiceMatcher.parsePartFileName(base, song.id, '');
                  return parsed.detectedInstrument == part.detectedInstrument &&
                      (parsed.detectedVoice == part.detectedVoice ||
                          (part.detectedVoice <= 1 && parsed.detectedVoice <= 1));
                })();

            if (isCandidate) {
              if (targetExists) {
                try {
                  await f.delete();
                  pdfFiles.remove(f);
                  count++;
                } catch (_) {}
              } else {
                try {
                  await f.rename(targetPath);
                  pdfFiles.remove(f);
                  count++;
                  break;
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (_) {}
    return count;
  }

  // --- Cached Songs Index ---

  List<Song> getCachedSongs() {
    final jsonStr = _prefs.getString(_prefSongsCacheKey);
    if (jsonStr == null) return [];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final songs = list.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
      return songs.map((song) {
        final sanitizedParts = song.parts.map((p) {
          final reparsed = VoiceMatcher.parsePartFileName(p.fileName, p.songId, p.remotePath);
          var inst = reparsed.detectedInstrument.trim();
          if (inst == 'Schlagzeug' || inst == 'Pauken' || inst == 'Glockenspiel') {
            inst = 'Percussion';
          }
          final validInst = (VoiceMatcher.knownRealInstruments.contains(inst) ||
                  inst == 'Partitur' ||
                  inst == 'Direktion' ||
                  inst == 'Zusatzstimme' ||
                  inst == 'Dokument')
              ? inst
              : 'Zusatzstimme';

          return p.copyWith(
            detectedInstrument: validInst,
            detectedVoice: reparsed.detectedVoice,
            detectedKey: reparsed.detectedKey,
            isCombinedVoice: reparsed.isCombinedVoice,
          );
        }).toList();
        return song.copyWith(parts: sanitizedParts);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCachedSongs(List<Song> songs) async {
    final list = songs.map((s) => s.toJson()).toList();
    await _prefs.setString(_prefSongsCacheKey, jsonEncode(list));
  }

  // --- Setlists Cache & Local Setlists ---

  List<Setlist> getLocalSetlists() {
    final jsonStr = _prefs.getString(_prefLocalSetlistsKey);
    if (jsonStr == null) return [];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.map((e) => Setlist.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveLocalSetlists(List<Setlist> setlists) async {
    final list = setlists.map((s) => s.toJson()).toList();
    await _prefs.setString(_prefLocalSetlistsKey, jsonEncode(list));
  }

  Future<void> upsertSetlist(Setlist setlist) async {
    final all = getLocalSetlists();
    final index = all.indexWhere((s) => s.id == setlist.id);
    if (index >= 0) {
      all[index] = setlist;
    } else {
      all.add(setlist);
    }
    await saveLocalSetlists(all);
  }

  Future<void> deleteSetlist(String id) async {
    final all = getLocalSetlists();
    all.removeWhere((s) => s.id == id);
    await saveLocalSetlists(all);
  }

  // --- Bluetooth Foot Pedal (Page Turner) ---

  PedalSettings getPedalSettings() {
    final jsonStr = _prefs.getString(_prefPedalSettingsKey);
    if (jsonStr == null) return PedalSettings.defaultSettings();
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return PedalSettings.fromJson(map);
    } catch (_) {
      return PedalSettings.defaultSettings();
    }
  }

  Future<void> savePedalSettings(PedalSettings settings) async {
    await _prefs.setString(_prefPedalSettingsKey, jsonEncode(settings.toJson()));
  }

  // --- Ignored Missing Parts (Nicht im Original vorhanden) ---

  Map<String, List<String>> getIgnoredMissingPartsMap() {
    final jsonStr = _prefs.getString(_prefIgnoredPartsKey);
    if (jsonStr == null || jsonStr.isEmpty) return {};
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as List).cast<String>()));
    } catch (_) {
      return {};
    }
  }

  List<String> getIgnoredMissingPartsForSong(String songId) {
    return getIgnoredMissingPartsMap()[songId] ?? const [];
  }

  Future<void> setPartIgnored(String songId, String partName, bool isIgnored) async {
    final map = getIgnoredMissingPartsMap();
    final list = map[songId] != null ? List<String>.from(map[songId]!) : <String>[];
    if (isIgnored) {
      if (!list.contains(partName)) list.add(partName);
    } else {
      list.remove(partName);
    }
    if (list.isEmpty) {
      map.remove(songId);
    } else {
      map[songId] = list;
    }
    await _prefs.setString(_prefIgnoredPartsKey, jsonEncode(map));
  }

  Future<void> setPartsIgnored(String songId, List<String> partNames, bool isIgnored) async {
    final map = getIgnoredMissingPartsMap();
    final list = map[songId] != null ? List<String>.from(map[songId]!) : <String>[];
    for (final p in partNames) {
      if (isIgnored) {
        if (!list.contains(p)) list.add(p);
      } else {
        list.remove(p);
      }
    }
    if (list.isEmpty) {
      map.remove(songId);
    } else {
      map[songId] = list;
    }
    await _prefs.setString(_prefIgnoredPartsKey, jsonEncode(map));
  }

  // --- Konzertmeister Kalender & Auftritte ---

  bool isKonzertmeisterEnabled() {
    return _prefs.getBool(_prefKonzertmeisterEnabledKey) ?? true;
  }

  Future<void> setKonzertmeisterEnabled(bool enabled) async {
    await _prefs.setBool(_prefKonzertmeisterEnabledKey, enabled);
  }

  String getKonzertmeisterUrl() {
    return _prefs.getString(_prefKonzertmeisterUrlKey) ?? KonzertmeisterService.defaultUrl;
  }

  Future<void> setKonzertmeisterUrl(String url) async {
    await _prefs.setString(_prefKonzertmeisterUrlKey, url);
  }

  DateTime? getKonzertmeisterLastSync() {
    final str = _prefs.getString(_prefKonzertmeisterLastSyncKey);
    if (str == null) return null;
    return DateTime.tryParse(str);
  }

  Future<void> setKonzertmeisterLastSync(DateTime dt) async {
    await _prefs.setString(_prefKonzertmeisterLastSyncKey, dt.toIso8601String());
  }

  List<KonzertmeisterAppointment> getCachedKonzertmeisterAppointments() {
    final jsonStr = _prefs.getString(_prefKonzertmeisterAppointmentsKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.map((e) => KonzertmeisterAppointment.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveKonzertmeisterAppointments(List<KonzertmeisterAppointment> appointments) async {
    final list = appointments.map((a) => a.toJson()).toList();
    await _prefs.setString(_prefKonzertmeisterAppointmentsKey, jsonEncode(list));
  }

  Map<String, String> getKonzertmeisterSetlistAssignments() {
    final jsonStr = _prefs.getString(_prefKonzertmeisterAssignmentsKey);
    if (jsonStr == null || jsonStr.isEmpty) return {};
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  String? getAssignedSetlistIdForAppointment(String appointmentId) {
    return getKonzertmeisterSetlistAssignments()[appointmentId];
  }

  String? getAssignedAppointmentIdForSetlist(String setlistId) {
    final map = getKonzertmeisterSetlistAssignments();
    for (final entry in map.entries) {
      if (entry.value == setlistId) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> setKonzertmeisterSetlistAssignment(String appointmentId, String? setlistId) async {
    final map = Map<String, String>.from(getKonzertmeisterSetlistAssignments());
    if (setlistId == null || setlistId.isEmpty) {
      map.remove(appointmentId);
    } else {
      map[appointmentId] = setlistId;
    }
    await _prefs.setString(_prefKonzertmeisterAssignmentsKey, jsonEncode(map));
  }

  /// Applies shared club configuration downloaded from Nextcloud
  Future<void> applyClubConfig(Map<String, dynamic> config) async {
    if (config['konzertmeister'] is Map<String, dynamic>) {
      final km = config['konzertmeister'] as Map<String, dynamic>;
      if (km['enabled'] is bool) {
        await setKonzertmeisterEnabled(km['enabled'] as bool);
      }
      if (km['widgetUrl'] is String && (km['widgetUrl'] as String).isNotEmpty) {
        await setKonzertmeisterUrl(km['widgetUrl'] as String);
      }
    } else if (config['konzertmeisterWidgetUrl'] is String) {
      await setKonzertmeisterUrl(config['konzertmeisterWidgetUrl'] as String);
      await setKonzertmeisterEnabled(true);
    }
    if (config['defaultCategory'] is String && (config['defaultCategory'] as String).isNotEmpty) {
      await setDefaultCategory(config['defaultCategory'] as String);
    }
  }
}
