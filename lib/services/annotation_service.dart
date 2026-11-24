import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/annotation.dart';
import 'nextcloud_service.dart';
import 'storage_service.dart';

class AnnotationService {
  final StorageService storageService;
  final bool isWeb;

  AnnotationService(this.storageService, {bool? isWeb})
      : isWeb = isWeb ?? kIsWeb;

  Future<String> _getAnnotationFilePath(String songId, String partId, int pageIndex) async {
    final docs = await storageService.getAppDocsDir();
    final safeSongId = songId.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final safePartId = partId.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final dir = Directory('${docs.path}/annotations/$safeSongId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return '${dir.path}/${safePartId}_p$pageIndex.json';
  }

  /// Load annotations for a specific song part and page.
  /// If NextcloudService is provided and local copy is missing, tries downloading from user's cloud folder.
  Future<PageAnnotations> loadAnnotations(
    String songId,
    String partId,
    int pageIndex, {
    NextcloudService? nextcloudService,
  }) async {
    final local = await _readLocal(songId, partId, pageIndex);
    if (local != null) {
      return local;
    }

    // Die Stimme hatte auf diesem Gerät früher eine andere Kennung: Notizen von
    // damals unter der neuen Kennung weiterführen. Bewusst ohne Upload – eine
    // neuere Notiz eines anderen Geräts in der Nextcloud soll gewinnen.
    final legacy = storageService.getLegacyPartId(partId);
    if (legacy != null) {
      final old = await _readLocal(legacy.songId, legacy.partId, pageIndex);
      if (old != null) {
        await saveAnnotations(songId, partId, old);
        return old;
      }
    }

    // If local was missing, try fetching from Nextcloud
    if (nextcloudService != null && nextcloudService.account.isConfigured) {
      try {
        final cloudAnn = await nextcloudService.downloadPageAnnotations(songId, partId, pageIndex);
        if (cloudAnn != null) {
          await saveAnnotations(songId, partId, cloudAnn);
          return cloudAnn;
        }
        if (legacy != null) {
          final oldCloud = await nextcloudService.downloadPageAnnotations(legacy.songId, legacy.partId, pageIndex);
          if (oldCloud != null) {
            await saveAnnotations(songId, partId, oldCloud);
            return oldCloud;
          }
        }
      } catch (_) {}
    }

    return PageAnnotations(pageIndex: pageIndex);
  }

  Future<PageAnnotations?> _readLocal(String songId, String partId, int pageIndex) async {
    try {
      if (isWeb) {
        final jsonStr = storageService.getWebAnnotation(songId, partId, pageIndex);
        if (jsonStr == null) return null;
        return PageAnnotations.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      }
      final file = File(await _getAnnotationFilePath(songId, partId, pageIndex));
      if (!await file.exists()) return null;
      return PageAnnotations.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Save annotations for a specific song part and page.
  /// Automatically uploads to Nextcloud user folder if NextcloudService is provided.
  Future<bool> saveAnnotations(
    String songId,
    String partId,
    PageAnnotations annotations, {
    NextcloudService? nextcloudService,
  }) async {
    try {
      final jsonStr = jsonEncode(annotations.toJson());
      if (isWeb) {
        await storageService.saveWebAnnotation(songId, partId, annotations.pageIndex, jsonStr);
      } else {
        final path = await _getAnnotationFilePath(songId, partId, annotations.pageIndex);
        final file = File(path);
        await file.writeAsString(jsonStr);
      }

      if (nextcloudService != null && nextcloudService.account.isConfigured) {
        final uploaded = await nextcloudService.uploadPageAnnotations(songId, partId, annotations);
        // Nicht übertragen (kein Internet): vormerken und später nachreichen.
        await storageService.setAnnotationUploadPending(songId, partId, annotations.pageIndex, !uploaded);
        return uploaded;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _syncingPending = false;

  /// Reicht vorgemerkte Notizen nach, sobald die Nextcloud wieder erreichbar
  /// ist. Liefert die Zahl der übertragenen Seiten.
  ///
  /// Hat ein anderes Gerät inzwischen eine neuere Fassung der Seite
  /// gespeichert, bleibt diese stehen und die lokale wird nicht hochgeladen.
  Future<int> syncPendingUploads(NextcloudService nextcloudService) async {
    if (_syncingPending || !nextcloudService.account.isConfigured) return 0;
    _syncingPending = true;
    var uploaded = 0;
    try {
      for (final item in storageService.getPendingAnnotationUploads()) {
        final local = await _readLocal(item.songId, item.partId, item.pageIndex);
        if (local == null) {
          await storageService.setAnnotationUploadPending(item.songId, item.partId, item.pageIndex, false);
          continue;
        }
        final cloud = await nextcloudService.downloadPageAnnotations(item.songId, item.partId, item.pageIndex);
        // Nextcloud nicht erreichbar: später wieder versuchen, Rest überspringen.
        if (nextcloudService.lastAnnotationDownloadFailed) break;
        final localTime = local.updatedAt;
        final cloudTime = cloud?.updatedAt;
        if (cloudTime != null && (localTime == null || cloudTime.isAfter(localTime))) {
          await storageService.setAnnotationUploadPending(item.songId, item.partId, item.pageIndex, false);
          continue;
        }
        if (await nextcloudService.uploadPageAnnotations(item.songId, item.partId, local)) {
          await storageService.setAnnotationUploadPending(item.songId, item.partId, item.pageIndex, false);
          uploaded++;
        } else {
          break;
        }
      }
    } catch (_) {
      // beim nächsten Durchlauf erneut
    } finally {
      _syncingPending = false;
    }
    return uploaded;
  }

  /// Delete all annotations for a specific page locally and on Nextcloud
  Future<void> clearPageAnnotations(
    String songId,
    String partId,
    int pageIndex, {
    NextcloudService? nextcloudService,
  }) async {
    try {
      await storageService.setAnnotationUploadPending(songId, partId, pageIndex, false);
      if (isWeb) {
        await storageService.deleteWebAnnotation(songId, partId, pageIndex);
      } else {
        final path = await _getAnnotationFilePath(songId, partId, pageIndex);
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      if (nextcloudService != null && nextcloudService.account.isConfigured) {
        await nextcloudService.deletePageAnnotations(songId, partId, pageIndex);
      }
    } catch (_) {}
  }
}
