import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/musician_profile.dart';
import '../models/nextcloud_account.dart';
import '../models/song.dart';
import '../models/setlist.dart';

class StorageService {
  static const _prefProfileKey = 'musician_profile';
  static const _prefAccountKey = 'nextcloud_account';
  static const _prefSongsCacheKey = 'cached_songs_index';
  static const _prefLocalSetlistsKey = 'local_setlists';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // --- Profile ---

  MusicianProfile getProfile() {
    final jsonStr = _prefs.getString(_prefProfileKey);
    if (jsonStr == null) return MusicianProfile.defaultProfile();
    try {
      return MusicianProfile.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
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
      return list.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
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
