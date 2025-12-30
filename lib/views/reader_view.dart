import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/comic_repository_firebase.dart';
import '../data/gemini_service.dart';
import '../models/comic.dart';
import '../models/page_panel_summaries.dart';
import '../models/translated_text.dart';
import 'panel_view.dart';

class ReaderView extends StatefulWidget {
  const ReaderView({required this.comic, required this.userId, super.key});
  final Comic comic;
  final String userId;

  @override
  State<ReaderView> createState() => ReaderViewState();
}

class ReaderViewState extends State<ReaderView> {
  final ComicRepositoryFirebase _repository = ComicRepositoryFirebase();
  final GeminiService _geminiService = GeminiService();

  late int _currentPageIndex;
  final Set<String> _pendingTranslations = {};
  bool _panelMode = false;
  int _currentPanelIndex = 0;
  String _selectedLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _currentPageIndex = widget.comic.currentPage;
  }

  void _updatePage(int index, {int? panelIndex}) {
    if (index < 0 || index >= widget.comic.pageCount) return;

    setState(() {
      _currentPageIndex = index;
      _currentPanelIndex = panelIndex ?? 0;
    });

    unawaited(
      _repository.updateCurrentPage(widget.userId, widget.comic.id, index),
    );

    if (_selectedLanguage != 'en') {
      unawaited(_translateIfNeeded(index));
    }
  }

  void _togglePanelMode() {
    setState(() {
      if (!_panelMode) {
        _panelMode = true;
        _currentPanelIndex = 0;
      } else {
        _panelMode = false;
        _currentPanelIndex = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.comic.pageCount <= 0) {
      return const Center(child: Text('No pages available'));
    }

    final currentPagePredictions =
        _currentPageIndex < widget.comic.predictions.length
        ? widget.comic.predictions[_currentPageIndex]
        : null;

    final currentPageSummaryRaw =
        (_currentPageIndex < widget.comic.pageSummaries.length)
        ? widget.comic.pageSummaries[_currentPageIndex].forLanguage(
            _selectedLanguage,
          )
        : null;

    String? currentPanelSummaryRaw;
    if (_panelMode && _currentPageIndex < widget.comic.panelSummaries.length) {
      final pageData = widget.comic.panelSummaries[_currentPageIndex];
      currentPanelSummaryRaw = pageData.getSummary(
        _currentPanelIndex,
        _selectedLanguage,
      );
    }

    final displayedSummary = _panelMode
        ? currentPanelSummaryRaw
        : currentPageSummaryRaw;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
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
                onTapUp: (details) {
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
                      'reader_$_currentPageIndex'
                      '_${_panelMode ? _currentPanelIndex : "page"}',
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
                            minScale: 1,
                            maxScale: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(32),
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
            _SummaryOverlay(
              displayedSummary: displayedSummary,
              panelMode: _panelMode,
              isPending: _pendingTranslations.contains(
                '$_currentPageIndex-$_selectedLanguage',
              ),
              selectedLanguage: _selectedLanguage,
              onLanguageChanged: (newValue) {
                if (newValue != null && newValue != _selectedLanguage) {
                  setState(() {
                    _selectedLanguage = newValue;
                  });
                  if (_selectedLanguage != 'en') {
                    unawaited(_translateIfNeeded(_currentPageIndex));
                  }
                }
              },
              predictionsFailed:
                  _panelMode &&
                  (currentPagePredictions == null ||
                      currentPagePredictions.panels.isEmpty),
            ),
            _ReaderSlider(
              comic: widget.comic,
              panelMode: _panelMode,
              currentPageIndex: _currentPageIndex,
              currentPanelIndex: _currentPanelIndex,
              onUpdatePage: _updatePage,
            ),
          ],
        ),
      ),
    );
  }

  void _goToPrevious() {
    final currentPreds = _currentPageIndex < widget.comic.predictions.length
        ? widget.comic.predictions[_currentPageIndex]
        : null;
    final totalPanels = currentPreds?.panels.length ?? 0;

    if (_panelMode && currentPreds != null && totalPanels > 0) {
      if (_currentPanelIndex > 0) {
        setState(() {
          _currentPanelIndex--;
        });
      } else if (_currentPageIndex > 0) {
        final prevIndex = _currentPageIndex - 1;
        final prevPreds = widget.comic.predictions.length > prevIndex
            ? widget.comic.predictions[prevIndex]
            : null;
        final prevPanelsCount = prevPreds?.panels.length ?? 0;
        _updatePage(
          prevIndex,
          panelIndex: prevPanelsCount > 0 ? prevPanelsCount - 1 : 0,
        );
      }
    } else if (_currentPageIndex > 0) {
      _updatePage(_currentPageIndex - 1);
    }
  }

  void _goToNext() {
    final currentPreds = _currentPageIndex < widget.comic.predictions.length
        ? widget.comic.predictions[_currentPageIndex]
        : null;
    final totalPanels = currentPreds?.panels.length ?? 0;

    if (_panelMode && currentPreds != null && totalPanels > 0) {
      if (_currentPanelIndex < totalPanels - 1) {
        setState(() {
          _currentPanelIndex++;
        });
      } else if (_currentPageIndex < (widget.comic.pageCount - 1)) {
        _updatePage(_currentPageIndex + 1);
      }
    } else if (_currentPageIndex < widget.comic.pageCount - 1) {
      _updatePage(_currentPageIndex + 1);
    }
  }

  Future<void> _translateIfNeeded([int? pageIndex]) async {
    final targetPageIndex = pageIndex ?? _currentPageIndex;
    if (_selectedLanguage == 'en') return;

    final lang = _selectedLanguage;
    final requestId = '$targetPageIndex-$lang';

    final pageTranslated =
        targetPageIndex < widget.comic.pageSummaries.length &&
        widget.comic.pageSummaries[targetPageIndex]
            .forLanguage(lang)
            .isNotEmpty;

    final panelsTranslated =
        targetPageIndex < widget.comic.panelSummaries.length &&
        widget.comic.panelSummaries[targetPageIndex].panels.every(
          (p) => p.forLanguage(lang).isNotEmpty,
        );

    if (pageTranslated && panelsTranslated) return;
    if (_pendingTranslations.contains(requestId)) return;

    if (mounted && targetPageIndex == _currentPageIndex) {
      setState(() {});
    }

    _pendingTranslations.add(requestId);

    try {
      final textsToTranslate = <String>[];
      if (targetPageIndex < widget.comic.pageSummaries.length) {
        textsToTranslate.add(widget.comic.pageSummaries[targetPageIndex].en);
      }
      if (targetPageIndex < widget.comic.panelSummaries.length) {
        textsToTranslate.addAll(
          widget.comic.panelSummaries[targetPageIndex].panels.map((p) => p.en),
        );
      }

      if (textsToTranslate.isEmpty) {
        _pendingTranslations.remove(requestId);
        return;
      }

      final results = await _geminiService.translate(textsToTranslate, lang);

      if (results.length == textsToTranslate.length) {
        var resultIdx = 0;
        if (targetPageIndex < widget.comic.pageSummaries.length) {
          widget.comic.pageSummaries[targetPageIndex] = widget
              .comic
              .pageSummaries[targetPageIndex]
              .withTranslation(lang, results[resultIdx++]);
        }
        if (targetPageIndex < widget.comic.panelSummaries.length) {
          final currentPanels =
              widget.comic.panelSummaries[targetPageIndex].panels;
          final updatedPanels = <TranslatedText>[];
          for (var i = 0; i < currentPanels.length; i++) {
            updatedPanels.add(
              currentPanels[i].withTranslation(lang, results[resultIdx++]),
            );
          }
          widget.comic.panelSummaries[targetPageIndex] = PagePanelSummaries(
            panels: updatedPanels,
          );
        }
      }
    } on Exception catch (e) {
      debugPrint('Translation error: $e');
    } finally {
      _pendingTranslations.remove(requestId);
      if (mounted && targetPageIndex == _currentPageIndex) {
        setState(() {});
      }
    }
  }

  @override
  void setState(VoidCallback fn) {
    if (!mounted) return;
    super.setState(fn);
  }

  AppBar _buildAppBar() => AppBar(
    title: Text(
      widget.comic.title,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 16),
    ),
    centerTitle: false,
    actions: [
      IconButton(
        icon: Icon(
          _panelMode ? Icons.grid_view : Icons.description,
          color: _panelMode ? Colors.blue : null,
        ),
        onPressed: _togglePanelMode,
        tooltip: _panelMode ? 'Switch to Page Mode' : 'Switch to Panel Mode',
      ),
      const SizedBox(width: 8),
    ],
  );
}

class _SummaryOverlay extends StatelessWidget {
  const _SummaryOverlay({
    required this.displayedSummary,
    required this.panelMode,
    required this.isPending,
    required this.selectedLanguage,
    required this.onLanguageChanged,
    required this.predictionsFailed,
  });

  final String? displayedSummary;
  final bool panelMode;
  final bool isPending;
  final String selectedLanguage;
  final ValueChanged<String?> onLanguageChanged;
  final bool predictionsFailed;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: panelMode ? Colors.blue[50] : Colors.grey[200],
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
    child: Row(
      children: [
        Expanded(child: _buildSummaryText()),
        const SizedBox(width: 8),
        _buildLanguageDropdown(),
      ],
    ),
  );

  Widget _buildSummaryText() {
    if (isPending) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final hasContent = displayedSummary?.isNotEmpty ?? false;
    final text = hasContent
        ? displayedSummary!
        : (panelMode
              ? (predictionsFailed
                    ? 'Summaries unavailable because panel detection failed '
                          'for this page.'
                    : 'No specific summary for this panel.')
              : 'No page summary available. (Did the import finish?)');

    return Text(
      text,
      style: TextStyle(
        fontSize: 18,
        color: hasContent ? Colors.black : Colors.grey[600],
        fontStyle: hasContent ? FontStyle.normal : FontStyle.italic,
      ),
    );
  }

  Widget _buildLanguageDropdown() => DropdownButtonHideUnderline(
    child: DropdownButton<String>(
      value: selectedLanguage,
      icon: const Icon(Icons.language, size: 20),
      style: const TextStyle(fontSize: 14, color: Colors.black),
      onChanged: onLanguageChanged,
      items: const [
        DropdownMenuItem(value: 'en', child: Text('EN')),
        DropdownMenuItem(value: 'es', child: Text('ES')),
        DropdownMenuItem(value: 'fr', child: Text('FR')),
      ],
    ),
  );
}

class _ReaderSlider extends StatelessWidget {
  const _ReaderSlider({
    required this.comic,
    required this.panelMode,
    required this.currentPageIndex,
    required this.currentPanelIndex,
    required this.onUpdatePage,
  });

  final Comic comic;
  final bool panelMode;
  final int currentPageIndex;
  final int currentPanelIndex;
  final Function(int, {int? panelIndex}) onUpdatePage;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: MediaQuery.of(context).size.width * 0.1,
      vertical: 16,
    ),
    child: Builder(
      builder: (context) {
        final globalReadingItems = <({int page, int? panel})>[];
        var currentGlobalIndex = 0;

        if (panelMode) {
          for (var i = 0; i < comic.pageCount; i++) {
            final pagePreds = comic.predictions.length > i
                ? comic.predictions[i]
                : null;
            final panels = pagePreds?.panels ?? [];
            if (panels.isEmpty) {
              if (i == currentPageIndex) {
                currentGlobalIndex = globalReadingItems.length;
              }
              globalReadingItems.add((page: i, panel: null));
            } else {
              for (var j = 0; j < panels.length; j++) {
                if (i == currentPageIndex && j == currentPanelIndex) {
                  currentGlobalIndex = globalReadingItems.length;
                }
                globalReadingItems.add((page: i, panel: j));
              }
            }
          }
        }

        final sliderValue = panelMode
            ? currentGlobalIndex.toDouble()
            : currentPageIndex.toDouble();
        final sliderMax = panelMode
            ? (globalReadingItems.length - 1).toDouble()
            : (comic.pageCount - 1).toDouble();
        final sliderDivisions = panelMode
            ? globalReadingItems.length - 1
            : comic.pageCount - 1;

        String sliderLabel;
        if (panelMode) {
          final item = globalReadingItems[currentGlobalIndex];
          if (item.panel != null) {
            sliderLabel = 'Page ${item.page + 1}, Panel ${item.panel! + 1}';
          } else {
            sliderLabel = 'Page ${item.page + 1}';
          }
        } else {
          sliderLabel = 'Page ${currentPageIndex + 1}';
        }

        return Slider(
          value: sliderValue,
          min: 0,
          max: sliderMax > 0 ? sliderMax : 0,
          divisions: sliderDivisions > 0 ? sliderDivisions : 1,
          label: sliderLabel,
          onChanged: (value) {
            final idx = value.round();
            if (panelMode) {
              if (idx >= 0 && idx < globalReadingItems.length) {
                final item = globalReadingItems[idx];
                onUpdatePage(item.page, panelIndex: item.panel ?? 0);
              }
            } else {
              onUpdatePage(idx);
            }
          },
        );
      },
    ),
  );
}
