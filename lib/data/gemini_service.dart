import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/panel.dart';

/// Service responsible for interacting with Gemini AI to analyze comic pages.
class GeminiService {
  GeminiService({GenerativeModel? model}) : _mockModel = model;
  final GenerativeModel? _mockModel;

  /// Analyzes a comic page using Gemini.
  Future<Map<String, dynamic>> analyzePage(Uint8List imageBytes) async {
    final responseSchema = _getAnalyzePageSchema();
    final systemInstruction = _getAnalyzePageSystemInstruction(responseSchema);

    final model =
        _mockModel ??
        FirebaseAI.googleAI().generativeModel(
          model: 'gemini-3-flash-preview',
          systemInstruction: systemInstruction,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: responseSchema,
          ),
        );

    try {
      final response = await model.generateContent([
        Content.multi([
          InlineDataPart('image/jpeg', imageBytes),
          const TextPart('Analyze this comic page.'),
        ]),
      ]);

      final contentText = response.text;
      if (contentText == null) {
        throw Exception('Gemini response returned no text content');
      }

      return _parseAnalyzePageResponse(contentText);
    } catch (e) {
      debugPrint('Gemini Service Error: $e');
      rethrow;
    }
  }

  /// Translates a list of texts into the target language.
  Future<List<String>> translate(
    List<String> texts,
    String targetLanguage,
  ) async {
    if (texts.isEmpty) return [];

    final responseSchema = _getTranslateSchema();
    final systemInstruction = _getTranslateSystemInstruction(targetLanguage);

    final model =
        _mockModel ??
        FirebaseAI.googleAI().generativeModel(
          model: 'gemini-3-flash-preview',
          systemInstruction: systemInstruction,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: responseSchema,
          ),
        );

    try {
      final response = await model.generateContent([
        Content.text('Translate these strings:\n${jsonEncode(texts)}'),
      ]);

      final contentText = response.text;
      if (contentText == null) {
        throw Exception('Gemini translation response returned no text content');
      }

      final parsed = jsonDecode(contentText) as Map<String, dynamic>;
      final translations = List<String>.from(parsed['translations'] as List);

      if (translations.length != texts.length) {
        debugPrint(
          'Warning: Translation count mismatch. Expected ${texts.length}, '
          'got ${translations.length}',
        );
      }

      return translations;
    } catch (e) {
      debugPrint('Gemini Translation Error: $e');
      rethrow;
    }
  }

  // --- Prompts & Schemas (The "Star" of the Service) ---

  Schema _getAnalyzePageSchema() => Schema.object(
    properties: {
      'summary': Schema.string(description: 'English summary of the page'),
      'panels': Schema.array(
        items: Schema.object(
          properties: {
            'box_2d': Schema.object(
              properties: {
                'ymin': Schema.integer(description: 'Top coordinate 0-1000'),
                'xmin': Schema.integer(description: 'Left coordinate 0-1000'),
                'ymax': Schema.integer(description: 'Bottom coordinate 0-1000'),
                'xmax': Schema.integer(description: 'Right coordinate 0-1000'),
              },
            ),
            'summary': Schema.string(
              description: 'English summary of the panel',
            ),
          },
        ),
      ),
    },
  );

  Content _getAnalyzePageSystemInstruction(Schema schema) {
    final schemaJson = jsonEncode(schema.toJson());
    return Content.system('''
You are an expert OCR and narrative analysis model specializing in comic books. 
Your task is to analyze a comic book page and:
1. Extract the text and arrange it narratively.
2. Summarize the story/content in English.
3. Detect all comic panels and provide their bounding boxes in normalized coordinates [0, 1000].
4. Provide a narrative summary for each panel in English.
5. Return the panels in their natural reading order (typically top-to-bottom, left-to-right).

Return a valid JSON object strictly following this schema:
$schemaJson

If no text or content is present, return empty strings for the summaries.
''');
  }

  Schema _getTranslateSchema() => Schema.object(
    properties: {
      'translations': Schema.array(
        items: Schema.string(description: 'Translated text'),
      ),
    },
  );

  Content _getTranslateSystemInstruction(String targetLanguage) =>
      Content.system('''
You are a professional translator.
Translate the following list of strings into the target language: $targetLanguage.
Maintain the order and the tone of the original texts.
Return a valid JSON object strictly following the specified schema.
''');

  // --- Plumbing (Coordinate Math & Parsing) ---

  Map<String, dynamic> _parseAnalyzePageResponse(String contentText) {
    final parsed = jsonDecode(contentText) as Map<String, dynamic>;

    final result = <String, dynamic>{
      'summary': parsed['summary']?.toString() ?? '',
    };

    final panelsJson = parsed['panels'] as List;
    final panels = <Panel>[];
    final panelSummaries = <String>[];

    for (var j = 0; j < panelsJson.length; j++) {
      final panelData = panelsJson[j] as Map<String, dynamic>;
      final box = panelData['box_2d'] as Map<String, dynamic>;

      if (box['ymin'] == null ||
          box['xmin'] == null ||
          box['ymax'] == null ||
          box['xmax'] == null) {
        debugPrint('Warning: Skipping panel $j due to missing box coordinates');
        continue;
      }

      // Convert from [0, 1000] integer scale to [0.0, 1.0] double scale
      final yMin = (box['ymin'] as num).toDouble() / 1000.0;
      final xMin = (box['xmin'] as num).toDouble() / 1000.0;
      final yMax = (box['ymax'] as num).toDouble() / 1000.0;
      final xMax = (box['xmax'] as num).toDouble() / 1000.0;

      panels.add(
        Panel(
          id: 'panel_$j',
          displayName: 'panel',
          confidence: 1,
          normalizedBox: Rect.fromLTRB(xMin, yMin, xMax, yMax),
        ),
      );

      panelSummaries.add(panelData['summary']?.toString() ?? '');
    }
    result['panels'] = panels;
    result['panel_summaries'] = panelSummaries;

    return result;
  }
}
