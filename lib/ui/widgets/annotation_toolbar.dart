import 'package:flutter/material.dart';
import '../../models/annotation.dart';

class AnnotationToolbar extends StatelessWidget {
  final bool isDrawingActive;
  final StrokeType activeTool;
  final Color activeColor;
  final double activeStrokeWidth;
  final VoidCallback onToggleDrawing;
  final Function(StrokeType) onSelectTool;
  final Function(Color) onSelectColor;
  final VoidCallback onUndo;
  final VoidCallback onClearPage;

  const AnnotationToolbar({
    super.key,
    required this.isDrawingActive,
    required this.activeTool,
    required this.activeColor,
    required this.activeStrokeWidth,
    required this.onToggleDrawing,
    required this.onSelectTool,
    required this.onSelectColor,
    required this.onUndo,
    required this.onClearPage,
  });

  static const List<Color> penColors = [
    Colors.black87,
    Color(0xFFD32F2F), // Red (Dirigenten-Rot)
    Color(0xFF1976D2), // Blue
    Color(0xFF388E3C), // Green
  ];

  static const List<Color> highlighterColors = [
    Color(0xFFFFEB3B), // Yellow
    Color(0xFF76FF03), // Lime
    Color(0xFFFF9800), // Orange
    Color(0xFF00E5FF), // Cyan
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      color: Theme.of(context).colorScheme.surface.withOpacity(0.92),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Master Pen mode toggle
            IconButton(
              icon: Icon(
                isDrawingActive ? Icons.edit : Icons.edit_off_outlined,
                color: isDrawingActive ? Theme.of(context).primaryColor : Colors.grey,
              ),
              tooltip: isDrawingActive ? 'Stift aktiv' : 'Lese-Modus (Stift aus)',
              onPressed: onToggleDrawing,
            ),
            if (isDrawingActive) ...[
              const VerticalDivider(width: 16, thickness: 1),
              // Pen tool
              IconButton(
                icon: const Icon(Icons.brush),
                color: activeTool == StrokeType.pen ? activeColor : Colors.grey,
                tooltip: 'Bleistift / Stift',
                onPressed: () => onSelectTool(StrokeType.pen),
              ),
              // Highlighter tool
              IconButton(
                icon: const Icon(Icons.highlight),
                color: activeTool == StrokeType.highlighter ? Colors.amber : Colors.grey,
                tooltip: 'Textmarker',
                onPressed: () => onSelectTool(StrokeType.highlighter),
              ),
              // Eraser tool
              IconButton(
                icon: const Icon(Icons.auto_fix_normal),
                color: activeTool == StrokeType.eraser ? Colors.redAccent : Colors.grey,
                tooltip: 'Radiergummi',
                onPressed: () => onSelectTool(StrokeType.eraser),
              ),
              const VerticalDivider(width: 16, thickness: 1),
              // Color selection
              if (activeTool != StrokeType.eraser)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: (activeTool == StrokeType.highlighter
                          ? highlighterColors
                          : penColors)
                      .map((color) {
                    final isSelected = activeColor.value == color.value;
                    return GestureDetector(
                      onTap: () => onSelectColor(color),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.black26,
                            width: isSelected ? 2.5 : 1.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withOpacity(0.5),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  )
                                ]
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const VerticalDivider(width: 16, thickness: 1),
              // Undo
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Rückgängig',
                onPressed: onUndo,
              ),
              // Clear page
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Seite leeren',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Anmerkungen löschen?'),
                      content: const Text(
                          'Möchtest du wirklich alle Zeichnungen auf dieser Seite löschen?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Abbrechen'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            onClearPage();
                          },
                          child: const Text('Löschen', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
