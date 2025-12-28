import 'panel.dart';

/// Represents the results of panel detection for a single page.
class Predictions {
  Predictions({required this.panels});

  factory Predictions.fromMap(Map<String, dynamic> map) {
    final panelsData = map['panels'] as List<dynamic>? ?? [];
    final panels = panelsData
        .map((panelData) => Panel.fromMap(panelData as Map<String, dynamic>))
        .toList();

    return Predictions(panels: panels);
  }
  final List<Panel> panels;

  Map<String, dynamic> toMap() => {
    'panels': panels.map((panel) => panel.toMap()).toList(),
  };

  @override
  String toString() => 'Predictions(panels: ${panels.length})';
}
