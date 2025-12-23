// ignore_for_file: prefer_single_quotes

// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
//import 'package:comic_reader/utils/predictions_test.dart';
import 'package:comic_reader/models/predictions.dart';
//import 'dart:ui';

void main() {
  group('Predictions JSON Parsing', () {
    test('should correctly parse sample JSON data', () {
      final sampleJson = {
        "predictions": [
          {
            "bboxes": [
              [0.648006, 0.966222823, 0.507949, 0.939645529],
              [0.35029164, 0.670767188, 0.50756073, 0.939673662],
            ],
            "ids": [
              "6981119557511413760",
              "6981119557511413760",
            ],
            "confidences": [
              0.266333193,
              0.211302295,
            ],
            "displayNames": [
              "panel",
              "panel",
            ]
          }
        ],
        "deployedModelId": "5586122700985729024",
        "model":
            "projects/492405530726/locations/us-central1/models/6098530303901433856",
        "modelDisplayName": "Comics-01-241209",
        "modelVersionId": "1"
      };

      final predictions = Predictions.fromJson(sampleJson);

      // Test metadata fields
      expect(predictions.deployedModelId, equals("5586122700985729024"));
      expect(predictions.modelDisplayName, equals("Comics-01-241209"));
      expect(predictions.modelVersionId, equals("1"));

      // Test panels array
      expect(predictions.panels.length, equals(2));

      // Test first panel bounding box
      // According to the new interpretation:
      // bboxes: [xMin, xMax, yMin, yMax]
      // normalizedBox = Rect.fromLTRB(xMin, yMin, xMax, yMax)
      final firstPanel = predictions.panels[0];
      final firstBox = firstPanel.normalizedBox;
      expect(firstBox.left, equals(0.648006)); // xMin
      expect(firstBox.right, equals(0.966222823)); // xMax
      expect(firstBox.top, equals(0.507949)); // yMin
      expect(firstBox.bottom, equals(0.939645529)); // yMax

      // Check width and height
      expect(firstBox.width, equals(firstBox.right - firstBox.left));
      expect(firstBox.height, equals(firstBox.bottom - firstBox.top));

      // Metadata
      expect(firstPanel.id, equals("6981119557511413760"));
      expect(firstPanel.confidence, equals(0.266333193));
      expect(firstPanel.displayName, equals("panel"));

      // Test second panel bounding box
      final secondPanel = predictions.panels[1];
      final secondBox = secondPanel.normalizedBox;
      expect(secondBox.left, equals(0.35029164)); // xMin
      expect(secondBox.right, equals(0.670767188)); // xMax
      expect(secondBox.top, equals(0.50756073)); // yMin
      expect(secondBox.bottom, equals(0.939673662)); // yMax

      // Check width and height
      expect(secondBox.width, equals(secondBox.right - secondBox.left));
      expect(secondBox.height, equals(secondBox.bottom - secondBox.top));

      // Metadata
      expect(secondPanel.id, equals("6981119557511413760"));
      expect(secondPanel.confidence, equals(0.211302295));
      expect(secondPanel.displayName, equals("panel"));
    });

    test('should handle empty predictions array', () {
      final emptyJson = {
        "predictions": [],
        "deployedModelId": "5586122700985729024",
      };

      final predictions = Predictions.fromJson(emptyJson);
      expect(predictions.panels, isEmpty);
      expect(predictions.deployedModelId, equals("5586122700985729024"));
    });

    test('should handle missing optional fields', () {
      final minimalJson = {
        "predictions": [
          {
            "bboxes": [
              [0.1, 0.2, 0.3, 0.4]
            ],
            "ids": ["123"],
            "confidences": [0.95],
            "displayNames": ["panel"]
          }
        ]
      };

      final predictions = Predictions.fromJson(minimalJson);
      expect(predictions.deployedModelId, isNull);
      expect(predictions.model, isNull);
      expect(predictions.modelDisplayName, isNull);
      expect(predictions.modelVersionId, isNull);
      expect(predictions.panels.length, equals(1));

      final panel = predictions.panels.first;
      final nb = panel.normalizedBox;
      expect(nb.left, equals(0.1));
      expect(nb.right, equals(0.2));
      expect(nb.top, equals(0.3));
      expect(nb.bottom, equals(0.4));
      expect(panel.id, equals("123"));
      expect(panel.confidence, equals(0.95));
      expect(panel.displayName, equals("panel"));
    });
  });
}
