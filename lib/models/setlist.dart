import 'package:uuid/uuid.dart';

/// Single item in a setlist
class SetlistItem {
  final String id;
  final String songId;
  final String songTitle;
  final String songFolderName;
  final int order;
  final String notes; // Custom performance notes: e.g. "Ohne Wdh.", "Attacca"
  final bool isIntermission; // "Pause" marker

  const SetlistItem({
    required this.id,
    required this.songId,
    required this.songTitle,
    required this.songFolderName,
    required this.order,
    this.notes = '',
    this.isIntermission = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'songId': songId,
        'songTitle': songTitle,
        'songFolderName': songFolderName,
        'order': order,
        'notes': notes,
        'isIntermission': isIntermission,
      };

  factory SetlistItem.fromJson(Map<String, dynamic> json) => SetlistItem(
        id: json['id'] as String? ?? const Uuid().v4(),
        songId: json['songId'] as String? ?? '',
        songTitle: json['songTitle'] as String? ?? '',
        songFolderName: json['songFolderName'] as String? ?? '',
        order: json['order'] as int? ?? 0,
        notes: json['notes'] as String? ?? '',
        isIntermission: json['isIntermission'] as bool? ?? false,
      );

  SetlistItem copyWith({
    int? order,
    String? notes,
    bool? isIntermission,
  }) =>
      SetlistItem(
        id: id,
        songId: songId,
        songTitle: songTitle,
        songFolderName: songFolderName,
        order: order ?? this.order,
        notes: notes ?? this.notes,
        isIntermission: isIntermission ?? this.isIntermission,
      );
}

/// A setlist containing an ordered list of songs for a concert, gig or rehearsal
class Setlist {
  final String id;
  final String title;
  final DateTime date;
  final String description;
  final List<SetlistItem> items;
  final DateTime updatedAt;
  final String createdBy;
  final bool isSyncedWithCloud;
  final String? remoteFileName; // e.g. "2026-12-15_Weihnachtskonzert.json"
  final String? konzertmeisterAppointmentId; // Linked Konzertmeister gig ID (e.g. "SHAP_...")

  const Setlist({
    required this.id,
    required this.title,
    required this.date,
    this.description = '',
    this.items = const [],
    required this.updatedAt,
    this.createdBy = '',
    this.isSyncedWithCloud = false,
    this.remoteFileName,
    this.konzertmeisterAppointmentId,
  });

  factory Setlist.create({
    required String title,
    DateTime? date,
    String description = '',
    List<SetlistItem> items = const [],
    String createdBy = '',
    String? konzertmeisterAppointmentId,
  }) {
    final now = DateTime.now();
    final d = date ?? now;
    final dateStr =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final safeTitle = title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final fileName = '${dateStr}_$safeTitle.json';

    return Setlist(
      id: const Uuid().v4(),
      title: title,
      date: d,
      description: description,
      items: items,
      updatedAt: now,
      createdBy: createdBy,
      remoteFileName: fileName,
      konzertmeisterAppointmentId: konzertmeisterAppointmentId,
    );
  }

  Setlist copyWith({
    String? title,
    DateTime? date,
    String? description,
    List<SetlistItem>? items,
    DateTime? updatedAt,
    bool? isSyncedWithCloud,
    String? remoteFileName,
    String? konzertmeisterAppointmentId,
    bool clearKonzertmeisterAppointmentId = false,
  }) {
    return Setlist(
      id: id,
      title: title ?? this.title,
      date: date ?? this.date,
      description: description ?? this.description,
      items: items ?? this.items,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy,
      isSyncedWithCloud: isSyncedWithCloud ?? this.isSyncedWithCloud,
      remoteFileName: remoteFileName ?? this.remoteFileName,
      konzertmeisterAppointmentId: clearKonzertmeisterAppointmentId
          ? null
          : (konzertmeisterAppointmentId ?? this.konzertmeisterAppointmentId),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'description': description,
        'items': items.map((i) => i.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
        'createdBy': createdBy,
        'remoteFileName': remoteFileName,
        'konzertmeisterAppointmentId': konzertmeisterAppointmentId,
      };

  factory Setlist.fromJson(Map<String, dynamic> json) => Setlist(
        id: json['id'] as String,
        title: json['title'] as String,
        date: DateTime.parse(json['date'] as String),
        description: json['description'] as String? ?? '',
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => SetlistItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        createdBy: json['createdBy'] as String? ?? '',
        isSyncedWithCloud: true,
        remoteFileName: json['remoteFileName'] as String?,
        konzertmeisterAppointmentId: json['konzertmeisterAppointmentId'] as String?,
      );
}
