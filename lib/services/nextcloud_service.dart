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

  /// Scan the root sheet music folder and retrieve all songs with their parts
  Future<List<Song>> scanLibrary() async {
    final rootFolder = account.cleanRootFolder;
    final url = Uri.parse('${account.webDavBaseUrl}$rootFolder');

    // Depth: 1 lists the folder itself and its immediate children (songs & _Setlisten)
    final request = http.Request('PROPFIND', url)
      ..headers.addAll(_headers)
      ..headers['Depth'] = '1';

    final response = await _client.send(request);
    if (response.statusCode != 207) {
      throw Exception('Fehler beim Abrufen der Notenliste: HTTP ${response.statusCode}');
    }

    final body = await response.stream.bytesToString();
    final document = xml.XmlDocument.parse(body);

    final List<Song> songs = [];
    final responses = document.findAllElements('d:response').isNotEmpty
        ? document.findAllElements('d:response')
        : document.findAllElements('D:response');

    for (final res in responses) {
      final hrefEl = res.findElements('d:href').isNotEmpty
          ? res.findElements('d:href').first
          : res.findElements('D:href').firstOrNull;
      if (hrefEl == null) continue;

      final href = Uri.decodeFull(hrefEl.innerText);
      // Skip the root folder itself
      if (href.endsWith(rootFolder) || href.endsWith('$rootFolder/')) continue;

      // Check if it is a directory
      final isCollection = res.findAllElements('d:collection').isNotEmpty ||
          res.findAllElements('D:collection').isNotEmpty;

      if (!isCollection) continue;

      // Extract folder name
      final folderSegments = href.split('/').where((s) => s.isNotEmpty).toList();
      final folderName = folderSegments.last;

      // Ignore setlist directory or hidden folders
      if (folderName.startsWith('.') || folderName == '_Setlisten') continue;

      final songId = folderName;
      final songTitle = Song.cleanTitleFromFolder(folderName);
      final remoteFolderPath = href;

      // Scan individual parts inside this song folder
      final parts = await _scanSongParts(remoteFolderPath, songId);

      songs.add(Song(
        id: songId,
        title: songTitle,
        folderName: folderName,
        remoteFolderPath: remoteFolderPath,
        parts: parts,
        lastSynced: DateTime.now(),
      ));
    }

    // Sort songs alphabetically
    songs.sort((a, b) => a.title.compareTo(b.title));
    return songs;
  }

  /// Scan all PDF parts inside a specific song folder
  Future<List<PartFile>> _scanSongParts(String folderHref, String songId) async {
    final url = Uri.parse('${account.cleanServerUrl}$folderHref');
    final request = http.Request('PROPFIND', url)
      ..headers.addAll(_headers)
      ..headers['Depth'] = '1';

    final response = await _client.send(request);
    if (response.statusCode != 207) return [];

    final body = await response.stream.bytesToString();
    final document = xml.XmlDocument.parse(body);

    final List<PartFile> parts = [];
    final responses = document.findAllElements('d:response').isNotEmpty
        ? document.findAllElements('d:response')
        : document.findAllElements('D:response');

    for (final res in responses) {
      final hrefEl = res.findElements('d:href').isNotEmpty
          ? res.findElements('d:href').first
          : res.findElements('D:href').firstOrNull;
      if (hrefEl == null) continue;

      final href = Uri.decodeFull(hrefEl.innerText);
      if (href.endsWith('/') || !href.toLowerCase().endsWith('.pdf')) continue;

      final fileName = href.split('/').last;

      // Parse metadata from file name using our smart VoiceMatcher
      final part = VoiceMatcher.parsePartFileName(fileName, songId, href);

      // Extract file size if available
      int size = 0;
      final lengthEl = res.findAllElements('d:getcontentlength').isNotEmpty
          ? res.findAllElements('d:getcontentlength').first
          : res.findAllElements('D:getcontentlength').firstOrNull;
      if (lengthEl != null) {
        size = int.tryParse(lengthEl.innerText) ?? 0;
      }

      parts.add(part.copyWith(
        detectedInstrument: part.detectedInstrument,
        detectedVoice: part.detectedVoice,
        detectedKey: part.detectedKey,
        isCombinedVoice: part.isCombinedVoice,
      ));
    }

    // Sort parts (Partitur first, then woodwinds, brass, percussion)
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
