import 'package:comic_reader/models/predictions.dart';
import 'package:comic_reader/models/panel.dart';

/// Represents all predictions for a comic, across all pages.
/// `pagePredictions` is a list where each element corresponds
/// to one page of the comic.
class ComicPredictions {
  final List<Predictions> pagePredictions;

  ComicPredictions({required this.pagePredictions});

  /// Returns a 2D list: panels[pageIndex] = List\<Panel\> for that page
  List<List<Panel>> get panels => pagePredictions.map((p) => p.panels).toList();

  Map<String, dynamic> toMap() {
    return {
      'pagePredictions': pagePredictions.map((p) => p.toMap()).toList(),
    };
  }

  factory ComicPredictions.fromMap(Map<String, dynamic> map) {
    final pp = (map['pagePredictions'] as List<dynamic>? ?? [])
        .map((m) => Predictions.fromMap(m as Map<String, dynamic>))
        .toList();

    return ComicPredictions(pagePredictions: pp);
  }
}
