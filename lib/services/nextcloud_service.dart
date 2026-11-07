import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import '../models/nextcloud_account.dart';
import '../models/song.dart';
import '../models/setlist.dart';
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

    for (final res in responses) {
      final hrefEl = res.findElements('d:href').isNotEmpty
          ? res.findElements('d:href').first
          : res.findElements('D:href').firstOrNull;
      if (hrefEl == null) continue;

      final href = Uri.decodeFull(hrefEl.innerText);
      final normalizedHref = href.endsWith('/') ? href : '$href/';
      // Skip the folder itself
      if (normalizedHref == requestPath) continue;

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

      items.add(_DavItem(
        href: href,
        name: name,
        isCollection: isCollection,
        size: size,
      ));
    }

    return items;
  }

  /// Scan the root sheet music folder and retrieve all songs with their parts,
  /// traversing both category folders (e.g. "01_Aktuelle Noten") and instrument subfolders.
  Future<List<Song>> scanLibrary({Function(int current, int total)? onProgress}) async {
    final rootFolder = account.cleanRootFolder;
    final rootItems = await _listFolder(rootFolder);
    final List<Song> songs = [];

    // Collect all song folders to scan across categories
    final List<({String songId, String title, String folderName, String href, String category})>
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
          final songId = '${item.name}_${songDir.name}';
          final songTitle = Song.cleanTitleFromFolder(songDir.name);

          songDirsToScan.add((
            songId: songId,
            title: songTitle,
            folderName: songDir.name,
            href: songDir.href,
            category: categoryName,
          ));
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
              ));
            }
          }
        }
      }
    }

    // Now scan all song folders with Depth: infinity in concurrent batches of 8
    final total = songDirsToScan.length;
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
          );
        }),
      );

      songs.addAll(batchResults.where((s) => s.parts.isNotEmpty));
      processed += batch.length;
      if (onProgress != null) {
        onProgress(processed, total);
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
          final fileName = href.split('/').last;
          setlists.add(Setlist.fromJson(jsonMap).copyWith(
            remoteFileName: fileName,
            isSyncedWithCloud: true,
          ));
        }
      } catch (_) {
        // Skip malformed files
      }
    }

    setlists.sort((a, b) => b.date.compareTo(a.date));
    return setlists;
  }

  /// Check if the user has write permissions to create/edit setlists in `_Setlisten/`
  Future<bool> hasSetlistWritePermission() async {
    try {
      final setlistFolder = '${account.cleanRootFolder}/_Setlisten';
      // First ensure the folder exists (MKCOL)
      final mkcolUrl = Uri.parse('${account.webDavBaseUrl}$setlistFolder');
      await _client.send(
        http.Request('MKCOL', mkcolUrl)..headers.addAll(_headers),
      );

      // Test write permission with an empty temp check file
      final testFileUrl = Uri.parse('${account.webDavBaseUrl}$setlistFolder/.perm_check');
      final putRes = await _client.put(testFileUrl, headers: _headers, body: 'ok');
      if (putRes.statusCode == 201 || putRes.statusCode == 204) {
        // Delete test file
        await _client.delete(testFileUrl, headers: _headers);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Upload or update a setlist on Nextcloud
  Future<bool> uploadSetlist(Setlist setlist) async {
    try {
      final setlistFolder = '${account.cleanRootFolder}/_Setlisten';
      final fileName = setlist.remoteFileName ?? '${setlist.id}.json';
      final url = Uri.parse('${account.webDavBaseUrl}$setlistFolder/$fileName');

      final content = const JsonEncoder.withIndent('  ').convert(setlist.toJson());
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
}

class _DavItem {
  final String href;
  final String name;
  final bool isCollection;
  final int size;

  const _DavItem({
    required this.href,
    required this.name,
    required this.isCollection,
    required this.size,
  });
}
