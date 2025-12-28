import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/panel.dart';

/// Service responsible for interacting with Gemini AI to analyze comic pages.
class GeminiService {
  final GenerativeModel? _mockModel;

  GeminiService({GenerativeModel? model}) : _mockModel = model;

  /// Analyzes a comic page using Gemini.
  ///
  /// Returns a [Map] containing:
  /// - 'summaries': `Map<String, String>` (language codes to summary text)
  /// - 'panels': `List<Panel>` (detected panel bounding boxes)
  /// - 'panel_summaries': `List<Map<String, String>>` (per-panel translations)
  Future<Map<String, dynamic>> analyzePage(Uint8List imageBytes) async {
    final responseSchema = Schema.object(
      properties: {
        'en': Schema.string(description: 'English summary of the page'),
        'es': Schema.string(description: 'Spanish summary of the page'),
        'fr': Schema.string(description: 'French summary of the page'),
        'panels': Schema.array(
          items: Schema.object(
            properties: {
              'box_2d': Schema.object(
                properties: {
                  'ymin': Schema.integer(description: 'Top coordinate 0-1000'),
                  'xmin': Schema.integer(description: 'Left coordinate 0-1000'),
                  'ymax': Schema.integer(
                    description: 'Bottom coordinate 0-1000',
                  ),
                  'xmax': Schema.integer(
                    description: 'Right coordinate 0-1000',
                  ),
                },
              ),
              'en': Schema.string(description: 'English summary of the panel'),
              'es': Schema.string(description: 'Spanish summary of the panel'),
              'fr': Schema.string(description: 'French summary of the panel'),
            },
          ),
        ),
      },
    );

    final schemaJson = jsonEncode(responseSchema.toJson());

    final systemInstruction = Content.system(
      'You are an expert OCR and translation model specializing in comic books. '
      'Your task is to analyze a comic book page and: \n'
      '1. Extract the text and arrange it narratively. \n'
      '2. Summarize the story/content in three languages: English (en), Spanish (es), and French (fr). \n'
      '3. Detect all comic panels and provide their bounding boxes in normalized coordinates [0, 1000]. \n'
      '4. Provide a narrative summary for each panel in the same three languages. \n'
      '5. IMPORTANT: You MUST return the panels in their natural reading order (typically top-to-bottom, left-to-right). \n'
      '\n'
      'IMPORTANT: You MUST return a valid JSON object strictly following this schema: \n'
      '$schemaJson \n'
      '\n'
      'If no text or content is present, return empty strings for the summaries.',
    );

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
          TextPart('Analyze this comic page.'),
        ]),
      ]);

      final contentText = response.text;
      if (contentText == null) {
        throw Exception('Gemini response returned no text content');
      }

      final parsed = jsonDecode(contentText) as Map<String, dynamic>;

      // Basic validation of expected keys
      if (!parsed.containsKey('en') ||
          !parsed.containsKey('es') ||
          !parsed.containsKey('fr')) {
        throw Exception('Invalid Gemini response: Missing summary fields');
      }

      final result = <String, dynamic>{
        'summaries': {
          'en': parsed['en']?.toString() ?? '',
          'es': parsed['es']?.toString() ?? '',
          'fr': parsed['fr']?.toString() ?? '',
        },
      };

      if (parsed.containsKey('panels')) {
        final List<dynamic> panelsJson = parsed['panels'] as List;
        final List<Panel> panels = [];
        final List<Map<String, String>> panelSummaries = [];

        for (var j = 0; j < panelsJson.length; j++) {
          final panelData = panelsJson[j] as Map<String, dynamic>;
          final box = panelData['box_2d'] as Map<String, dynamic>;

          if (box['ymin'] == null ||
              box['xmin'] == null ||
              box['ymax'] == null ||
              box['xmax'] == null) {
            debugPrint(
              'Warning: Skipping panel $j due to missing box coordinates',
            );
            continue;
          }

          final yMin = (box['ymin'] as num).toDouble() / 1000.0;
          final xMin = (box['xmin'] as num).toDouble() / 1000.0;
          final yMax = (box['ymax'] as num).toDouble() / 1000.0;
          final xMax = (box['xmax'] as num).toDouble() / 1000.0;

          panels.add(
            Panel(
              id: 'panel_$j',
              displayName: 'panel',
              confidence: 1.0,
              normalizedBox: Rect.fromLTRB(xMin, yMin, xMax, yMax),
            ),
          );

          panelSummaries.add({
            'en': panelData['en']?.toString() ?? '',
            'es': panelData['es']?.toString() ?? '',
            'fr': panelData['fr']?.toString() ?? '',
          });
        }
        result['panels'] = panels;
        result['panel_summaries'] = panelSummaries;
      } else {
        result['panels'] = <Panel>[];
        result['panel_summaries'] = <Map<String, String>>[];
      }
      return result;
    } catch (e) {
      debugPrint('Gemini Service Error: $e');
      rethrow;
    }
  }
}
