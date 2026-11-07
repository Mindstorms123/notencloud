import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/annotation.dart';
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

  /// Load annotations for a specific song part and page
  Future<PageAnnotations> loadAnnotations(String songId, String partId, int pageIndex) async {
    if (kIsWeb) {
      return PageAnnotations(pageIndex: pageIndex);
    }
    try {
      final path = await _getAnnotationFilePath(songId, partId, pageIndex);
      final file = File(path);
      if (!await file.exists()) {
        return PageAnnotations(pageIndex: pageIndex);
      }
      final jsonStr = await file.readAsString();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return PageAnnotations.fromJson(map);
    } catch (e) {
      return PageAnnotations(pageIndex: pageIndex);
    }
  }

  /// Save annotations for a specific song part and page
  Future<void> saveAnnotations(String songId, String partId, PageAnnotations annotations) async {
    if (kIsWeb) return;
    try {
      final path = await _getAnnotationFilePath(songId, partId, annotations.pageIndex);
      final file = File(path);
      final jsonStr = jsonEncode(annotations.toJson());
      await file.writeAsString(jsonStr);
    } catch (e) {
      // Handle error gracefully
    }
  }

  /// Delete all annotations for a specific page
  Future<void> clearPageAnnotations(String songId, String partId, int pageIndex) async {
    if (kIsWeb) return;
    try {
      final path = await _getAnnotationFilePath(songId, partId, pageIndex);
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
