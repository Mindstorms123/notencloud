import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/annotation.dart';
import '../theme/app_theme.dart';

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
  Offset? _pointerDownPos;
  DateTime? _pointerDownTime;

  // Dragging state for text notes
  String? _draggingNoteId;
  Point2D? _draggingPos;

  Point2D _normalizePoint(Offset localPos) {
    final w = widget.pageSize.width > 0 ? widget.pageSize.width : 1.0;
    final h = widget.pageSize.height > 0 ? widget.pageSize.height : 1.0;
    return Point2D(
      x: (localPos.dx / w).clamp(0.0, 1.0),
      y: (localPos.dy / h).clamp(0.0, 1.0),
    );
  }

  bool _isNearExistingNote(Offset localPos) {
    final norm = _normalizePoint(localPos);
    final w = widget.pageSize.width > 0 ? widget.pageSize.width : 1.0;
    final h = widget.pageSize.height > 0 ? widget.pageSize.height : 1.0;
    for (final note in widget.annotations.textNotes) {
      final dx = (note.position.x - norm.x) * w;
      final dy = (note.position.y - norm.y) * h;
      if (dx.abs() < 50.0 && dy.abs() < 24.0) {
        return true;
      }
    }
    return false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.isDrawingActive) return;

    if (widget.activeTool == StrokeType.text) {
      _pointerDownPos = event.localPosition;
      _pointerDownTime = DateTime.now();
      return;
    }

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

    if (widget.activeTool == StrokeType.text) {
      return;
    }

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

    if (widget.activeTool == StrokeType.text) {
      if (_pointerDownPos != null && _pointerDownTime != null) {
        final dist = (event.localPosition - _pointerDownPos!).distance;
        final duration = DateTime.now().difference(_pointerDownTime!);
        if (dist < 18.0 && duration.inMilliseconds < 600) {
          if (!_isNearExistingNote(event.localPosition)) {
            _showTextEntryDialog(localPos: event.localPosition);
          }
        }
      }
      _pointerDownPos = null;
      _pointerDownTime = null;
      return;
    }

    if (widget.activeTool == StrokeType.eraser) {
      return;
    }

    if (_currentPoints.length > 1) {
      final newStroke = Stroke(
        id: const Uuid().v4(),
        type: widget.activeTool,
        colorValue: widget.activeColor.toARGB32(),
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
          return false;
        }
      }
      return true;
    }).toList();

    final remainingNotes = widget.annotations.textNotes.where((note) {
      final dx = note.position.x - norm.x;
      final dy = note.position.y - norm.y;
      return (dx * dx + dy * dy) >= (eraseRadius * eraseRadius);
    }).toList();

    if (remainingStrokes.length != widget.annotations.strokes.length ||
        remainingNotes.length != widget.annotations.textNotes.length) {
      widget.onAnnotationsChanged(
        widget.annotations.copyWith(
          strokes: remainingStrokes,
          textNotes: remainingNotes,
        ),
      );
    }
  }

  Future<void> _showTextEntryDialog({
    Offset? localPos,
    TextNote? existingNote,
  }) async {
    final isEditing = existingNote != null;
    final textController = TextEditingController(text: existingNote?.text ?? '');
    double selectedFontSize = existingNote?.fontSize ?? 15.0;
    Color selectedColor = existingNote != null
        ? existingNote.color
        : (widget.activeColor.toARGB32() != Colors.black87.toARGB32()
            ? widget.activeColor
            : const Color(0xFFEF4444));
    bool hasBackground = existingNote?.hasBackground ?? true;

    final quickChips = [
      'Solo',
      'Tutti',
      'Mit Dämpfer',
      'Ohne Dämpfer',
      'Attacca',
      'Ohne Wdh.',
      '1. Mal',
      '2. Mal',
      'p',
      'f',
      'ff',
      'Coda',
      'Rit.',
      'Blick!',
    ];

    final colorOptions = [
      const Color(0xFFEF4444), // Conductor Red
      const Color(0xFF1E293B), // Charcoal / Black
      const Color(0xFF2563EB), // Blue
      const Color(0xFF10B981), // Emerald
      const Color(0xFFF59E0B), // Amber
      const Color(0xFF8B5CF6), // Purple
    ];

    final fontSizes = [12.0, 15.0, 20.0, 26.0];
    final fontSizeLabels = ['Klein', 'Normal', 'Groß', 'Extra'];

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: AppTheme.darkSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: AppTheme.darkBorder, width: 1),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.text_fields_rounded,
                      color: AppTheme.primaryLight,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing ? 'Notiz bearbeiten' : 'Text in Noten tippen',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // Quick Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: quickChips.map((chip) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6, bottom: 4),
                            child: ActionChip(
                              label: Text(
                                chip,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.darkTextPrimary,
                                ),
                              ),
                              backgroundColor: AppTheme.darkCard,
                              side: const BorderSide(color: AppTheme.darkBorder),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setModalState(() {
                                  final cur = textController.text.trim();
                                  if (cur.isEmpty) {
                                    textController.text = chip;
                                  } else {
                                    textController.text = '$cur $chip';
                                  }
                                  textController.selection = TextSelection.fromPosition(
                                    TextPosition(offset: textController.text.length),
                                  );
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Text Input Field
                    TextField(
                      controller: textController,
                      autofocus: true,
                      style: const TextStyle(
                        color: AppTheme.darkTextPrimary,
                        fontSize: 16,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'z.B. Solo, Mit Dämpfer, Attacca...',
                        hintStyle: const TextStyle(color: AppTheme.darkTextMuted, fontSize: 14),
                        filled: true,
                        fillColor: AppTheme.darkCard,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.darkBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.darkBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.primaryLight, width: 1.5),
                        ),
                        suffixIcon: textController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18, color: AppTheme.darkTextMuted),
                                onPressed: () {
                                  setModalState(() {
                                    textController.clear();
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (text) => setModalState(() {}),
                    ),

                    const SizedBox(height: 16),

                    // Color Picker Row
                    const Text(
                      'FARBE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: AppTheme.darkTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: colorOptions.map((c) {
                        final isSelected = selectedColor.toARGB32() == c.toARGB32();
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedColor = c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: 2.5,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: c.withValues(alpha: 0.6),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    // Font Size Selector
                    const Text(
                      'SCHRIFTGRÖSSE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: AppTheme.darkTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(fontSizes.length, (index) {
                        final size = fontSizes[index];
                        final label = fontSizeLabels[index];
                        final isSelected = selectedFontSize == size;

                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: index == 0 ? 0 : 4,
                              right: index == fontSizes.length - 1 ? 0 : 4,
                            ),
                            child: InkWell(
                              onTap: () => setModalState(() => selectedFontSize = size),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryLight.withValues(alpha: 0.2)
                                      : AppTheme.darkCard,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected ? AppTheme.primaryLight : AppTheme.darkBorder,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? AppTheme.primaryLight : AppTheme.darkTextSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 14),

                    // Background Badge Toggle
                    InkWell(
                      onTap: () => setModalState(() => hasBackground = !hasBackground),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        child: Row(
                          children: [
                            Icon(
                              hasBackground ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              size: 20,
                              color: hasBackground ? AppTheme.primaryLight : AppTheme.darkTextMuted,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Lesbarkeit: Weißer Kasten über Notenlinien',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.darkTextSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (isEditing)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppTheme.rose),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Löschen'),
                    onPressed: () {
                      final updatedNotes = widget.annotations.textNotes
                          .where((n) => n.id != existingNote.id)
                          .toList();
                      widget.onAnnotationsChanged(
                        widget.annotations.copyWith(textNotes: updatedNotes),
                      );
                      Navigator.of(ctx).pop();
                    },
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Abbrechen', style: TextStyle(color: AppTheme.darkTextMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onPressed: textController.text.trim().isEmpty
                      ? null
                      : () {
                          final text = textController.text.trim();
                          if (isEditing) {
                            final updatedNotes = widget.annotations.textNotes.map((n) {
                              if (n.id == existingNote.id) {
                                return n.copyWith(
                                  text: text,
                                  colorValue: selectedColor.toARGB32(),
                                  fontSize: selectedFontSize,
                                  hasBackground: hasBackground,
                                );
                              }
                              return n;
                            }).toList();
                            widget.onAnnotationsChanged(
                              widget.annotations.copyWith(textNotes: updatedNotes),
                            );
                          } else {
                            final normPos = localPos != null
                                ? _normalizePoint(localPos)
                                : const Point2D(x: 0.5, y: 0.5);
                            final newNote = TextNote(
                              id: const Uuid().v4(),
                              text: text,
                              position: normPos,
                              colorValue: selectedColor.toARGB32(),
                              fontSize: selectedFontSize,
                              hasBackground: hasBackground,
                            );
                            final updatedNotes = List<TextNote>.from(widget.annotations.textNotes)..add(newNote);
                            widget.onAnnotationsChanged(
                              widget.annotations.copyWith(textNotes: updatedNotes),
                            );
                          }
                          Navigator.of(ctx).pop();
                        },
                  child: Text(isEditing ? 'Übernehmen' : 'Einfügen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTextNoteWidget(TextNote note, double w, double h) {
    final pos = (_draggingNoteId == note.id && _draggingPos != null)
        ? _draggingPos!
        : note.position;

    final px = pos.x * w;
    final py = pos.y * h;

    return Positioned(
      left: px,
      top: py,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: IgnorePointer(
          ignoring: !widget.isDrawingActive,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (widget.isDrawingActive) {
                _showTextEntryDialog(existingNote: note);
              }
            },
            onPanStart: (details) {
              setState(() {
                _draggingNoteId = note.id;
                _draggingPos = note.position;
              });
            },
            onPanUpdate: (details) {
              if (_draggingNoteId == note.id) {
                final curPx = (_draggingPos?.x ?? note.position.x) * w + details.delta.dx;
                final curPy = (_draggingPos?.y ?? note.position.y) * h + details.delta.dy;
                setState(() {
                  _draggingPos = Point2D(
                    x: (curPx / w).clamp(0.0, 1.0),
                    y: (curPy / h).clamp(0.0, 1.0),
                  );
                });
              }
            },
            onPanEnd: (details) {
              if (_draggingNoteId == note.id && _draggingPos != null) {
                final updatedNotes = widget.annotations.textNotes.map((n) {
                  if (n.id == note.id) {
                    return n.copyWith(position: _draggingPos);
                  }
                  return n;
                }).toList();
                widget.onAnnotationsChanged(
                  widget.annotations.copyWith(textNotes: updatedNotes),
                );
              }
              setState(() {
                _draggingNoteId = null;
                _draggingPos = null;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: note.hasBackground
                    ? Colors.white.withValues(alpha: 0.94)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: widget.isDrawingActive
                      ? note.color.withValues(alpha: 0.8)
                      : (note.hasBackground ? Colors.black26 : Colors.transparent),
                  width: widget.isDrawingActive ? 1.5 : 0.8,
                ),
                boxShadow: note.hasBackground
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 4,
                          offset: const Offset(0, 1.5),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.isDrawingActive) ...[
                    Icon(
                      Icons.drag_indicator_rounded,
                      size: (note.fontSize * 0.85).clamp(11.0, 16.0),
                      color: note.color.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 2),
                  ],
                  Text(
                    note.text,
                    style: TextStyle(
                      color: note.color,
                      fontSize: note.fontSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.pageSize.width;
    final h = widget.pageSize.height;

    return IgnorePointer(
      ignoring: !widget.isDrawingActive,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Drawing Canvas & Touch Area
            Positioned.fill(
              child: Listener(
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
              ),
            ),

            // 2. Interactive Text Notes Overlay
            ...widget.annotations.textNotes.map((note) => _buildTextNoteWidget(note, w, h)),
          ],
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
      paint.color = color.withValues(alpha: 0.35);
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
