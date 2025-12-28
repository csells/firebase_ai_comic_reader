import 'package:flutter/foundation.dart' show immutable;

import 'translated_text.dart';

/// Contains the translated summaries for all panels on a single comic page.
@immutable
class PagePanelSummaries {
  const PagePanelSummaries({this.panels = const []});

  factory PagePanelSummaries.fromMap(Map<String, dynamic> map) {
    final panelsList = map['panels'] as List?;
    if (panelsList == null) {
      return const PagePanelSummaries();
    }

    final panels = panelsList
        .map((p) => TranslatedText.fromMap(p as Map<String, dynamic>))
        .toList();

    return PagePanelSummaries(panels: panels);
  }

  /// The translated summaries for each panel on this page.
  final List<TranslatedText> panels;

  /// Returns the summary for a specific panel at [index] in the given
  /// [languageCode].
  ///
  /// Returns null if [index] is out of bounds.
  String? getSummary(int index, String languageCode) {
    if (index < 0 || index >= panels.length) return null;
    final text = panels[index].forLanguage(languageCode);
    return text.isEmpty ? null : text;
  }

  Map<String, dynamic> toMap() => {
    'panels': panels.map((p) => p.toMap()).toList(),
  };

  @override
  String toString() => 'PagePanelSummaries(panels: ${panels.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PagePanelSummaries && _listEquals(panels, other.panels);

  @override
  int get hashCode => Object.hashAll(panels);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
