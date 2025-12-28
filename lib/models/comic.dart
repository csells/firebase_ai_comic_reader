import 'package:comic_reader/models/comic_predictions.dart';

class Comic {
  final String id;
  final String title;
  final String? thumbnailImage;
  final String? author;
  final String? series;
  final int pageCount;
  int currentPage;
  DateTime lastReadDate;
  List<String> pageImages;

  /// AI/ML predictions for each page (panels, etc.)
  ComicPredictions? predictions;

  /// Summaries for each page
  /// (Index i in [pageSummaries] corresponds to the i-th page in [pageImages]).
  /// Each element is a map where keys are language codes (e.g. 'en', 'es', 'fr') and values are the summary text.
  List<Map<String, String>> pageSummaries;

  /// Summaries for each panel on each page.
  /// (Index i corresponds to the i-th page).
  /// Each element is a map with a key 'panels' containing a list of panel summaries.
  /// Structure: `[ { 'panels': [ { 'en': '...' }, ... ] }, ... ]`
  List<Map<String, dynamic>> panelSummaries;

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
    this.predictions,
    this.pageSummaries = const [],
    this.panelSummaries = const [],
  }) : lastReadDate = lastReadDate ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'thumbnailImage': thumbnailImage,
      'author': author,
      'series': series,
      'pageCount': pageCount,
      'currentPage': currentPage,
      'lastReadDate': lastReadDate.toIso8601String(),
      'pageImages': pageImages,
      'predictions': predictions?.toMap(),
      'pageSummaries': pageSummaries,
      'panelSummaries': panelSummaries,
    };
  }

  static Comic fromMap(Map<String, dynamic> map) {
    return Comic(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      thumbnailImage: map['thumbnailImage'],
      author: map['author'],
      series: map['series'],
      pageCount: map['pageCount'] ?? 0,
      currentPage: map['currentPage'] ?? 0,
      lastReadDate: map['lastReadDate'] != null
          ? DateTime.parse(map['lastReadDate'])
          : null,
      pageImages: List<String>.from(map['pageImages'] ?? []),
      predictions: map['predictions'] != null
          ? ComicPredictions.fromMap(map['predictions'])
          : null,
      pageSummaries: map['pageSummaries'] != null
          ? (map['pageSummaries'] as List)
                .map((e) => Map<String, String>.from(e))
                .toList()
          : [],
      panelSummaries: map['panelSummaries'] != null
          ? (map['panelSummaries'] as List).map((pageMap) {
              final m = Map<String, dynamic>.from(pageMap);
              if (m['panels'] != null) {
                m['panels'] = (m['panels'] as List)
                    .map((panel) => Map<String, String>.from(panel))
                    .toList();
              }
              return m;
            }).toList()
          : [],
    );
  }
}
