/// Represents an individual sheet music PDF file for a specific part/instrument
class PartFile {
  final String id;
  final String songId;
  final String fileName;
  final String remotePath;
  final String? localFilePath;
  final String detectedInstrument;
  final int detectedVoice;
  final String detectedKey;
  final bool isCombinedVoice; // e.g. "Trompete 1-2"
  final int fileSizeBytes;
  final DateTime? lastModified;
  final bool isDownloaded;

  const PartFile({
    required this.id,
    required this.songId,
    required this.fileName,
    required this.remotePath,
    this.localFilePath,
    this.detectedInstrument = '',
    this.detectedVoice = 0,
    this.detectedKey = '',
    this.isCombinedVoice = false,
    this.fileSizeBytes = 0,
    this.lastModified,
    this.isDownloaded = false,
  });

  PartFile copyWith({
    String? localFilePath,
    bool? isDownloaded,
    String? detectedInstrument,
    int? detectedVoice,
    String? detectedKey,
    bool? isCombinedVoice,
    int? fileSizeBytes,
    DateTime? lastModified,
  }) {
    return PartFile(
      id: id,
      songId: songId,
      fileName: fileName,
      remotePath: remotePath,
      localFilePath: localFilePath ?? this.localFilePath,
      detectedInstrument: detectedInstrument ?? this.detectedInstrument,
      detectedVoice: detectedVoice ?? this.detectedVoice,
      detectedKey: detectedKey ?? this.detectedKey,
      isCombinedVoice: isCombinedVoice ?? this.isCombinedVoice,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      lastModified: lastModified ?? this.lastModified,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'songId': songId,
        'fileName': fileName,
        'remotePath': remotePath,
        'localFilePath': localFilePath,
        'detectedInstrument': detectedInstrument,
        'detectedVoice': detectedVoice,
        'detectedKey': detectedKey,
        'isCombinedVoice': isCombinedVoice,
        'fileSizeBytes': fileSizeBytes,
        'lastModified': lastModified?.toIso8601String(),
        'isDownloaded': isDownloaded,
      };

  factory PartFile.fromJson(Map<String, dynamic> json) => PartFile(
        id: json['id'] as String,
        songId: json['songId'] as String,
        fileName: json['fileName'] as String,
        remotePath: json['remotePath'] as String,
        localFilePath: json['localFilePath'] as String?,
        detectedInstrument: json['detectedInstrument'] as String? ?? '',
        detectedVoice: json['detectedVoice'] as int? ?? 0,
        detectedKey: json['detectedKey'] as String? ?? '',
        isCombinedVoice: json['isCombinedVoice'] as bool? ?? false,
        fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
        lastModified: json['lastModified'] != null
            ? DateTime.tryParse(json['lastModified'] as String)
            : null,
        isDownloaded: json['isDownloaded'] as bool? ?? false,
      );

  bool get isScoreOrConductor {
    final lower = '$detectedInstrument $fileName'.toLowerCase();
    return lower.contains('partitur') ||
        lower.contains('direktion') ||
        lower.contains('score') ||
        lower.contains('conductor') ||
        lower.contains('tutti');
  }
}

/// Represents a musical piece / song folder on Nextcloud
class Song {
  final String id;
  final String title;
  final String folderName;
  final String remoteFolderPath;
  final String category; // e.g. "Aktuelle Noten", "Ältere Noten"
  final List<PartFile> parts;
  final String composer;
  final String arranger;
  final String tempo;
  final String notes;
  final DateTime? lastSynced;
  final String etag; // Nextcloud WebDAV ETag for fast delta sync

  const Song({
    required this.id,
    required this.title,
    required this.folderName,
    required this.remoteFolderPath,
    this.category = '',
    this.parts = const [],
    this.composer = '',
    this.arranger = '',
    this.tempo = '',
    this.notes = '',
    this.lastSynced,
    this.etag = '',
  });

  /// User-friendly title cleaned up from folder prefix numbers (e.g. "001_Alte_Kameraden" -> "Alte Kameraden")
  static String cleanTitleFromFolder(String folderName) {
    var cleaned = folderName;
    // Remove leading numbers like 001_ or 12 -
    cleaned = cleaned.replaceFirst(RegExp(r'^\d+[\s_-]*'), '');
    // Replace underscores with spaces
    cleaned = cleaned.replaceAll('_', ' ').trim();
    return cleaned.isEmpty ? folderName : cleaned;
  }

  /// Whether this entry is an orchestra list, schedule, or general document
  /// (e.g. from "Listen und Co") that has no instrument/voice distinction.
  bool get isDocumentOrList =>
      category.toLowerCase().contains('listen') ||
      category.toLowerCase().contains('archiv') ||
      remoteFolderPath.toLowerCase().contains('listen%20und%20co') ||
      remoteFolderPath.toLowerCase().contains('listen und co');

  Song copyWith({
    String? id,
    String? title,
    String? folderName,
    String? remoteFolderPath,
    String? category,
    List<PartFile>? parts,
    String? composer,
    String? arranger,
    String? tempo,
    String? notes,
    DateTime? lastSynced,
    String? etag,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      folderName: folderName ?? this.folderName,
      remoteFolderPath: remoteFolderPath ?? this.remoteFolderPath,
      category: category ?? this.category,
      parts: parts ?? this.parts,
      composer: composer ?? this.composer,
      arranger: arranger ?? this.arranger,
      tempo: tempo ?? this.tempo,
      notes: notes ?? this.notes,
      lastSynced: lastSynced ?? this.lastSynced,
      etag: etag ?? this.etag,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'folderName': folderName,
        'remoteFolderPath': remoteFolderPath,
        'category': category,
        'parts': parts.map((p) => p.toJson()).toList(),
        'composer': composer,
        'arranger': arranger,
        'tempo': tempo,
        'notes': notes,
        'lastSynced': lastSynced?.toIso8601String(),
        'etag': etag,
      };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
        id: json['id'] as String,
        title: json['title'] as String,
        folderName: json['folderName'] as String,
        remoteFolderPath: json['remoteFolderPath'] as String,
        category: json['category'] as String? ?? '',
        parts: (json['parts'] as List<dynamic>?)
                ?.map((e) => PartFile.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        composer: json['composer'] as String? ?? '',
        arranger: json['arranger'] as String? ?? '',
        tempo: json['tempo'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        lastSynced: json['lastSynced'] != null
            ? DateTime.tryParse(json['lastSynced'] as String)
            : null,
        etag: json['etag'] as String? ?? '',
      );
}
