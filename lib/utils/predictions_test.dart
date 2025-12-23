import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:comic_reader/models/predictions.dart';
// 241211: SAMPLE DATA (JSON):
/*
{
  "predictions": [
    {
      "bboxes": [
        [
          0.648006,
          0.966222823,
          0.507949,
          0.939645529
        ],
        [
          0.35029164,
          0.670767188,
          0.50756073,
          0.939673662
        ],
        [
          0.0628743693,
          0.917342544,
          0.0505616069,
          0.517016113
        ],
        [
          0.0478149056,
          0.376912713,
          0.506715238,
          0.94164896
        ]
      ],
      "ids": [
        "6981119557511413760",
        "6981119557511413760",
        "6981119557511413760",
        "6981119557511413760"
      ],
      "confidences": [
        0.266333193,
        0.211302295,
        0.183786958,
        0.147128344
      ],
      "displayNames": [
        "panel",
        "panel",
        "panel",
        "panel"
      ]
    }
  ],
  "deployedModelId": "5586122700985729024",
  "model": "projects/492405530726/locations/us-central1/models/6098530303901433856",
  "modelDisplayName": "Comics-01-241209",
  "modelVersionId": "1"
}
*/

/// Utility class for loading and managing test prediction data from JSON files.
///
/// This class provides functionality to load panel detection predictions from JSON files
/// for testing purposes. It caches the loaded predictions to avoid repeated file reads.
class PredictionsTest {
  /// Cache of test predictions, keyed by image filename.
  /// The value is the parsed JSON prediction data.
  static Map<String, Map<String, dynamic>>? _predictions;

  /// Gets the predictions for a specific image file.
  ///
  /// [imageFilename] The name of the image file (with .jpg extension).
  /// Returns a [Predictions] object containing the panel detection data.
  /// If no predictions exist for the image, returns an empty [Predictions] object.
  static Future<Predictions> getPredictionFor(String imageFilename) async {
    if (_predictions == null) {
      await _loadPredictions();
    }
    final jsonData = _predictions?[imageFilename];
    if (jsonData != null) {
      final predictions = Predictions.fromJson(jsonData);
      return predictions; //.panels;
    }
    return Predictions(panels: []);
  }

  /// Gets all cached predictions.
  ///
  /// Returns a map where keys are image filenames and values are the raw prediction data.
  /// Loads the predictions if they haven't been loaded yet.
  static Future<Map<String, Map<String, dynamic>>> getAllPredictions() async {
    if (_predictions == null) {
      await _loadPredictions();
    }
    return _predictions!;
  }

  /// Loads predictions from JSON files in the assets directory.
  ///
  /// This method scans the assets directory for JSON files containing panel detection
  /// predictions and caches them in memory. The predictions can be in either array
  /// or object format.
  static Future<void> _loadPredictions() async {
    _predictions = {};

    // Get list of assets
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);

    // Filter for JSON files in the test_data_json_predictions directory
    final jsonFiles = manifestMap.keys.where((String key) =>
        key.startsWith('lib/assets/test_data_json_predictions/') &&
        key.endsWith('.json'));

    // Load each JSON file
    for (var jsonFile in jsonFiles) {
      try {
        // Load and parse JSON content
        final String jsonContent = await rootBundle.loadString(jsonFile);
        final dynamic jsonData = json.decode(jsonContent);

        // Create key by replacing .json with .jpg in the filename
        final String filename =
            jsonFile.split('/').last.replaceAll('.json', '.jpg');

        // Check if jsonData is a List or a Map and store accordingly
        if (jsonData is List) {
          _predictions![filename] = {'predictions': jsonData};
        } else if (jsonData is Map<String, dynamic>) {
          _predictions![filename] = jsonData;
        } else {
          debugPrint('Unexpected JSON format in file $jsonFile');
        }
      } catch (e) {
        debugPrint('Error loading prediction file $jsonFile: $e');
      }
    }
  }
}
