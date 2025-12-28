import 'package:cached_network_image/cached_network_image.dart';
import 'package:comic_reader/data/comic_repository_firebase.dart';
import 'package:comic_reader/models/comic.dart';
import 'package:comic_reader/models/predictions.dart';
import 'package:comic_reader/views/panel_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ReaderView extends StatefulWidget {
  final Comic comic;
  final String userId;
  final String? firebaseAuthToken;

  const ReaderView({
    super.key,
    required this.comic,
    required this.userId,
    this.firebaseAuthToken,
  });

  @override
  State<ReaderView> createState() => ReaderViewState();
}

class ReaderViewState extends State<ReaderView> {
  final ComicRepositoryFirebase _repository = ComicRepositoryFirebase();

  late int _currentPageIndex;

  /// Whether we’re in panel-by-panel panel mode.
  bool _panelMode = false;

  /// Which panel (0-based index) we’re currently focused on in panel mode.
  int _currentPanelIndex = 0;

  /// Selected language for summaries.
  String _selectedLanguage = 'en';

  /// Whether we’re showing the Gemini summary text.
  bool _showSummaries = true;

  /// We remember the user’s summary toggle setting before switching to panel mode,
  /// so we can restore it when exiting panel mode.
  bool _oldShowSummaries = true;

  @override
  void initState() {
    super.initState();
    _currentPageIndex = widget.comic.currentPage;
  }

  /// Updates the current page and optionally the panel index.
  void _updatePage(int index, {int? panelIndex}) {
    if (index < 0 || index >= widget.comic.pageCount) return;

    setState(() {
      _currentPageIndex = index;
      if (panelIndex != null) {
        _currentPanelIndex = panelIndex;
      } else {
        // Default to first panel on new page unless otherwise specified
        _currentPanelIndex = 0;
      }
    });

    _repository.updateCurrentPage(widget.userId, widget.comic.id, index);
  }

  /// Toggles between page mode (page-based) and panel mode (panel-based).
  void _togglePanelMode() {
    setState(() {
      if (!_panelMode) {
        // Switching from page to panel mode:
        _oldShowSummaries = _showSummaries;
        _showSummaries = true; // Enabled in panel mode to show panel summaries
        _panelMode = true;
        _currentPanelIndex = 0;
      } else {
        // Switching from panel mode back to page mode:
        _panelMode = false;
        _showSummaries =
            _oldShowSummaries; // Restore prior summary toggle state
        _currentPanelIndex = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comic.pageCount <= 0) {
      return const Center(child: Text('No pages available'));
    }

    // Grab the Predictions for this page, if available
    final Predictions? currentPagePredictions = widget.comic.predictions == null
        ? null
        : (widget.comic.predictions!.pagePredictions.length > _currentPageIndex
              ? widget.comic.predictions!.pagePredictions[_currentPageIndex]
              : null);

    // Grab the Gemini summary for the current page
    final String? currentPageSummaryRaw =
        (_currentPageIndex < widget.comic.pageSummaries.length)
        ? widget.comic.pageSummaries[_currentPageIndex][_selectedLanguage]
        : null;

    // Grab the Panel summary if in panel mode
    String? currentPanelSummaryRaw;
    if (_panelMode && _currentPageIndex < widget.comic.panelSummaries.length) {
      final pageData = widget.comic.panelSummaries[_currentPageIndex];
      // Safely extract panels list from the map structure
      final List? panels = pageData['panels'] as List?;

      if (panels != null && _currentPanelIndex < panels.length) {
        final panelMap = panels[_currentPanelIndex];
        if (panelMap is Map) {
          currentPanelSummaryRaw = panelMap[_selectedLanguage]?.toString();
        }
      }
    }

    final displayedSummary = _panelMode
        ? currentPanelSummaryRaw
        : currentPageSummaryRaw;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.comic.title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        centerTitle: false,
        actions: [
          // Panel-mode button
          IconButton(
            icon: Icon(
              _panelMode ? Icons.grid_view : Icons.description,
              color: _panelMode ? Colors.blue : null,
            ),
            onPressed: _togglePanelMode,
            tooltip: _panelMode
                ? 'Switch to Page Mode'
                : 'Switch to Panel Mode',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          // Simple arrow-key navigation
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _goToPrevious();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _goToNext();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTapUp: (TapUpDetails details) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  if (details.globalPosition.dx < screenWidth / 2) {
                    _goToPrevious();
                  } else {
                    _goToNext();
                  }
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(
                      'reader_${_currentPageIndex}_${_panelMode ? _currentPanelIndex : "page"}',
                    ),
                    child:
                        (_panelMode &&
                            currentPagePredictions != null &&
                            currentPagePredictions.panels.isNotEmpty)
                        ? PanelView(
                            imageUrl:
                                widget.comic.pageImages[_currentPageIndex],
                            panels: currentPagePredictions.panels,
                            currentPanelIndex: _currentPanelIndex,
                            panelMode: _panelMode,
                          )
                        : InteractiveViewer(
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Image(
                                image: CachedNetworkImageProvider(
                                  widget.comic.pageImages[_currentPageIndex],
                                ),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),

            // Always show the Gemini summary.
            Container(
              width: double.infinity,
              color: _panelMode ? Colors.blue[50] : Colors.grey[200],
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayedSummary?.isNotEmpty == true
                              ? displayedSummary!
                              : (_panelMode
                                    ? (currentPagePredictions == null ||
                                              currentPagePredictions
                                                  .panels
                                                  .isEmpty
                                          ? 'Summaries unavailable because panel detection failed for this page.'
                                          : 'No specific summary for this panel.')
                                    : 'No page summary available. (Did the import finish?)'),
                          style: TextStyle(
                            fontSize: 18,
                            color: displayedSummary?.isNotEmpty == true
                                ? Colors.black
                                : Colors.grey[600],
                            fontStyle: displayedSummary?.isNotEmpty == true
                                ? FontStyle.normal
                                : FontStyle.italic,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedLanguage,
                          icon: const Icon(Icons.language, size: 20),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                          ),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedLanguage = newValue;
                              });
                            }
                          },
                          items: const [
                            DropdownMenuItem(value: 'en', child: Text('EN')),
                            DropdownMenuItem(value: 'es', child: Text('ES')),
                            DropdownMenuItem(value: 'fr', child: Text('FR')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Page/Panel slider
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width * 0.1,
                vertical: 16,
              ),
              child: Builder(
                builder: (context) {
                  final List<({int page, int? panel})> globalReadingItems = [];
                  int currentGlobalIndex = 0;

                  if (_panelMode) {
                    for (int i = 0; i < widget.comic.pageCount; i++) {
                      final pagePreds =
                          (widget.comic.predictions?.pagePredictions.length ??
                                  0) >
                              i
                          ? widget.comic.predictions!.pagePredictions[i]
                          : null;
                      final panels = pagePreds?.panels ?? [];
                      if (panels.isEmpty) {
                        if (i == _currentPageIndex) {
                          currentGlobalIndex = globalReadingItems.length;
                        }
                        globalReadingItems.add((page: i, panel: null));
                      } else {
                        for (int j = 0; j < panels.length; j++) {
                          if (i == _currentPageIndex &&
                              j == _currentPanelIndex) {
                            currentGlobalIndex = globalReadingItems.length;
                          }
                          globalReadingItems.add((page: i, panel: j));
                        }
                      }
                    }
                  }

                  final double sliderValue = _panelMode
                      ? currentGlobalIndex.toDouble()
                      : _currentPageIndex.toDouble();
                  final double sliderMax = _panelMode
                      ? (globalReadingItems.length - 1).toDouble()
                      : (widget.comic.pageCount - 1).toDouble();
                  final int sliderDivisions = _panelMode
                      ? globalReadingItems.length - 1
                      : widget.comic.pageCount - 1;

                  String sliderLabel;
                  if (_panelMode) {
                    final item = globalReadingItems[currentGlobalIndex];
                    if (item.panel != null) {
                      sliderLabel =
                          'Page ${item.page + 1}, Panel ${item.panel! + 1}';
                    } else {
                      sliderLabel = 'Page ${item.page + 1}';
                    }
                  } else {
                    sliderLabel = 'Page ${_currentPageIndex + 1}';
                  }

                  return Slider(
                    value: sliderValue,
                    min: 0,
                    max: sliderMax > 0 ? sliderMax : 0,
                    divisions: sliderDivisions > 0 ? sliderDivisions : 1,
                    label: sliderLabel,
                    onChanged: (value) {
                      if (_panelMode) {
                        final idx = value.round();
                        if (idx >= 0 && idx < globalReadingItems.length) {
                          final item = globalReadingItems[idx];
                          _updatePage(item.page, panelIndex: item.panel ?? 0);
                        }
                      } else {
                        _updatePage(value.round());
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Navigates to the previous panel (if in panel mode), or previous page (if in page mode).
  void _goToPrevious() {
    final Predictions? currentPreds = widget.comic.predictions == null
        ? null
        : (widget.comic.predictions!.pagePredictions.length > _currentPageIndex
              ? widget.comic.predictions!.pagePredictions[_currentPageIndex]
              : null);
    final int totalPanels = currentPreds?.panels.length ?? 0;

    if (_panelMode && currentPreds != null && totalPanels > 0) {
      if (_currentPanelIndex > 0) {
        // Move to previous panel
        setState(() {
          _currentPanelIndex--;
        });
      } else {
        // Already at first panel; go to previous page's last panel if possible
        if (_currentPageIndex > 0) {
          final prevIndex = _currentPageIndex - 1;
          final prevPreds =
              (widget.comic.predictions?.pagePredictions.length ?? 0) >
                  prevIndex
              ? widget.comic.predictions!.pagePredictions[prevIndex]
              : null;
          final prevPanelsCount = prevPreds?.panels.length ?? 0;

          _updatePage(
            prevIndex,
            panelIndex: prevPanelsCount > 0 ? prevPanelsCount - 1 : 0,
          );
        }
      }
    } else {
      // Page mode: just go to the previous page if it exists
      if (_currentPageIndex > 0) {
        _updatePage(_currentPageIndex - 1);
      }
    }
  }

  /// Navigates to the next panel (if in panel mode), or next page (if in page mode).
  void _goToNext() {
    final Predictions? currentPreds = widget.comic.predictions == null
        ? null
        : (widget.comic.predictions!.pagePredictions.length > _currentPageIndex
              ? widget.comic.predictions!.pagePredictions[_currentPageIndex]
              : null);
    final int totalPanels = currentPreds?.panels.length ?? 0;

    if (_panelMode && currentPreds != null && totalPanels > 0) {
      // If we're not yet at the last panel, go to the next panel
      if (_currentPanelIndex < totalPanels - 1) {
        setState(() {
          _currentPanelIndex++;
        });
      } else {
        // If at last panel, try to go to next page's first panel
        if (_currentPageIndex < (widget.comic.pageCount - 1)) {
          _updatePage(_currentPageIndex + 1);
        }
      }
    } else {
      // Page mode: go to next page if possible
      if (_currentPageIndex < widget.comic.pageCount - 1) {
        _updatePage(_currentPageIndex + 1);
      }
    }
  }
}
