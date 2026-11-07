import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import '../models/nextcloud_account.dart';
import '../models/song.dart';
import '../models/setlist.dart';
import '../models/annotation.dart';
import 'voice_matcher.dart';

class NextcloudService {
  final NextcloudAccount account;
  final http.Client _client;

  NextcloudService(this.account, [http.Client? client])
      : _client = client ?? http.Client();

  Map<String, String> get _headers {
    final bytes = utf8.encode('${account.username}:${account.password}');
    final auth = base64.encode(bytes);
    return {
      'Authorization': 'Basic $auth',
      'OCS-APIREQUEST': 'true',
      'User-Agent': 'Notencloud/1.0',
    };
  }

  /// Test connection to Nextcloud server and verify credentials
  Future<bool> testConnection() async {
    try {
      final statusUrl = Uri.parse('${account.cleanServerUrl}/status.php');
      final statusRes = await _client.get(statusUrl).timeout(const Duration(seconds: 10));

      if (statusRes.statusCode != 200) {
        return false;
      }

      // Check WebDAV credentials
      final davUrl = Uri.parse(account.webDavBaseUrl);
      final davRes = await _client.send(
        http.Request('PROPFIND', davUrl)
          ..headers.addAll(_headers)
          ..headers['Depth'] = '0',
      ).timeout(const Duration(seconds: 10));

      return davRes.statusCode == 207 || davRes.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Initialize Nextcloud Login Flow v2.
  /// Generates the browser login URL and poll credentials.
  static Future<({String loginUrl, String pollEndpoint, String pollToken})?> initLoginFlow(String serverUrl) async {
    try {
      var cleanServer = serverUrl.trim();
      if (!cleanServer.startsWith('http://') && !cleanServer.startsWith('https://')) {
        cleanServer = 'https://$cleanServer';
      }
      cleanServer = cleanServer.replaceAll(RegExp(r'/+$'), '');

      final url = Uri.parse('$cleanServer/index.php/login/v2');
      final response = await http.post(
        url,
        headers: {'User-Agent': 'Notencloud/1.0 (Android)'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final loginUrl = data['login'] as String?;
        final poll = data['poll'] as Map<String, dynamic>?;
        final pollEndpoint = poll?['endpoint'] as String?;
        final pollToken = poll?['token'] as String?;

        if (loginUrl != null && pollEndpoint != null && pollToken != null) {
          return (
            loginUrl: loginUrl,
            pollEndpoint: pollEndpoint,
            pollToken: pollToken,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Poll the login flow endpoint once.
  /// Returns credentials when approved by user in browser, or null if pending.
  static Future<({String server, String loginName, String appPassword})?> pollLoginFlow(
    String pollEndpoint,
    String pollToken,
  ) async {
    try {
      final url = Uri.parse(pollEndpoint);
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Notencloud/1.0 (Android)',
        },
        body: {'token': pollToken},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final server = data['server'] as String? ?? '';
        final loginName = data['loginName'] as String? ?? '';
        final appPassword = data['appPassword'] as String? ?? '';
        if (loginName.isNotEmpty && appPassword.isNotEmpty) {
          return (server: server, loginName: loginName, appPassword: appPassword);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Helper to list items in a WebDAV folder
  Future<List<_DavItem>> _listFolder(String folderPath) async {
    final String fullUrl;
    if (folderPath.startsWith('http://') || folderPath.startsWith('https://')) {
      fullUrl = folderPath;
    } else if (folderPath.startsWith('/remote.php/dav/files/')) {
      fullUrl = '${account.cleanServerUrl}$folderPath';
    } else {
      final clean = folderPath.startsWith('/') ? folderPath : '/$folderPath';
      fullUrl = '${account.webDavBaseUrl}$clean';
    }
    final url = Uri.parse(fullUrl);

    final request = http.Request('PROPFIND', url)
      ..headers.addAll(_headers)
      ..headers['Depth'] = '1';

    final response = await _client.send(request);
    if (response.statusCode != 207) return [];

    final body = await response.stream.bytesToString();
    final document = xml.XmlDocument.parse(body);

    final List<_DavItem> items = [];
    final responses = document.findAllElements('d:response').isNotEmpty
        ? document.findAllElements('d:response')
        : document.findAllElements('D:response');

    final requestPath = url.path.endsWith('/') ? url.path : '${url.path}/';
    final decodedRequestPath = Uri.decodeFull(requestPath);

    for (final res in responses) {
      final hrefEl = res.findElements('d:href').isNotEmpty
          ? res.findElements('d:href').first
          : res.findElements('D:href').firstOrNull;
      if (hrefEl == null) continue;

      final href = Uri.decodeFull(hrefEl.innerText);
      final normalizedHref = href.endsWith('/') ? href : '$href/';
      // Skip the folder itself (check both raw and decoded paths)
      if (normalizedHref == decodedRequestPath ||
          normalizedHref == requestPath ||
          normalizedHref.replaceAll(RegExp(r'/+$'), '') == decodedRequestPath.replaceAll(RegExp(r'/+$'), '')) {
        continue;
      }

      final isCollection = res.findAllElements('d:collection').isNotEmpty ||
          res.findAllElements('D:collection').isNotEmpty;

      final segments = href.split('/').where((s) => s.isNotEmpty).toList();
      final name = segments.isNotEmpty ? segments.last : '';

      int size = 0;
      final lengthEl = res.findAllElements('d:getcontentlength').isNotEmpty
          ? res.findAllElements('d:getcontentlength').first
          : res.findAllElements('D:getcontentlength').firstOrNull;
      if (lengthEl != null) {
        size = int.tryParse(lengthEl.innerText) ?? 0;
      }

      String etag = '';
      final etagEl = res.findAllElements('d:getetag').isNotEmpty
          ? res.findAllElements('d:getetag').first
          : res.findAllElements('D:getetag').firstOrNull;
      if (etagEl != null) {
        etag = etagEl.innerText.replaceAll('"', '').trim();
      }

      items.add(_DavItem(
        href: href,
        name: name,
        isCollection: isCollection,
        size: size,
        etag: etag,
      ));
    }

    return items;
  }

  /// Scan the root sheet music folder with fast incremental delta-sync.
  /// If [existingCachedSongs] are provided, any song whose ETag has not changed
  /// on Nextcloud will be reused instantly without triggering a WebDAV Depth: infinity scan!
  Future<List<Song>> scanLibrary({
    List<Song>? existingCachedSongs,
    Function(int current, int total)? onProgress,
  }) async {
    final rootFolder = account.cleanRootFolder;
    final rootItems = await _listFolder(rootFolder);
    final List<Song> songs = [];

    // Sanitize cached songs to eliminate any phantom category-as-song entries
    final sanitizedCached = (existingCachedSongs ?? []).where((s) {
      if (s.id == '01_Aktuelle Noten_01_Aktuelle Noten' || s.id == '02_Ältere Noten_02_Ältere Noten') return false;
      if (s.folderName == '01_Aktuelle Noten' || s.folderName == '02_Ältere Noten') return false;
      if ((s.title.toLowerCase() == 'aktuelle noten' || s.title.toLowerCase() == 'ältere noten') && s.parts.length > 50) return false;
      return true;
    }).toList();

    // Map existing cached songs by ID and folderName for instant lookup
    final Map<String, Song> cachedMap = {
      for (final s in sanitizedCached) s.id: s,
    };
    final Map<String, Song> cachedByFolderMap = {
      for (final s in sanitizedCached) s.folderName: s,
    };

    // Collect song folders that are either new or have changed ETags
    final List<({String songId, String title, String folderName, String href, String category, String etag})>
        songDirsToScan = [];

    for (final item in rootItems) {
      if (item.name.startsWith('.') || item.name == '_Setlisten') continue;

      if (item.isCollection) {
        final categoryName = Song.cleanTitleFromFolder(item.name);
        final subItems = await _listFolder(item.href);

        final subDirs = subItems.where((i) => i.isCollection).toList();
        final pdfs = subItems
            .where((i) => !i.isCollection && i.name.toLowerCase().endsWith('.pdf'))
            .toList();

        // Category folder containing songs
        for (final songDir in subDirs) {
          if (songDir.name.startsWith('.')) continue;
          // Guard: Never treat the category folder itself as a song!
          if (songDir.name == item.name || songDir.href == item.href) continue;
          if (Song.cleanTitleFromFolder(songDir.name).toLowerCase() == categoryName.toLowerCase()) continue;
          final songId = '${item.name}_${songDir.name}';
          final songTitle = Song.cleanTitleFromFolder(songDir.name);

          // Fast Delta Cache check:
          final cached = cachedMap[songId] ?? cachedByFolderMap[songDir.name];
          final isCacheValid = cached != null &&
              cached.parts.isNotEmpty &&
              cached.etag.isNotEmpty &&
              songDir.etag.isNotEmpty &&
              cached.etag == songDir.etag;

          if (isCacheValid) {
            // Unchanged: reuse parsed parts instantly without any network call!
            songs.add(cached.copyWith(
              id: songId,
              title: songTitle,
              category: categoryName,
              remoteFolderPath: songDir.href,
              etag: songDir.etag,
              lastSynced: DateTime.now(),
            ));
          } else {
            // New or modified: queue for deep scan
            songDirsToScan.add((
              songId: songId,
              title: songTitle,
              folderName: songDir.name,
              href: songDir.href,
              category: categoryName,
              etag: songDir.etag,
            ));
          }
        }

        // Loose PDFs directly in folder (e.g. "03_Unsortiert")
        if (pdfs.isNotEmpty) {
          if (subDirs.isEmpty) {
            final songId = item.name;
            final songTitle = categoryName;
            final parts = pdfs
                .map((p) => VoiceMatcher.parsePartFileName(p.name, songId, p.href))
                .toList();
            songs.add(Song(
              id: songId,
              title: songTitle,
              folderName: item.name,
              remoteFolderPath: item.href,
              category: categoryName,
              parts: parts,
              lastSynced: DateTime.now(),
              etag: item.etag,
            ));
          } else {
            for (final pdf in pdfs) {
              final songId = pdf.name;
              final songTitle = Song.cleanTitleFromFolder(
                  pdf.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''));
              final part = VoiceMatcher.parsePartFileName(pdf.name, songId, pdf.href);
              songs.add(Song(
                id: songId,
                title: songTitle,
                folderName: item.name,
                remoteFolderPath: pdf.href,
                category: categoryName,
                parts: [part],
                lastSynced: DateTime.now(),
                etag: pdf.etag,
              ));
            }
          }
        }
      }
    }

    // Now scan only the new/modified song folders
    final totalToScan = songDirsToScan.length;
    if (totalToScan > 0) {
      int processed = 0;
      const batchSize = 8;

      for (int i = 0; i < songDirsToScan.length; i += batchSize) {
        final end = (i + batchSize < songDirsToScan.length) ? i + batchSize : songDirsToScan.length;
        final batch = songDirsToScan.sublist(i, end);

        final batchResults = await Future.wait(
          batch.map((s) async {
            final parts = await _scanSongFolder(s.href, s.songId);
            return Song(
              id: s.songId,
              title: s.title,
              folderName: s.folderName,
              remoteFolderPath: s.href,
              category: s.category,
              parts: parts,
              lastSynced: DateTime.now(),
              etag: s.etag,
            );
          }),
        );

        songs.addAll(batchResults.where((s) => s.parts.isNotEmpty));
        processed += batch.length;
        if (onProgress != null) {
          onProgress(processed, totalToScan);
        }
      }
    }

    songs.sort((a, b) => a.title.compareTo(b.title));
    return songs;
  }

  /// Scans all parts in a song folder using Depth: infinity for maximum speed
  Future<List<PartFile>> _scanSongFolder(String songFolderHref, String songId) async {
    final url = Uri.parse('${account.cleanServerUrl}$songFolderHref');
    final request = http.Request('PROPFIND', url)
      ..headers.addAll(_headers)
      ..headers['Depth'] = 'infinity';

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (_) {
      return [];
    }

    if (response.statusCode != 207) {
      return [];
    }

    final body = await response.stream.bytesToString();
    final document = xml.XmlDocument.parse(body);

    final List<PartFile> parts = [];
    final responses = document.findAllElements('d:response').isNotEmpty
        ? document.findAllElements('d:response')
        : document.findAllElements('D:response');

    final cleanSongHref = songFolderHref.endsWith('/') ? songFolderHref : '$songFolderHref/';

    for (final res in responses) {
      final hrefEl = res.findElements('d:href').isNotEmpty
          ? res.findElements('d:href').first
          : res.findElements('D:href').firstOrNull;
      if (hrefEl == null) continue;

      final href = Uri.decodeFull(hrefEl.innerText);
      if (href.endsWith('/') || !href.toLowerCase().endsWith('.pdf')) continue;

      final segments = href.split('/').where((s) => s.isNotEmpty).toList();
      final fileName = segments.last;

      String instrumentHint = '';
      if (segments.length >= 2) {
        final parentSegment = segments[segments.length - 2];
        if (!cleanSongHref.contains('/$parentSegment/')) {
          instrumentHint = parentSegment;
        }
      }

      int size = 0;
      final lengthEl = res.findAllElements('d:getcontentlength').isNotEmpty
          ? res.findAllElements('d:getcontentlength').first
          : res.findAllElements('D:getcontentlength').firstOrNull;
      if (lengthEl != null) {
        size = int.tryParse(lengthEl.innerText) ?? 0;
      }

      final part = VoiceMatcher.parsePartFileName(
        fileName,
        songId,
        href,
        instrumentHint: instrumentHint,
      );

      parts.add(part.copyWith(fileSizeBytes: size));
    }

    parts.sort((a, b) => a.fileName.compareTo(b.fileName));
    return parts;
  }

  /// Download a PDF part file to the local device
  Future<File> downloadPart(PartFile part, String localDestinationPath,
      {Function(double progress)? onProgress}) async {
    final url = Uri.parse('${account.cleanServerUrl}${part.remotePath}');
    final request = http.Request('GET', url)..headers.addAll(_headers);

    final streamedResponse = await _client.send(request);
    if (streamedResponse.statusCode != 200) {
      throw Exception('Fehler beim Download (${streamedResponse.statusCode})');
    }

    final totalBytes = streamedResponse.contentLength ?? 0;
    int receivedBytes = 0;

    final file = File(localDestinationPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();

    await for (final chunk in streamedResponse.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0 && onProgress != null) {
        onProgress(receivedBytes / totalBytes);
      }
    }

    await sink.flush();
    await sink.close();
    return file;
  }

  /// Fetch all setlists from the Nextcloud `_Setlisten/` directory
  Future<List<Setlist>> fetchSetlists() async {
    final setlistPath = '${account.cleanRootFolder}/_Setlisten';
    final url = Uri.parse('${account.webDavBaseUrl}$setlistPath');

    final request = http.Request('PROPFIND', url)
      ..headers.addAll(_headers)
      ..headers['Depth'] = '1';

    final response = await _client.send(request);
    if (response.statusCode != 207) return [];

    final body = await response.stream.bytesToString();
    final document = xml.XmlDocument.parse(body);

    final List<Setlist> setlists = [];
    final responses = document.findAllElements('d:response').isNotEmpty
        ? document.findAllElements('d:response')
        : document.findAllElements('D:response');

    for (final res in responses) {
      final hrefEl = res.findElements('d:href').isNotEmpty
          ? res.findElements('d:href').first
          : res.findElements('D:href').firstOrNull;
      if (hrefEl == null) continue;

      final href = Uri.decodeFull(hrefEl.innerText);
      if (!href.toLowerCase().endsWith('.json')) continue;

      // Download and parse setlist JSON
      try {
        final getUrl = Uri.parse('${account.cleanServerUrl}$href');
        final getRes = await _client.get(getUrl, headers: _headers);
        if (getRes.statusCode == 200) {
          final jsonMap = jsonDecode(getRes.body) as Map<String, dynamic>;
          setlists.add(Setlist.fromJson(jsonMap).copyWith(isSyncedWithCloud: true));
        }
      } catch (_) {
        // Skip malformed files
      }
    }

    return setlists;
  }

  /// Check write permission for the setlists folder
  Future<bool> hasSetlistWritePermission() async {
    final setlistPath = '${account.cleanRootFolder}/_Setlisten';
    final url = Uri.parse('${account.webDavBaseUrl}$setlistPath');

    // Ensure folder exists or can be created
    final req = http.Request('PROPFIND', url)
      ..headers.addAll(_headers)
      ..headers['Depth'] = '0';

    final res = await _client.send(req);
    if (res.statusCode == 404) {
      // Try creating it
      final mkcolReq = http.Request('MKCOL', url)..headers.addAll(_headers);
      final mkcolRes = await _client.send(mkcolReq);
      return mkcolRes.statusCode == 201;
    }

    return res.statusCode == 200 || res.statusCode == 207;
  }

  /// Upload a setlist JSON file to Nextcloud `_Setlisten/<id>.json`
  Future<bool> uploadSetlist(Setlist setlist) async {
    await hasSetlistWritePermission();

    final setlistPath = '${account.cleanRootFolder}/_Setlisten/${setlist.id}.json';
    final url = Uri.parse('${account.webDavBaseUrl}$setlistPath');
    final content = jsonEncode(setlist.toJson());

    try {
      final res = await _client.put(
        url,
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
        },
        body: content,
      );

      return res.statusCode == 201 || res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// Ensures that all directory levels exist on Nextcloud, creating missing ones via MKCOL
  Future<bool> ensureDirectoryExists(String relativePath) async {
    final clean = relativePath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final segments = clean.split('/');
    var currentPath = '';

    for (final seg in segments) {
      if (seg.isEmpty) continue;
      currentPath += '/$seg';
      final url = Uri.parse('${account.webDavBaseUrl}$currentPath');

      try {
        final req = http.Request('PROPFIND', url)
          ..headers.addAll(_headers)
          ..headers['Depth'] = '0';
        final res = await _client.send(req);

        if (res.statusCode == 404) {
          final mkcolReq = http.Request('MKCOL', url)..headers.addAll(_headers);
          final mkcolRes = await _client.send(mkcolReq);
          if (mkcolRes.statusCode != 201 && mkcolRes.statusCode != 405) {
            return false;
          }
        }
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  String _getUserAnnotationsDir(String songId) {
    final safeUser = account.username.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final safeSongId = songId.replaceAll(RegExp(r'[^\w\s-]'), '_');
    return '${account.cleanRootFolder}/_Notizen/$safeUser/$safeSongId';
  }

  /// Upload a user's page annotations to Nextcloud `_Notizen/<user>/<songId>/<partId>_p<page>.json`
  Future<bool> uploadPageAnnotations(String songId, String partId, PageAnnotations annotations) async {
    final safePartId = partId.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final userDir = _getUserAnnotationsDir(songId);
    final ok = await ensureDirectoryExists(userDir);
    if (!ok) return false;

    final remoteFilePath = '$userDir/${safePartId}_p${annotations.pageIndex}.json';
    final url = Uri.parse('${account.webDavBaseUrl}$remoteFilePath');
    final content = jsonEncode(annotations.toJson());

    try {
      final res = await _client.put(
        url,
        headers: {
          ..._headers,
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: utf8.encode(content),
      );
      return res.statusCode == 201 || res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// Download a user's page annotations from Nextcloud
  Future<PageAnnotations?> downloadPageAnnotations(String songId, String partId, int pageIndex) async {
    final safePartId = partId.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final userDir = _getUserAnnotationsDir(songId);
    final remoteFilePath = '$userDir/${safePartId}_p$pageIndex.json';
    final url = Uri.parse('${account.webDavBaseUrl}$remoteFilePath');

    try {
      final res = await _client.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return PageAnnotations.fromJson(map).copyWith(isSyncedWithCloud: true);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Delete a user's page annotations from Nextcloud
  Future<bool> deletePageAnnotations(String songId, String partId, int pageIndex) async {
    final safePartId = partId.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final userDir = _getUserAnnotationsDir(songId);
    final remoteFilePath = '$userDir/${safePartId}_p$pageIndex.json';
    final url = Uri.parse('${account.webDavBaseUrl}$remoteFilePath');

    try {
      final res = await _client.delete(url, headers: _headers);
      return res.statusCode == 204 || res.statusCode == 200 || res.statusCode == 404;
    } catch (_) {
      return false;
    }
  }
}

class _DavItem {
  final String href;
  final String name;
  final bool isCollection;
  final int size;
  final String etag;

  const _DavItem({
    required this.href,
    required this.name,
    required this.isCollection,
    required this.size,
    this.etag = '',
  });
}
