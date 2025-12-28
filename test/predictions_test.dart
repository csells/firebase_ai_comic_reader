import 'package:comic_reader/models/predictions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Predictions Model', () {
    test('should serialize and deserialize correctly', () {
      final predictions = Predictions(panels: []);
      final map = predictions.toMap();
      final restored = Predictions.fromMap(map);

      expect(restored.panels, isEmpty);
    });

    test('should handle fromMap with null panels', () {
      final predictions = Predictions.fromMap({'panels': null});
      expect(predictions.panels, isEmpty);
    });
  });
}
