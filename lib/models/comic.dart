// ignore_for_file: avoid_dynamic_calls

import 'predictions.dart';

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
    predictions: (map['predictions']?['pagePredictions'] as List? ?? [])
        .map((m) => Predictions.fromMap(m as Map<String, dynamic>))
        .toList(),
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

  final String id;
  final String title;
  final String? thumbnailImage;
  final String? author;
  final String? series;
  final int pageCount;
  int currentPage;
  DateTime lastReadDate;
  List<String> pageImages;

  /// Panel predictions for each page
  List<Predictions> predictions;

  /// Summaries for each page (language code -> text)
  List<Map<String, String>> pageSummaries;

  /// Summaries for each panel on each page
  /// Structure: `[ { 'panels': [ { 'en': '...' }, ... ] }, ... ]`
  List<Map<String, dynamic>> panelSummaries;

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
    'pageSummaries': pageSummaries,
    'panelSummaries': panelSummaries,
  };
}
