import 'package:flutter/foundation.dart' show immutable;

/// Represents text translated into multiple languages.
///
/// Used for page summaries and panel summaries that are available in English,
/// Spanish, and French.
@immutable
class TranslatedText {
  const TranslatedText({Map<String, String> translations = const {}})
    : _translations = translations;

  factory TranslatedText.fromMap(Map<String, dynamic> map) =>
      TranslatedText(translations: Map<String, String>.from(map));

  final Map<String, String> _translations;

  /// English text.
  String get en => _translations['en'] ?? '';

  /// Spanish text.
  String get es => _translations['es'] ?? '';

  /// French text.
  String get fr => _translations['fr'] ?? '';

  /// Returns the text for the given language code.
  String forLanguage(String languageCode) => _translations[languageCode] ?? '';

  /// Returns true if all translations are empty.
  bool get isEmpty => _translations.values.every((v) => v.isEmpty);

  /// Returns true if any translation is non-empty.
  bool get isNotEmpty => !isEmpty;

  /// Returns a new [TranslatedText] with the given translation added.
  TranslatedText withTranslation(String languageCode, String text) {
    final newTranslations = Map<String, String>.from(_translations);
    newTranslations[languageCode] = text;
    return TranslatedText(translations: newTranslations);
  }

  Map<String, String> toMap() => _translations;

  @override
  String toString() => 'TranslatedText(translations: $_translations)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslatedText && _mapEquals(_translations, other._translations);

  @override
  int get hashCode =>
      Object.hashAll(_translations.keys) ^ Object.hashAll(_translations.values);

  static bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }
}
