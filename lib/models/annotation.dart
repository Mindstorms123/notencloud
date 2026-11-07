import 'package:flutter/material.dart';

enum StrokeType {
  pen,
  highlighter,
  eraser,
  text,
}

/// Normalized 2D coordinate on a PDF page (0.0 to 1.0)
class Point2D {
  final double x;
  final double y;
  final double pressure;

  const Point2D({
    required this.x,
    required this.y,
    this.pressure = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'p': pressure,
      };

  factory Point2D.fromJson(Map<String, dynamic> json) => Point2D(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        pressure: (json['p'] as num?)?.toDouble() ?? 1.0,
      );
}

/// A drawn vector stroke on the sheet music
class Stroke {
  final String id;
  final StrokeType type;
  final int colorValue; // ARGB
  final double width;
  final List<Point2D> points;

  const Stroke({
    required this.id,
    required this.type,
    required this.colorValue,
    required this.width,
    required this.points,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'color': colorValue,
        'width': width,
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory Stroke.fromJson(Map<String, dynamic> json) => Stroke(
        id: json['id'] as String,
        type: StrokeType.values.byName(json['type'] as String? ?? 'pen'),
        colorValue: json['color'] as int? ?? 0xFF000000,
        width: (json['width'] as num?)?.toDouble() ?? 2.0,
        points: (json['points'] as List<dynamic>?)
                ?.map((e) => Point2D.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// A text note pinned to a location on the sheet music
class TextNote {
  final String id;
  final String text;
  final Point2D position;
  final int colorValue;
  final double fontSize;
  final bool hasBackground;

  const TextNote({
    required this.id,
    required this.text,
    required this.position,
    this.colorValue = 0xFFEF4444, // Default conductor red
    this.fontSize = 14.0,
    this.hasBackground = true,
  });

  Color get color => Color(colorValue);

  TextNote copyWith({
    String? text,
    Point2D? position,
    int? colorValue,
    double? fontSize,
    bool? hasBackground,
  }) {
    return TextNote(
      id: id,
      text: text ?? this.text,
      position: position ?? this.position,
      colorValue: colorValue ?? this.colorValue,
      fontSize: fontSize ?? this.fontSize,
      hasBackground: hasBackground ?? this.hasBackground,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'position': position.toJson(),
        'color': colorValue,
        'fontSize': fontSize,
        'hasBg': hasBackground,
      };

  factory TextNote.fromJson(Map<String, dynamic> json) => TextNote(
        id: json['id'] as String,
        text: json['text'] as String,
        position: Point2D.fromJson(json['position'] as Map<String, dynamic>),
        colorValue: json['color'] as int? ?? 0xFFEF4444,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
        hasBackground: json['hasBg'] as bool? ?? true,
      );
}

/// All annotations for a specific page of a piece
class PageAnnotations {
  final int pageIndex;
  final List<Stroke> strokes;
  final List<TextNote> textNotes;

  const PageAnnotations({
    required this.pageIndex,
    this.strokes = const [],
    this.textNotes = const [],
  });

  bool get isEmpty => strokes.isEmpty && textNotes.isEmpty;

  PageAnnotations copyWith({
    List<Stroke>? strokes,
    List<TextNote>? textNotes,
  }) =>
      PageAnnotations(
        pageIndex: pageIndex,
        strokes: strokes ?? this.strokes,
        textNotes: textNotes ?? this.textNotes,
      );

  Map<String, dynamic> toJson() => {
        'pageIndex': pageIndex,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'textNotes': textNotes.map((n) => n.toJson()).toList(),
      };

  factory PageAnnotations.fromJson(Map<String, dynamic> json) => PageAnnotations(
        pageIndex: json['pageIndex'] as int,
        strokes: (json['strokes'] as List<dynamic>?)
                ?.map((s) => Stroke.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        textNotes: (json['textNotes'] as List<dynamic>?)
                ?.map((n) => TextNote.fromJson(n as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
