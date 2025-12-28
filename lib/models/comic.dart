import 'page_panel_summaries.dart';
import 'predictions.dart';
import 'translated_text.dart';

class Comic {
  Comic({
    required this.id,
    required this.title,
    this.thumbnailImage,
    this.author,
    this.series,
    this.pageCount = 0,
    this.currentPage = 0,
    DateTime? lastReadDate,
    this.pageImages = const [],
    this.predictions = const [],
    this.pageSummaries = const [],
    this.panelSummaries = const [],
  }) : lastReadDate = lastReadDate ?? DateTime.now();

  factory Comic.fromMap(Map<String, dynamic> map) => Comic(
    id: map['id']?.toString() ?? '',
    title: map['title']?.toString() ?? '',
    thumbnailImage: map['thumbnailImage']?.toString(),
    author: map['author']?.toString(),
    series: map['series']?.toString(),
    pageCount: (map['pageCount'] as num?)?.toInt() ?? 0,
    currentPage: (map['currentPage'] as num?)?.toInt() ?? 0,
    lastReadDate: map['lastReadDate'] != null
        ? DateTime.parse(map['lastReadDate'] as String)
        : null,
    pageImages: List<String>.from(map['pageImages'] as List? ?? []),
    predictions:
        ((map['predictions'] as Map<String, dynamic>?)?['pagePredictions']
                    as List? ??
                [])
            .map((m) => Predictions.fromMap(m as Map<String, dynamic>))
            .toList(),
    pageSummaries: (map['pageSummaries'] as List? ?? [])
        .map((e) => TranslatedText.fromMap(e as Map<String, dynamic>))
        .toList(),
    panelSummaries: (map['panelSummaries'] as List? ?? [])
        .map((e) => PagePanelSummaries.fromMap(e as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String title;
  final String? thumbnailImage;
  final String? author;
  final String? series;
  final int pageCount;
  int currentPage;
  DateTime lastReadDate;
  List<String> pageImages;

  /// Panel predictions for each page.
  List<Predictions> predictions;

  /// Summaries for each page (translated into multiple languages).
  List<TranslatedText> pageSummaries;

  /// Summaries for each panel on each page (translated into multiple
  /// languages).
  List<PagePanelSummaries> panelSummaries;

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'thumbnailImage': thumbnailImage,
    'author': author,
    'series': series,
    'pageCount': pageCount,
    'currentPage': currentPage,
    'lastReadDate': lastReadDate.toIso8601String(),
    'pageImages': pageImages,
    // Same Firestore structure: predictions.pagePredictions
    'predictions': {
      'pagePredictions': predictions.map((p) => p.toMap()).toList(),
    },
    'pageSummaries': pageSummaries.map((s) => s.toMap()).toList(),
    'panelSummaries': panelSummaries.map((p) => p.toMap()).toList(),
  };
}
