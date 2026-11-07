import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/musician_profile.dart';
import '../models/nextcloud_account.dart';
import '../models/song.dart';
import '../models/setlist.dart';
import 'voice_matcher.dart';

class StorageService {
  static const _prefProfileKey = 'musician_profile';
  static const _prefAccountKey = 'nextcloud_account';
  static const _prefSongsCacheKey = 'cached_songs_index';
  static const _prefLocalSetlistsKey = 'local_setlists';
  static const _prefDefaultCategoryKey = 'default_repertoire_category';
  static const _prefLastActiveCategoryKey = 'last_active_repertoire_category';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

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

  // --- Offline Directory paths ---

  Future<Directory> getAppDocsDir() async {
    if (kIsWeb) {
      throw UnsupportedError('Local filesystem paths not supported on web directly');
    }
    return await getApplicationDocumentsDirectory();
  }

  Future<String> getLocalPdfPath(String songId, String fileName) async {
    final docs = await getAppDocsDir();
    final safeSongId = songId.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final safeFileName = fileName.replaceAll(RegExp(r'[^\w\s-\.]'), '_');
    final dir = Directory('${docs.path}/scores/$safeSongId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return '${dir.path}/$safeFileName';
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
          var inst = p.detectedInstrument.trim();
          if (inst == 'Schlagzeug' || inst == 'Pauken' || inst == 'Glockenspiel') {
            inst = 'Percussion';
          }
          if (VoiceMatcher.knownRealInstruments.contains(inst) ||
              inst == 'Partitur' ||
              inst == 'Direktion' ||
              inst == 'Zusatzstimme' ||
              inst == 'Dokument') {
            return p.copyWith(detectedInstrument: inst);
          }
          // Legacy/bogus instrument name (e.g. "Wonderful Christmas") -> sanitize to Zusatzstimme
          return p.copyWith(detectedInstrument: 'Zusatzstimme');
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
}
