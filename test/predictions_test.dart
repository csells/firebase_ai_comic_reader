import 'package:comic_reader/models/predictions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Predictions JSON Parsing', () {
    test(
      'should correctly parse sample JSON data and preserve original order',
      () {
        final sampleJson = {
          "predictions": [
            {
              "bboxes": [
                [0.6, 0.9, 0.5, 0.9], // Panel 2
                [0.1, 0.4, 0.5, 0.9], // Panel 1
                [0.0, 0.9, 0.0, 0.4], // Panel 0
              ],
              "ids": ["p2", "p1", "p0"],
              "confidences": [0.9, 0.9, 0.9],
              "displayNames": ["panel", "panel", "panel"],
            },
          ],
        };

        final predictions = Predictions.fromJson(sampleJson);

        // Verify that original order is preserved (assuming the AI provides reading order)
        expect(predictions.panels.length, equals(3));
        expect(predictions.panels[0].id, equals("p2"));
        expect(predictions.panels[1].id, equals("p1"));
        expect(predictions.panels[2].id, equals("p0"));
      },
    );

    test('should handle empty predictions array', () {
      final emptyJson = {"predictions": [], "deployedModelId": "empty-model"};

      final predictions = Predictions.fromJson(emptyJson);
      expect(predictions.panels, isEmpty);
    });
  });
}
