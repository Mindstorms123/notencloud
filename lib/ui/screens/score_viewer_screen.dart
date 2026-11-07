import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../models/annotation.dart';
import '../../models/musician_profile.dart';
import '../../models/song.dart';
import '../../models/setlist.dart';
import '../../services/annotation_service.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_matcher.dart';
import '../theme/app_theme.dart';
import '../widgets/annotation_canvas.dart';
import '../widgets/annotation_toolbar.dart';
import '../widgets/voice_selector_sheet.dart';

class ScoreViewerScreen extends StatefulWidget {
  final Song song;
  final PartFile initialPart;
  final MusicianProfile profile;
  final StorageService storageService;
  final AnnotationService annotationService;
  final NextcloudService? nextcloudService;
  final Setlist? currentSetlist;
  final int setlistIndex;

  const ScoreViewerScreen({
    super.key,
    required this.song,
    required this.initialPart,
    required this.profile,
    required this.storageService,
    required this.annotationService,
    this.nextcloudService,
    this.currentSetlist,
    this.setlistIndex = 0,
  });

  @override
  State<ScoreViewerScreen> createState() => _ScoreViewerScreenState();
}

class _ScoreViewerScreenState extends State<ScoreViewerScreen> {
  late Song _currentSong;
  late PartFile _currentPart;
  late int _currentSetlistIndex;

  PdfViewerController? _pdfController;
  int _currentPage = 1;
  int _pageCount = 1;

  // Annotation states
  bool _isDrawingActive = false;
  StrokeType _activeTool = StrokeType.pen;
  Color _activeColor = Colors.black87;
  double _activeStrokeWidth = 2.0;
  final Map<int, PageAnnotations> _pageAnnotations = {};
  bool _isLoadingPdf = true;
  String? _localPdfPath;
  String? _errorMessage;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _currentSong = widget.song;
    _currentPart = widget.initialPart;
    _currentSetlistIndex = widget.setlistIndex;
    _pdfController = PdfViewerController();
    _preparePdf();
  }

  Future<void> _preparePdf() async {
    setState(() {
      _isLoadingPdf = true;
      _errorMessage = null;
    });

    try {
      final localPath = await widget.storageService.getLocalPdfPath(
        _currentSong.id,
        _currentPart.fileName,
      );

      final file = File(localPath);
      if (await file.exists()) {
        setState(() {
          _localPdfPath = localPath;
          _isLoadingPdf = false;
        });
        _loadPageAnnotations(1);
        return;
      }

      if (widget.nextcloudService != null) {
        await widget.nextcloudService!.downloadPart(_currentPart, localPath);
        setState(() {
          _localPdfPath = localPath;
          _isLoadingPdf = false;
        });
        _loadPageAnnotations(1);
      } else {
        setState(() {
          _errorMessage = 'Notendatei nicht im lokalen Speicher und keine Cloud-Verbindung aktiv.';
          _isLoadingPdf = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Fehler beim Laden der Noten: $e';
        _isLoadingPdf = false;
      });
    }
  }

  Future<void> _loadPageAnnotations(int page) async {
    if (_pageAnnotations.containsKey(page)) return;
    final ann = await widget.annotationService.loadAnnotations(
      _currentSong.id,
      _currentPart.id,
      page,
    );
    if (mounted) {
      setState(() {
        _pageAnnotations[page] = ann;
      });
    }
  }

  Future<void> _saveCurrentAnnotations(int page, PageAnnotations ann) async {
    _pageAnnotations[page] = ann;
    await widget.annotationService.saveAnnotations(
      _currentSong.id,
      _currentPart.id,
      ann,
    );
  }

  void _onAnnotationsChanged(PageAnnotations updated) {
    setState(() {
      _pageAnnotations[_currentPage] = updated;
    });
    _saveCurrentAnnotations(_currentPage, updated);
  }

  void _switchPart(PartFile newPart) {
    setState(() {
      _currentPart = newPart;
      _pageAnnotations.clear();
      _currentPage = 1;
    });
    _preparePdf();
  }

  void _navigateToSetlistItem(int targetIndex) {
    if (widget.currentSetlist == null) return;
    final items = widget.currentSetlist!.items;
    if (targetIndex < 0 || targetIndex >= items.length) return;

    final targetItem = items[targetIndex];
    if (targetItem.isIntermission) {
      // Skip intermission in the direction
      final step = targetIndex > _currentSetlistIndex ? 1 : -1;
      _navigateToSetlistItem(targetIndex + step);
      return;
    }

    final allSongs = widget.storageService.getCachedSongs();
    final nextSong = allSongs.firstWhere(
      (s) => s.id == targetItem.songId || s.folderName == targetItem.songFolderName,
      orElse: () => Song(
        id: targetItem.songId,
        title: targetItem.songTitle,
        folderName: targetItem.songFolderName,
        remoteFolderPath: '',
      ),
    );

    final bestMatch = VoiceMatcher.findBestMatch(nextSong.parts, widget.profile);
    if (bestMatch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.amber,
          content: Text('Keine Stimme für "${nextSong.title}" gefunden.'),
        ),
      );
      return;
    }

    setState(() {
      _currentSetlistIndex = targetIndex;
      _currentSong = nextSong;
      _currentPart = bestMatch;
      _pageAnnotations.clear();
      _currentPage = 1;
    });
    _preparePdf();
  }

  bool get _hasPrevInSetlist {
    if (widget.currentSetlist == null) return false;
    for (int i = _currentSetlistIndex - 1; i >= 0; i--) {
      if (!widget.currentSetlist!.items[i].isIntermission) return true;
    }
    return false;
  }

  bool get _hasNextInSetlist {
    if (widget.currentSetlist == null) return false;
    final items = widget.currentSetlist!.items;
    for (int i = _currentSetlistIndex + 1; i < items.length; i++) {
      if (!items[i].isIntermission) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final currentAnn = _pageAnnotations[_currentPage] ?? PageAnnotations(pageIndex: _currentPage);
    final inSetlistMode = widget.currentSetlist != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullscreen
          ? null
          : AppBar(
              backgroundColor: AppTheme.darkSurface,
              foregroundColor: AppTheme.darkTextPrimary,
              elevation: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentSong.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: -0.2),
                  ),
                  InkWell(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: AppTheme.darkSurface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        builder: (ctx) => VoiceSelectorSheet(
                          song: _currentSong,
                          currentPart: _currentPart,
                          profile: widget.profile,
                          onSelectPart: _switchPart,
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppTheme.emerald,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _currentPart.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppTheme.emerald, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: AppTheme.emerald, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                // Voice selector button
                IconButton(
                  icon: const Icon(Icons.queue_music_rounded, color: AppTheme.primaryLight),
                  tooltip: 'Stimme wechseln',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: AppTheme.darkSurface,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (ctx) => VoiceSelectorSheet(
                        song: _currentSong,
                        currentPart: _currentPart,
                        profile: widget.profile,
                        onSelectPart: _switchPart,
                      ),
                    );
                  },
                ),
                // Fullscreen Stage Mode Toggle
                IconButton(
                  icon: Icon(
                    _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                  tooltip: 'Vollbildmodus',
                  onPressed: () {
                    setState(() {
                      _isFullscreen = !_isFullscreen;
                    });
                  },
                ),
              ],
            ),
      body: Stack(
        children: [
          // PDF Display
          if (_isLoadingPdf)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryLight),
                  SizedBox(height: 16),
                  Text('Lade Noten...', style: TextStyle(color: AppTheme.darkTextSecondary)),
                ],
              ),
            )
          else if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppTheme.rose, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.darkTextSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _preparePdf,
                      child: const Text('Erneut versuchen'),
                    ),
                  ],
                ),
              ),
            )
          else if (_localPdfPath != null)
            GestureDetector(
              onDoubleTap: () {
                setState(() {
                  _isFullscreen = !_isFullscreen;
                });
              },
              child: PdfViewer.file(
                _localPdfPath!,
                controller: _pdfController,
                params: PdfViewerParams(
                  backgroundColor: Colors.black,
                  onPageChanged: (page) {
                    if (page != null) {
                      setState(() {
                        _currentPage = page;
                      });
                      _loadPageAnnotations(page);
                    }
                  },
                  onDocumentChanged: (document) {
                    if (document != null) {
                      setState(() {
                        _pageCount = document.pages.length;
                      });
                    }
                  },
                  pageOverlaysBuilder: (context, pageRect, page) {
                    if (page.pageNumber != _currentPage) {
                      return [];
                    }
                    return [
                      Positioned(
                        left: 0,
                        top: 0,
                        width: pageRect.width,
                        height: pageRect.height,
                        child: AnnotationCanvas(
                          annotations: currentAnn,
                          isDrawingActive: _isDrawingActive,
                          activeTool: _activeTool,
                          activeColor: _activeColor,
                          activeStrokeWidth: _activeStrokeWidth,
                          pageSize: Size(pageRect.width, pageRect.height),
                          onAnnotationsChanged: _onAnnotationsChanged,
                        ),
                      ),
                    ];
                  },
                ),
              ),
            ),

          // Floating Setlist Stage Navigation Bar (when in Setlist mode)
          if (inSetlistMode && !_isLoadingPdf)
            Positioned(
              top: _isFullscreen ? 16 : 8,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded, size: 14, color: Colors.white),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _hasPrevInSetlist
                          ? () => _navigateToSetlistItem(_currentSetlistIndex - 1)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_currentSetlistIndex + 1} / ${widget.currentSetlist!.items.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _hasNextInSetlist
                          ? () => _navigateToSetlistItem(_currentSetlistIndex + 1)
                          : null,
                    ),
                  ],
                ),
              ),
            ),

          // Floating Page indicator (top right)
          if (!_isLoadingPdf && _errorMessage == null)
            Positioned(
              top: _isFullscreen ? 16 : 8,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: Text(
                  'Seite $_currentPage / $_pageCount',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),

          // Floating Annotation Toolbar (bottom center)
          if (!_isLoadingPdf && _errorMessage == null)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: AnnotationToolbar(
                  isDrawingActive: _isDrawingActive,
                  activeTool: _activeTool,
                  activeColor: _activeColor,
                  activeStrokeWidth: _activeStrokeWidth,
                  onToggleDrawing: () {
                    setState(() {
                      _isDrawingActive = !_isDrawingActive;
                    });
                  },
                  onSelectTool: (tool) {
                    setState(() {
                      _activeTool = tool;
                      if (tool == StrokeType.highlighter) {
                        _activeColor = const Color(0xFFFFEB3B);
                        _activeStrokeWidth = 8.0;
                      } else if (tool == StrokeType.pen) {
                        _activeColor = Colors.black87;
                        _activeStrokeWidth = 2.0;
                      }
                    });
                  },
                  onSelectColor: (c) {
                    setState(() {
                      _activeColor = c;
                    });
                  },
                  onUndo: () {
                    if (currentAnn.strokes.isNotEmpty) {
                      final updated = List<Stroke>.from(currentAnn.strokes)..removeLast();
                      _onAnnotationsChanged(currentAnn.copyWith(strokes: updated));
                    }
                  },
                  onClearPage: () async {
                    await widget.annotationService.clearPageAnnotations(
                      _currentSong.id,
                      _currentPart.id,
                      _currentPage,
                    );
                    setState(() {
                      _pageAnnotations[_currentPage] = PageAnnotations(pageIndex: _currentPage);
                    });
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
