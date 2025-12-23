// TODO: 241229: Disable slider for panel-by-panel mode

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
  final String? googleAccessToken;

  const ReaderView({
    super.key,
    required this.comic,
    required this.userId,
    this.firebaseAuthToken,
    this.googleAccessToken,
  });

  @override
  State<ReaderView> createState() => ReaderViewState();
}

class ReaderViewState extends State<ReaderView> {
  final PageController _pageController = PageController();
  final ComicRepositoryFirebase _repository = ComicRepositoryFirebase();

  late int _currentPageIndex;

  /// Whether we’re in panel-by-panel smart mode.
  bool _smartMode = false;

  /// Which panel (0-based index) we’re currently focused on in smart mode.
  int _currentPanelIndex = 0;

  // TODO: 241224: Decide on whether to move to first panel on load (it used to
  // go to the last panel when navigating backwards, and the first panel when
  // navigating forwards).
  //
  /// Flag: If we jump to a new page in smart mode, do we go to the first or last panel?
  bool? _goToFirstPanelOnLoad;

  /// Selected language for summaries.
  String _selectedLanguage = 'en';

  /// Whether we’re showing the Gemini summary text in normal mode.
  bool _showSummaries = true;

  /// We remember the user’s summary toggle setting before switching to smart mode,
  /// so we can restore it when exiting smart mode.
  bool _oldShowSummaries = true;

  @override
  void initState() {
    super.initState();
    _currentPageIndex = widget.comic.currentPage;

    // Jump the PageView to the current page on first load.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageController.jumpToPage(_currentPageIndex);
    });
  }

  /// Fired when the user swipes to a different page (in normal mode),
  /// or we programmatically change the page (in smart mode).
  void _onPageChanged(int index) {
    int newPanelIndex = 0;

    // If in smart mode and we have a specific target (e.g. going back to previous page)
    if (_smartMode && _goToFirstPanelOnLoad == false) {
      final predictions = widget.comic.predictions;
      if (predictions != null && index < predictions.pagePredictions.length) {
        final panels = predictions.pagePredictions[index].panels;
        if (panels.isNotEmpty) {
          newPanelIndex = panels.length - 1;
        }
      }
    }

    setState(() {
      _currentPageIndex = index;
      _currentPanelIndex = newPanelIndex;
      _goToFirstPanelOnLoad = null;
    });
    _repository.updateCurrentPage(widget.userId, widget.comic.id, index);
  }

  /// Toggles between normal mode (page-based) and smart mode (panel-based).
  void _toggleSmartMode() {
    setState(() {
      if (!_smartMode) {
        // Switching from normal to smart mode:
        _oldShowSummaries = _showSummaries;
        _showSummaries = true; // Enabled in smart mode to show panel summaries
        _smartMode = true;
        _currentPanelIndex = 0;
      } else {
        // Switching from smart mode back to normal mode:
        _smartMode = false;
        _showSummaries =
            _oldShowSummaries; // Restore prior summary toggle state
        _currentPanelIndex = 0;
      }
    });
  }

  /// Toggles whether we display summaries.
  void _toggleSummaries() {
    setState(() {
      _showSummaries = !_showSummaries;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comic.pageCount == null || widget.comic.pageCount! <= 0) {
      return const Center(child: Text('No pages available'));
    }

    // Grab the Predictions for this page, if available
    final Predictions? currentPagePredictions = widget.comic.predictions == null
        ? null
        : (widget.comic.predictions!.pagePredictions.length > _currentPageIndex
            ? widget.comic.predictions!.pagePredictions[_currentPageIndex]
            : null);

    // Grab the Gemini summary for the current page
    final String? currentPageSummaryRaw = (widget.comic.pageSummaries != null &&
            _currentPageIndex < widget.comic.pageSummaries!.length)
        ? widget.comic.pageSummaries![_currentPageIndex][_selectedLanguage]
        : null;

    // Grab the Panel summary if in smart mode
    String? currentPanelSummaryRaw;
    if (_smartMode &&
        widget.comic.panelSummaries != null &&
        _currentPageIndex < widget.comic.panelSummaries!.length) {
      final pageData = widget.comic.panelSummaries![_currentPageIndex];
      // Safely extract panels list from the map structure
      final List? panels = pageData['panels'] as List?;

      if (panels != null && _currentPanelIndex < panels.length) {
        final panelMap = panels[_currentPanelIndex];
        if (panelMap is Map) {
          currentPanelSummaryRaw = panelMap[_selectedLanguage]?.toString();
        }
      }
    }

    final displayedSummary =
        _smartMode ? currentPanelSummaryRaw : currentPageSummaryRaw;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.comic.title, overflow: TextOverflow.ellipsis),
        centerTitle: false, // Changed to false to give more room for actions
        actions: [
          // Simplified Language Dropdown
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedLanguage,
              icon: const Icon(Icons.language),
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
          const SizedBox(width: 8),
          // Smart-mode button
          IconButton(
            icon: Icon(
              Icons.science,
              color: _smartMode ? Colors.blue : null, // Highlight when ON
            ),
            onPressed: _toggleSmartMode,
            tooltip: _smartMode ? 'Smart Mode (ON)' : 'Smart Mode (OFF)',
          ),
          // Summaries toggle button
          IconButton(
            icon: Icon(
              _showSummaries ? Icons.comment : Icons.comment_bank_outlined,
            ),
            onPressed: _toggleSummaries,
            tooltip: _showSummaries ? 'Hide Summaries' : 'Show Summaries',
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'delete') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Comic'),
                    content: const Text(
                        'Are you sure you want to delete this comic?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && mounted) {
                  await _repository.deleteComic(widget.userId, widget.comic.id);
                  if (mounted) {
                    Navigator.pop(context); // Go back to library
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete Comic', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
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
                child: PageView.builder(
                  controller: _pageController,
                  physics: _smartMode
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  onPageChanged: _onPageChanged,
                  itemCount: widget.comic.pageCount,
                  itemBuilder: (context, index) {
                    final imageUrl = widget.comic.pageImages[index];

                    // If we’re in smart mode, show the panel-by-panel view
                    if (_smartMode && index == _currentPageIndex) {
                      if (currentPagePredictions != null &&
                          currentPagePredictions.panels.isNotEmpty) {
                        return PanelView(
                          imageUrl: imageUrl,
                          panels: currentPagePredictions.panels,
                          currentPanelIndex: _currentPanelIndex,
                          smartMode: _smartMode,
                        );
                      } else {
                        // No predictions on this page? Fall back to normal image display
                        return InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: Image(
                            image: CachedNetworkImageProvider(imageUrl),
                            fit: BoxFit.contain,
                          ),
                        );
                      }
                    } else {
                      // Normal mode: just display the full page with zoom
                      return InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 4.0,
                        child: Image(
                          image: CachedNetworkImageProvider(imageUrl),
                          fit: BoxFit.contain,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),

            // Only show the Gemini summary if user has toggled it on.
            if (_showSummaries)
              Container(
                width: double.infinity,
                color: _smartMode ? Colors.blue[50] : Colors.grey[200],
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_smartMode)
                      Row(
                        children: [
                          const Icon(Icons.science,
                              color: Colors.blue, size: 14),
                          const SizedBox(width: 4),
                          const Text(
                            'SMART MODE ACTIVE',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue),
                          ),
                          const Spacer(),
                          if (currentPagePredictions == null ||
                              currentPagePredictions.panels.isEmpty)
                            const Text(
                              '(No panels detected for this page)',
                              style: TextStyle(fontSize: 10, color: Colors.red),
                            ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      displayedSummary?.isNotEmpty == true
                          ? displayedSummary!
                          : (_smartMode
                              ? (currentPagePredictions == null ||
                                      currentPagePredictions.panels.isEmpty
                                  ? 'Summaries unavailable because panel detection failed for this page.'
                                  : 'No specific summary for this panel.')
                              : 'No page summary available. (Did the import finish?)'),
                      style: TextStyle(
                        fontSize: 14,
                        color: displayedSummary?.isNotEmpty == true
                            ? Colors.black
                            : Colors.grey[600],
                        fontStyle: displayedSummary?.isNotEmpty == true
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

            // Page slider
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width * 0.1,
                vertical: 16,
              ),
              child: Slider(
                value: _currentPageIndex.toDouble(),
                min: 0,
                max: (widget.comic.pageCount! - 1).toDouble(),
                divisions: widget.comic.pageCount! - 1,
                label: (_currentPageIndex + 1).toString(),
                onChanged: (value) {
                  // Only allow direct page-jumping if we’re NOT in smart mode
                  if (!_smartMode) {
                    _pageController.jumpToPage(value.round());
                    _onPageChanged(value.round());
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Navigates to the previous panel (if in smart mode), or previous page (if in normal mode).
  void _goToPrevious() {
    final Predictions? currentPreds = widget.comic.predictions == null
        ? null
        : (widget.comic.predictions!.pagePredictions.length > _currentPageIndex
            ? widget.comic.predictions!.pagePredictions[_currentPageIndex]
            : null);
    final int totalPanels = currentPreds?.panels.length ?? 0;

    if (_smartMode && currentPreds != null && totalPanels > 0) {
      if (_currentPanelIndex > 0) {
        // Move to previous panel
        setState(() {
          _currentPanelIndex--;
        });
      } else {
        // Already at first panel; go to previous page's last panel if possible
        if (_currentPageIndex > 0) {
          _goToFirstPanelOnLoad =
              false; // We'll want the last panel on that page
          _pageController.previousPage(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
          );
        }
      }
    } else {
      // Normal mode: just go to the previous page if it exists
      if (_currentPageIndex > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  /// Navigates to the next panel (if in smart mode), or next page (if in normal mode).
  void _goToNext() {
    final Predictions? currentPreds = widget.comic.predictions == null
        ? null
        : (widget.comic.predictions!.pagePredictions.length > _currentPageIndex
            ? widget.comic.predictions!.pagePredictions[_currentPageIndex]
            : null);
    final int totalPanels = currentPreds?.panels.length ?? 0;

    if (_smartMode && currentPreds != null && totalPanels > 0) {
      // If we're not yet at the last panel, go to the next panel
      if (_currentPanelIndex < totalPanels - 1) {
        setState(() {
          _currentPanelIndex++;
        });
      } else {
        // If at last panel, try to go to next page's first panel
        if (_currentPageIndex < (widget.comic.pageCount! - 1)) {
          _goToFirstPanelOnLoad = true; // We'll want the first panel there
          _pageController.nextPage(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
          );
        }
      }
    } else {
      // Normal mode: go to next page if possible
      if (_currentPageIndex < widget.comic.pageCount! - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
        );
      }
    }
  }
}
