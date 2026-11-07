import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/annotation.dart';

class AnnotationCanvas extends StatefulWidget {
  final PageAnnotations annotations;
  final bool isDrawingActive;
  final StrokeType activeTool;
  final Color activeColor;
  final double activeStrokeWidth;
  final Function(PageAnnotations) onAnnotationsChanged;
  final Size pageSize;

  const AnnotationCanvas({
    super.key,
    required this.annotations,
    required this.isDrawingActive,
    required this.activeTool,
    required this.activeColor,
    required this.activeStrokeWidth,
    required this.onAnnotationsChanged,
    required this.pageSize,
  });

  @override
  State<AnnotationCanvas> createState() => _AnnotationCanvasState();
}

class _AnnotationCanvasState extends State<AnnotationCanvas> {
  final List<Point2D> _currentPoints = [];
  final List<PageAnnotations> _undoStack = [];
  final List<PageAnnotations> _redoStack = [];

  void _recordUndo() {
    _undoStack.add(widget.annotations);
    _redoStack.clear();
    if (_undoStack.length > 25) {
      _undoStack.removeAt(0);
    }
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(widget.annotations);
    final previous = _undoStack.removeLast();
    widget.onAnnotationsChanged(previous);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(widget.annotations);
    final next = _redoStack.removeLast();
    widget.onAnnotationsChanged(next);
  }

  Point2D _normalizePoint(Offset localPos) {
    final w = widget.pageSize.width > 0 ? widget.pageSize.width : 1.0;
    final h = widget.pageSize.height > 0 ? widget.pageSize.height : 1.0;
    return Point2D(
      x: (localPos.dx / w).clamp(0.0, 1.0),
      y: (localPos.dy / h).clamp(0.0, 1.0),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.isDrawingActive) return;

    // Palm rejection: If pen is preferred and a non-stylus touch arrives while drawing,
    // we can filter or accept depending on tool.
    _recordUndo();

    final point = _normalizePoint(event.localPosition);
    final pWithPressure = Point2D(
      x: point.x,
      y: point.y,
      pressure: event.pressure > 0 ? event.pressure : 1.0,
    );

    if (widget.activeTool == StrokeType.eraser) {
      _eraseNear(event.localPosition);
    } else {
      setState(() {
        _currentPoints.clear();
        _currentPoints.add(pWithPressure);
      });
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!widget.isDrawingActive) return;

    if (widget.activeTool == StrokeType.eraser) {
      _eraseNear(event.localPosition);
      return;
    }

    final point = _normalizePoint(event.localPosition);
    final pWithPressure = Point2D(
      x: point.x,
      y: point.y,
      pressure: event.pressure > 0 ? event.pressure : 1.0,
    );

    setState(() {
      _currentPoints.add(pWithPressure);
    });
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!widget.isDrawingActive) return;

    if (widget.activeTool == StrokeType.eraser) {
      return;
    }

    if (_currentPoints.length > 1) {
      final newStroke = Stroke(
        id: const Uuid().v4(),
        type: widget.activeTool,
        colorValue: widget.activeColor.value,
        width: widget.activeStrokeWidth,
        points: List.from(_currentPoints),
      );

      final updatedStrokes = List<Stroke>.from(widget.annotations.strokes)..add(newStroke);
      widget.onAnnotationsChanged(
        widget.annotations.copyWith(strokes: updatedStrokes),
      );
    }

    setState(() {
      _currentPoints.clear();
    });
  }

  void _eraseNear(Offset localPos) {
    final norm = _normalizePoint(localPos);
    const eraseRadius = 0.035; // Normalized radius

    final remainingStrokes = widget.annotations.strokes.where((stroke) {
      for (final pt in stroke.points) {
        final dx = pt.x - norm.x;
        final dy = pt.y - norm.y;
        if ((dx * dx + dy * dy) < (eraseRadius * eraseRadius)) {
          return false; // Remove stroke if any point is within eraser radius
        }
      }
      return true;
    }).toList();

    if (remainingStrokes.length != widget.annotations.strokes.length) {
      widget.onAnnotationsChanged(
        widget.annotations.copyWith(strokes: remainingStrokes),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.isDrawingActive
          ? HitTestBehavior.opaque
          : HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      child: CustomPaint(
        size: widget.pageSize,
        painter: _AnnotationPainter(
          annotations: widget.annotations,
          currentPoints: _currentPoints,
          currentTool: widget.activeTool,
          currentColor: widget.activeColor,
          currentWidth: widget.activeStrokeWidth,
          pageSize: widget.pageSize,
        ),
      ),
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final PageAnnotations annotations;
  final List<Point2D> currentPoints;
  final StrokeType currentTool;
  final Color currentColor;
  final double currentWidth;
  final Size pageSize;

  _AnnotationPainter({
    required this.annotations,
    required this.currentPoints,
    required this.currentTool,
    required this.currentColor,
    required this.currentWidth,
    required this.pageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Draw saved strokes
    for (final stroke in annotations.strokes) {
      _drawStroke(canvas, stroke.points, stroke.type, stroke.color, stroke.width, w, h);
    }

    // Draw current active stroke
    if (currentPoints.length > 1) {
      _drawStroke(canvas, currentPoints, currentTool, currentColor, currentWidth, w, h);
    }
  }

  void _drawStroke(
    Canvas canvas,
    List<Point2D> points,
    StrokeType type,
    Color color,
    double width,
    double w,
    double h,
  ) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (type == StrokeType.highlighter) {
      paint.color = color.withOpacity(0.35);
      paint.strokeWidth = width * 3.5;
    } else {
      paint.color = color;
      paint.strokeWidth = width;
    }

    final path = Path();
    path.moveTo(points.first.x * w, points.first.y * h);

    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].x * w, points[i].y * h);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}
