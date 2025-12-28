import 'package:comic_reader/models/predictions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Predictions JSON Parsing', () {
    test(
      'should correctly parse sample JSON data with reading order logic',
      () {
        final sampleJson = {
          "predictions": [
            {
              "bboxes": [
                [0.6, 0.9, 0.5, 0.9], // Panel 2 (right)
                [0.1, 0.4, 0.5, 0.9], // Panel 1 (left)
                [0.0, 0.9, 0.0, 0.4], // Panel 0 (top)
              ],
              "ids": ["p2", "p1", "p0"],
              "confidences": [0.9, 0.9, 0.9],
              "displayNames": ["panel", "panel", "panel"],
            },
          ],
          "deployedModelId": "test-model",
        };

        final predictions = Predictions.fromJson(sampleJson);

        // Verify sorting: Top-to-bottom, then Left-to-right
        expect(predictions.panels.length, equals(3));
        expect(predictions.panels[0].id, equals("p0")); // Top-most
        expect(predictions.panels[1].id, equals("p1")); // Middle-row, Left
        expect(predictions.panels[2].id, equals("p2")); // Middle-row, Right
      },
    );

    test('should handle empty predictions array', () {
      final emptyJson = {"predictions": [], "deployedModelId": "empty-model"};

      final predictions = Predictions.fromJson(emptyJson);
      expect(predictions.panels, isEmpty);
    });
  });
}
