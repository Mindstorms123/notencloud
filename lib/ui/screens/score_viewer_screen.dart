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
  late PartFile _currentPart;
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
    _currentPart = widget.initialPart;
    _pdfController = PdfViewerController();
    _preparePdf();
  }

  Future<void> _preparePdf() async {
    setState(() {
      _isLoadingPdf = true;
      _errorMessage = null;
    });

    try {
      // Check if file is already cached locally
      final localPath = await widget.storageService.getLocalPdfPath(
        widget.song.id,
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

      // If not cached, download from Nextcloud
      if (widget.nextcloudService != null) {
        await widget.nextcloudService!.downloadPart(_currentPart, localPath);
        setState(() {
          _localPdfPath = localPath;
          _isLoadingPdf = false;
        });
        _loadPageAnnotations(1);
      } else {
        setState(() {
          _errorMessage = 'Noten-Datei nicht lokal verfügbar und keine Cloud-Verbindung aktiv.';
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
      widget.song.id,
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
      widget.song.id,
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

  @override
  Widget build(BuildContext context) {
    final currentAnn = _pageAnnotations[_currentPage] ?? PageAnnotations(pageIndex: _currentPage);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullscreen
          ? null
          : AppBar(
              backgroundColor: Colors.grey.shade900,
              foregroundColor: Colors.white,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.song.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _currentPart.fileName,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ),
              actions: [
                // Voice selector
                IconButton(
                  icon: const Icon(Icons.queue_music),
                  tooltip: 'Stimme wechseln',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (ctx) => VoiceSelectorSheet(
                        song: widget.song,
                        currentPart: _currentPart,
                        profile: widget.profile,
                        onSelectPart: _switchPart,
                      ),
                    );
                  },
                ),
                // Stage mode / Fullscreen
                IconButton(
                  icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                  tooltip: 'Bühnenmodus (Vollbild)',
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
          // PDF Canvas area
          if (_isLoadingPdf)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Lade Noten...', style: TextStyle(color: Colors.white70)),
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
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _preparePdf,
                      child: const Text('Erneut versuchen'),
                    ),
                  ],
                ),
              ),
            )
          else if (_localPdfPath != null)
            GestureDetector(
              // In fullscreen mode, double tap toggles appbar back
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
                        _activeColor = const Color(0xFFFFEB3B); // Yellow
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
                    // Undo on current page
                    if (currentAnn.strokes.isNotEmpty) {
                      final updated = List<Stroke>.from(currentAnn.strokes)..removeLast();
                      _onAnnotationsChanged(currentAnn.copyWith(strokes: updated));
                    }
                  },
                  onClearPage: () async {
                    await widget.annotationService.clearPageAnnotations(
                      widget.song.id,
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

          // Floating Page indicator & setlist navigation
          if (!_isLoadingPdf && _errorMessage == null)
            Positioned(
              top: _isFullscreen ? 16 : 8,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Seite $_currentPage / $_pageCount',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
