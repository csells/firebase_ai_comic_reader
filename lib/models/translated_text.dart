import 'package:flutter/foundation.dart' show immutable;

/// Represents text translated into multiple languages.
///
/// Used for page summaries and panel summaries that are available in English,
/// Spanish, and French.
@immutable
class TranslatedText {
  const TranslatedText({this.en = '', this.es = '', this.fr = ''});

  factory TranslatedText.fromMap(Map<String, dynamic> map) => TranslatedText(
    en: map['en']?.toString() ?? '',
    es: map['es']?.toString() ?? '',
    fr: map['fr']?.toString() ?? '',
  );

  /// English text.
  final String en;

  /// Spanish text.
  final String es;

  /// French text.
  final String fr;

  /// Returns the text for the given language code.
  ///
  /// Supported codes: 'en', 'es', 'fr'. Returns empty string for unknown codes.
  String forLanguage(String languageCode) => switch (languageCode) {
    'en' => en,
    'es' => es,
    'fr' => fr,
    _ => '',
  };

  /// Returns true if all translations are empty.
  bool get isEmpty => en.isEmpty && es.isEmpty && fr.isEmpty;

  /// Returns true if any translation is non-empty.
  bool get isNotEmpty => !isEmpty;

  Map<String, String> toMap() => {'en': en, 'es': es, 'fr': fr};

  @override
  String toString() => 'TranslatedText(en: $en, es: $es, fr: $fr)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslatedText &&
          en == other.en &&
          es == other.es &&
          fr == other.fr;

  @override
  int get hashCode => Object.hash(en, es, fr);
}
