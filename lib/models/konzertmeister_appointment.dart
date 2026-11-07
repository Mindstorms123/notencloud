class KonzertmeisterAppointment {
  final String id;
  final String title;
  final String type; // e.g. "Auftritt", "Konzert", "Probe"
  final DateTime dateTime;
  final DateTime? endDateTime;
  final String dateString;
  final String timeString;
  final String weekday;
  final String location;
  final String mapsUrl;
  final String icalUrl;
  final bool isCancelled;

  const KonzertmeisterAppointment({
    required this.id,
    required this.title,
    required this.type,
    required this.dateTime,
    this.endDateTime,
    required this.dateString,
    required this.timeString,
    this.weekday = '',
    this.location = '',
    this.mapsUrl = '',
    this.icalUrl = '',
    this.isCancelled = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'dateTime': dateTime.toIso8601String(),
        'endDateTime': endDateTime?.toIso8601String(),
        'dateString': dateString,
        'timeString': timeString,
        'weekday': weekday,
        'location': location,
        'mapsUrl': mapsUrl,
        'icalUrl': icalUrl,
        'isCancelled': isCancelled,
      };

  factory KonzertmeisterAppointment.fromJson(Map<String, dynamic> json) =>
      KonzertmeisterAppointment(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        type: json['type'] as String? ?? 'Auftritt',
        dateTime: DateTime.tryParse(json['dateTime'] as String? ?? '') ??
            DateTime.now(),
        endDateTime: json['endDateTime'] != null
            ? DateTime.tryParse(json['endDateTime'] as String)
            : null,
        dateString: json['dateString'] as String? ?? '',
        timeString: json['timeString'] as String? ?? '',
        weekday: json['weekday'] as String? ?? '',
        location: json['location'] as String? ?? '',
        mapsUrl: json['mapsUrl'] as String? ?? '',
        icalUrl: json['icalUrl'] as String? ?? '',
        isCancelled: json['isCancelled'] as bool? ?? false,
      );
}
