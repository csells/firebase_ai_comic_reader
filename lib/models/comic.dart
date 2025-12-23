import 'package:comic_reader/models/comic_predictions.dart';

class Comic {
  final String id;
  final String title;
  final String? thumbnailImage;
  final String? author;
  final String? series;
  late final int? pageCount;
  int currentPage;
  DateTime lastReadDate;
  List<String> pageImages;

  /// AI/ML predictions for each page (panels, etc.)
  ComicPredictions? predictions;

  /// **New**: Summaries for each page
  /// (Index i in [pageSummaries] corresponds to the i-th page in [pageImages]).
  /// Each element is a map where keys are language codes (e.g. 'en', 'es', 'fr') and values are the summary text.
  List<Map<String, String>>? pageSummaries;

  /// **New**: Summaries for each panel on each page.
  /// (Index i corresponds to the i-th page).
  /// Each element is a map with a key 'panels' containing a list of panel summaries.
  /// This wrapping is necessary because Firestore does not support nested arrays (`List<List>`).
  /// Structure: `[ { 'panels': [ { 'en': '...' }, ... ] }, ... ]`
  List<Map<String, dynamic>>? panelSummaries;

  Comic({
    required this.id,
    required this.title,
    this.thumbnailImage,
    this.author,
    this.series,
    this.pageCount,
    this.currentPage = 0,
    DateTime? lastReadDate,
    this.pageImages = const [],
    this.predictions,
    this.pageSummaries,
    this.panelSummaries,
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
      id: map['id'],
      title: map['title'],
      thumbnailImage: map['thumbnailImage'],
      author: map['author'],
      series: map['series'],
      pageCount: map['pageCount'],
      currentPage: map['currentPage'],
      lastReadDate: DateTime.parse(map['lastReadDate']),
      pageImages: List<String>.from(map['pageImages']),
      predictions: map['predictions'] != null
          ? ComicPredictions.fromMap(map['predictions'])
          : null,
      pageSummaries: map['pageSummaries'] != null
          ? (map['pageSummaries'] as List).map((e) {
              if (e is String) return {'en': e};
              return Map<String, String>.from(e);
            }).toList()
          : null,
      panelSummaries: map['panelSummaries'] != null
          ? (map['panelSummaries'] as List).map((pageMap) {
              if (pageMap is List) {
                // Handle old nested array format if it somehow exists (e.g. from local tests)
                return {
                  'panels':
                      pageMap.map((p) => Map<String, String>.from(p)).toList()
                };
              }
              final m = Map<String, dynamic>.from(pageMap);
              if (m['panels'] != null) {
                m['panels'] = (m['panels'] as List)
                    .map((panel) => Map<String, String>.from(panel))
                    .toList();
              }
              return m;
            }).toList()
          : null,
    );
  }
}

// 122423: Pre-Gemini Summaries:
/*
/// Represents a comic book with its metadata and reading state.
///
/// This class handles both the comic's metadata (title, author, etc.) and its reading state
/// (current page, last read date). It also manages the comic's page images.
///
/// Note: Image naming conventions in CBZ archives can be misleading as they often skip numbers.
/// The actual page count should be determined by counting the loaded pages rather than
/// inferring from image filenames.
class Comic {
  /// Unique identifier for the comic.
  final String id;

  /// Title of the comic.
  final String title;

  /// URL or path to the comic's thumbnail image.
  final String? thumbnailImage;

  /// Author of the comic.
  final String? author;

  /// Series or collection the comic belongs to.
  final String? series;

  /// Total number of pages in the comic.
  /// This is set after loading the comic and counting the actual pages.
  late final int? pageCount;

  /// Current page being read (0-based index).
  int currentPage;

  /// Date when the comic was last read.
  DateTime lastReadDate;

  /// List of URLs or paths to the comic's page images.
  List<String> pageImages;

  /// New field: predictions for all pages of the comic.
  ComicPredictions? predictions;

  Comic({
    required this.id,
    required this.title,
    this.thumbnailImage,
    this.author,
    this.series,
    this.pageCount,
    this.currentPage = 0,
    DateTime? lastReadDate,
    this.pageImages = const [],
    this.predictions,
  }) : lastReadDate = lastReadDate ?? DateTime.now();

  /// Converts the comic data to a map for serialization.
  ///
  /// Returns a map containing all comic properties, suitable for storage in Firestore
  /// or other data stores. The lastReadDate is converted to ISO 8601 format.
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
      // Store predictions if available
      'predictions': predictions?.toMap(),
    };
  }

  /// Creates a Comic instance from a map representation.
  ///
  /// [map] A map containing comic properties, typically from a data store.
  /// The lastReadDate is expected to be in ISO 8601 format.
  static Comic fromMap(Map<String, dynamic> map) {
    return Comic(
      id: map['id'],
      title: map['title'],
      thumbnailImage: map['thumbnailImage'],
      author: map['author'],
      series: map['series'],
      pageCount: map['pageCount'],
      currentPage: map['currentPage'],
      lastReadDate: DateTime.parse(map['lastReadDate']),
      pageImages: List<String>.from(map['pageImages']),
      // Restore predictions if present
      predictions: map['predictions'] != null
          ? ComicPredictions.fromMap(map['predictions'])
          : null,
    );
  }
}
*/
