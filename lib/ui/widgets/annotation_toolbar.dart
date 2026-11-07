import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/annotation.dart';
import '../theme/app_theme.dart';

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
    Color(0xFFF8FAFC), // White/Silver for dark stage
    Color(0xFF1E293B), // Charcoal Black
    Color(0xFFEF4444), // Conductor Red
    Color(0xFF3B82F6), // Blue
    Color(0xFF10B981), // Emerald
  ];

  static const List<Color> highlighterColors = [
    Color(0xFFFACC15), // Neon Yellow
    Color(0xFF4ADE80), // Neon Green
    Color(0xFFFB923C), // Neon Orange
    Color(0xFF38BDF8), // Neon Cyan
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF13151D).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pen Mode Toggle Capsule
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    icon: Icon(
                      isDrawingActive ? Icons.edit_rounded : Icons.edit_outlined,
                      color: isDrawingActive ? AppTheme.primaryLight : AppTheme.darkTextMuted,
                      size: 20,
                    ),
                    tooltip: isDrawingActive ? 'Stift aktiv' : 'Lese-Modus',
                    onPressed: onToggleDrawing,
                  ),

                  if (isDrawingActive) ...[
                    Container(
                      height: 20,
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.15),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                    ),

                    // Pen Tool
                    _ToolButton(
                      icon: Icons.draw_rounded,
                      isSelected: activeTool == StrokeType.pen,
                      activeColor: activeColor,
                      tooltip: 'Bleistift',
                      onTap: () => onSelectTool(StrokeType.pen),
                    ),

                    // Highlighter Tool
                    _ToolButton(
                      icon: Icons.brush_rounded,
                      isSelected: activeTool == StrokeType.highlighter,
                      activeColor: Colors.amber,
                      tooltip: 'Textmarker',
                      onTap: () => onSelectTool(StrokeType.highlighter),
                    ),

                    // Text Tool
                    _ToolButton(
                      icon: Icons.text_fields_rounded,
                      isSelected: activeTool == StrokeType.text,
                      activeColor: AppTheme.primaryLight,
                      tooltip: 'Text tippen',
                      onTap: () => onSelectTool(StrokeType.text),
                    ),

                    // Eraser Tool
                    _ToolButton(
                      icon: Icons.auto_fix_normal_rounded,
                      isSelected: activeTool == StrokeType.eraser,
                      activeColor: AppTheme.rose,
                      tooltip: 'Radierer',
                      onTap: () => onSelectTool(StrokeType.eraser),
                    ),

                    Container(
                      height: 20,
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.15),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                    ),

                    // Color Palette
                    if (activeTool != StrokeType.eraser)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: (activeTool == StrokeType.highlighter
                                ? highlighterColors
                                : penColors)
                            .map((color) {
                          final isSelected = activeColor.toARGB32() == color.toARGB32();
                          return GestureDetector(
                            onTap: () => onSelectColor(color),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.black45,
                                  width: isSelected ? 2.0 : 1.0,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.6),
                                          blurRadius: 5,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                    Container(
                      height: 20,
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.15),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                    ),

                    // Undo
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      color: AppTheme.darkTextSecondary,
                      tooltip: 'Rückgängig',
                      onPressed: onUndo,
                    ),

                    // Clear Page
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      color: AppTheme.rose,
                      tooltip: 'Seite leeren',
                      onPressed: onClearPage,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(color: activeColor.withValues(alpha: 0.6), width: 1.5)
                : null,
          ),
          child: Icon(
            icon,
            size: 19,
            color: isSelected ? activeColor : AppTheme.darkTextMuted,
          ),
        ),
      ),
    );
  }
}
