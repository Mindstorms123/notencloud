import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/annotation.dart';
import 'nextcloud_service.dart';
import 'storage_service.dart';

class AnnotationService {
  final StorageService storageService;

  AnnotationService(this.storageService);

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
    PageAnnotations? local;
    if (!kIsWeb) {
      try {
        final path = await _getAnnotationFilePath(songId, partId, pageIndex);
        final file = File(path);
        if (await file.exists()) {
          final jsonStr = await file.readAsString();
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          local = PageAnnotations.fromJson(map);
        }
      } catch (_) {}
    }

    if (local != null) {
      return local;
    }

    // If local was missing, try fetching from Nextcloud
    if (nextcloudService != null && nextcloudService.account.isConfigured) {
      try {
        final cloudAnn = await nextcloudService.downloadPageAnnotations(songId, partId, pageIndex);
        if (cloudAnn != null) {
          await saveAnnotations(songId, partId, cloudAnn);
          return cloudAnn;
        }
      } catch (_) {}
    }

    return PageAnnotations(pageIndex: pageIndex);
  }

  /// Save annotations for a specific song part and page.
  /// Automatically uploads to Nextcloud user folder if NextcloudService is provided.
  Future<bool> saveAnnotations(
    String songId,
    String partId,
    PageAnnotations annotations, {
    NextcloudService? nextcloudService,
  }) async {
    if (kIsWeb) return false;
    try {
      final path = await _getAnnotationFilePath(songId, partId, annotations.pageIndex);
      final file = File(path);
      final jsonStr = jsonEncode(annotations.toJson());
      await file.writeAsString(jsonStr);

      if (nextcloudService != null && nextcloudService.account.isConfigured) {
        return await nextcloudService.uploadPageAnnotations(songId, partId, annotations);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Delete all annotations for a specific page locally and on Nextcloud
  Future<void> clearPageAnnotations(
    String songId,
    String partId,
    int pageIndex, {
    NextcloudService? nextcloudService,
  }) async {
    if (kIsWeb) return;
    try {
      final path = await _getAnnotationFilePath(songId, partId, pageIndex);
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      if (nextcloudService != null && nextcloudService.account.isConfigured) {
        await nextcloudService.deletePageAnnotations(songId, partId, pageIndex);
      }
    } catch (_) {}
  }
}
