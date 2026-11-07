import 'dart:io';
import 'dart:ui';
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
  final Map<int, List<PageAnnotations>> _undoHistory = {};
  bool _isLoadingPdf = true;
  String? _localPdfPath;
  String? _errorMessage;
  bool _isFullscreen = false;
  double? _baseFitZoom;
  bool _isFitWidth = true;
  bool _isCloudSyncing = false;
  bool _isCloudSynced = false;

  @override
  void initState() {
    super.initState();
    _currentSong = widget.song;
    _currentPart = widget.initialPart;
    _currentSetlistIndex = widget.setlistIndex;
    _pdfController = PdfViewerController();
    _preparePdf();
  }

  void _zoomIn() {
    if (_pdfController?.isReady == true) {
      final current = _pdfController!.currentZoom;
      final newZoom = (current * 1.25).clamp(_pdfController!.minScale, _pdfController!.maxScale);
      _pdfController!.setZoom(_pdfController!.centerPosition, newZoom);
    }
  }

  void _zoomOut() {
    if (_pdfController?.isReady == true) {
      final current = _pdfController!.currentZoom;
      final newZoom = (current / 1.25).clamp(_pdfController!.minScale, _pdfController!.maxScale);
      _pdfController!.setZoom(_pdfController!.centerPosition, newZoom);
    }
  }

  void _toggleZoomFit() {
    if (_pdfController?.isReady == true) {
      if (_isFitWidth) {
        // Toggle to Fit Page (show entire page height)
        final matrix = _pdfController!.calcMatrixForFit(pageNumber: _currentPage);
        if (matrix != null) {
          _pdfController!.goTo(matrix);
          setState(() {
            _isFitWidth = false;
          });
        }
      } else {
        // Toggle to Fit Width (fill readable page width)
        final matrix = _pdfController!.calcMatrixFitWidthForPage(pageNumber: _currentPage) ??
            _pdfController!.calcMatrixForFit(pageNumber: _currentPage);
        if (matrix != null) {
          _pdfController!.goTo(matrix);
          setState(() {
            _isFitWidth = true;
          });
        }
      }
    }
  }

  Future<void> _preparePdf() async {
    setState(() {
      _isLoadingPdf = true;
      _errorMessage = null;
      _baseFitZoom = null;
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
      nextcloudService: widget.nextcloudService,
    );
    if (mounted) {
      setState(() {
        _pageAnnotations[page] = ann;
        if (ann.isSyncedWithCloud) _isCloudSynced = true;
      });
    }

    // Background check for newer cloud version
    if (widget.nextcloudService != null && widget.nextcloudService!.account.isConfigured) {
      widget.nextcloudService!.downloadPageAnnotations(
        _currentSong.id,
        _currentPart.id,
        page,
      ).then((cloudAnn) {
        if (cloudAnn != null && mounted) {
          final localTime = ann.updatedAt;
          final cloudTime = cloudAnn.updatedAt;
          if (localTime == null || (cloudTime != null && cloudTime.isAfter(localTime))) {
            widget.annotationService.saveAnnotations(
              _currentSong.id,
              _currentPart.id,
              cloudAnn,
            );
            setState(() {
              _pageAnnotations[page] = cloudAnn;
              _isCloudSynced = true;
            });
          }
        }
      }).catchError((_) {});
    }
  }

  Future<void> _saveCurrentAnnotations(int page, PageAnnotations ann) async {
    final withTime = ann.copyWith(updatedAt: DateTime.now());
    _pageAnnotations[page] = withTime;
    if (widget.nextcloudService != null && widget.nextcloudService!.account.isConfigured) {
      setState(() => _isCloudSyncing = true);
    }
    final ok = await widget.annotationService.saveAnnotations(
      _currentSong.id,
      _currentPart.id,
      withTime,
      nextcloudService: widget.nextcloudService,
    );
    if (mounted) {
      setState(() {
        _isCloudSyncing = false;
        if (ok) _isCloudSynced = true;
      });
    }
  }

  void _onAnnotationsChanged(PageAnnotations updated) {
    final current = _pageAnnotations[_currentPage] ?? PageAnnotations(pageIndex: _currentPage);
    _undoHistory.putIfAbsent(_currentPage, () => []).add(current);
    if (_undoHistory[_currentPage]!.length > 30) {
      _undoHistory[_currentPage]!.removeAt(0);
    }
    setState(() {
      _pageAnnotations[_currentPage] = updated;
    });
    _saveCurrentAnnotations(_currentPage, updated);
  }

  void _switchPart(PartFile newPart) {
    setState(() {
      _currentPart = newPart;
      _pageAnnotations.clear();
      _undoHistory.clear();
      _currentPage = 1;
      _baseFitZoom = null;
      _isFitWidth = true;
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
      _baseFitZoom = null;
      _isFitWidth = true;
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
    bool isExactVoice = widget.profile.voiceNumber == 0 ||
        _currentPart.detectedVoice == widget.profile.voiceNumber ||
        _currentPart.isCombinedVoice ||
        _currentPart.detectedVoice == 0;
    if (widget.profile.instrument == 'Percussion' &&
        widget.profile.percussionInstrument.isNotEmpty &&
        widget.profile.percussionInstrument != 'Alle') {
      final partSub = VoiceMatcher.detectPercussionSubInstrument(_currentPart.fileName);
      if (partSub.toLowerCase() != widget.profile.percussionInstrument.toLowerCase()) {
        isExactVoice = false;
      }
    }
    final isDoc = _currentSong.isDocumentOrList;
    final voiceColor = isDoc
        ? AppTheme.primaryLight
        : (isExactVoice ? AppTheme.emerald : AppTheme.amber);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(_isFullscreen ? 0.0 : kToolbarHeight),
        child: AnimatedSlide(
          offset: _isFullscreen ? const Offset(0, -1) : Offset.zero,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          child: AnimatedOpacity(
            opacity: _isFullscreen ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: AppBar(
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
                          decoration: BoxDecoration(
                            color: voiceColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            isDoc
                                ? _currentPart.fileName
                                : (isExactVoice
                                    ? _currentPart.fileName
                                    : (widget.profile.instrument == 'Percussion' &&
                                            widget.profile.percussionInstrument.isNotEmpty &&
                                            widget.profile.percussionInstrument != 'Alle'
                                        ? 'Keine ${widget.profile.percussionInstrument} • Ausweichstimme: ${_currentPart.fileName}'
                                        : 'Keine ${widget.profile.voiceNumber}. Stimme • Ausweichstimme: ${_currentPart.fileName}')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: voiceColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: voiceColor, size: 16),
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
          ),
        ),
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
            PdfViewer.file(
              _localPdfPath!,
              controller: _pdfController,
              params: PdfViewerParams(
                backgroundColor: Colors.black,
                onGeneralTap: (context, controller, details) {
                  if (_isDrawingActive) return false;
                  if (details.type == PdfViewerGeneralTapType.doubleTap) {
                    setState(() {
                      _isFullscreen = !_isFullscreen;
                    });
                    return true;
                  }
                  return false;
                },
                onViewerReady: (document, controller) {
                  if (mounted) {
                    setState(() {
                      _baseFitZoom = controller.currentZoom;
                    });
                  }
                },
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
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _isFullscreen
                      ? () {
                          setState(() {
                            _isFullscreen = false;
                          });
                        }
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.darkBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Seite $_currentPage / $_pageCount',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        if (_isFullscreen) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.fullscreen_exit_rounded, color: AppTheme.primaryLight, size: 16),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Floating Zoom Controls (bottom left)
          _buildZoomControls(),

          // Annotation Tools: Corner Pen Button when inactive, Full Toolbar when active, Hidden in Fullscreen
          if (!_isFullscreen && !_isLoadingPdf && _errorMessage == null)
            if (!_isDrawingActive)
              Positioned(
                bottom: 24,
                right: 20,
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFF13151D).withValues(alpha: 0.88),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 14,
                            spreadRadius: 1,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.edit_rounded, color: AppTheme.primaryLight, size: 22),
                        tooltip: 'Stift & Textnotizen',
                        onPressed: () {
                          setState(() {
                            _isDrawingActive = true;
                          });
                        },
                      ),
                    ),
                  ),
                ),
              )
            else
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
                    isCloudSyncing: _isCloudSyncing,
                    isCloudSynced: _isCloudSynced,
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
                        } else if (tool == StrokeType.text) {
                          _activeColor = const Color(0xFFEF4444);
                        }
                      });
                    },
                    onSelectColor: (c) {
                      setState(() {
                        _activeColor = c;
                      });
                    },
                    onUndo: () {
                      final history = _undoHistory[_currentPage];
                      if (history != null && history.isNotEmpty) {
                        final previous = history.removeLast();
                        setState(() {
                          _pageAnnotations[_currentPage] = previous;
                        });
                        _saveCurrentAnnotations(_currentPage, previous);
                      } else {
                        if (currentAnn.textNotes.isNotEmpty) {
                          final updated = List<TextNote>.from(currentAnn.textNotes)..removeLast();
                          _onAnnotationsChanged(currentAnn.copyWith(textNotes: updated));
                        } else if (currentAnn.strokes.isNotEmpty) {
                          final updated = List<Stroke>.from(currentAnn.strokes)..removeLast();
                          _onAnnotationsChanged(currentAnn.copyWith(strokes: updated));
                        }
                      }
                    },
                    onClearPage: () async {
                      await widget.annotationService.clearPageAnnotations(
                        _currentSong.id,
                        _currentPart.id,
                        _currentPage,
                        nextcloudService: widget.nextcloudService,
                      );
                      setState(() {
                        _pageAnnotations[_currentPage] = PageAnnotations(pageIndex: _currentPage);
                        _undoHistory[_currentPage]?.clear();
                        _isCloudSynced = true;
                      });
                    },
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildZoomControls() {
    if (_isFullscreen || _isDrawingActive || _isLoadingPdf || _errorMessage != null) {
      return const SizedBox.shrink();
    }

    final controller = _pdfController;
    if (controller == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 24,
      left: 20,
      child: ValueListenableBuilder<Matrix4>(
        valueListenable: controller,
        builder: (context, matrix, _) {
          final currentZoom = controller.isReady ? controller.currentZoom : 1.0;
          final base = _baseFitZoom ??
              (controller.isReady
                  ? (controller.alternativeFitScale ?? controller.coverScale)
                  : 1.0);
          final percent = base > 0 ? ((currentZoom / base) * 100).round() : 100;

          return ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF13151D).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 14,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, color: AppTheme.primaryLight, size: 20),
                      tooltip: 'Verkleinern',
                      visualDensity: VisualDensity.compact,
                      onPressed: _zoomOut,
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _toggleZoomFit,
                      child: Tooltip(
                        message: _isFitWidth ? 'Auf ganze Seite einpassen' : 'Auf Seitenbreite einpassen',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isFitWidth ? Icons.fit_screen_rounded : Icons.aspect_ratio_rounded,
                                color: Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$percent%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, color: AppTheme.primaryLight, size: 20),
                      tooltip: 'Vergrößern',
                      visualDensity: VisualDensity.compact,
                      onPressed: _zoomIn,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
