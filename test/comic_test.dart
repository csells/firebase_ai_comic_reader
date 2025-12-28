import 'package:comic_reader/models/comic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Comic Model Tests', () {
    test('should create Comic from map and back to map', () {
      final now = DateTime.now();
      final map = {
        'id': 'test-comic',
        'title': 'Test Comic',
        'thumbnailImage': 'thumb.jpg',
        'author': 'Author',
        'series': 'Series',
        'pageCount': 10,
        'currentPage': 2,
        'lastReadDate': now.toIso8601String(),
        'pageImages': ['page1.jpg', 'page2.jpg'],
        'pageSummaries': [
          {'en': 'Page 1 summary'},
        ],
        'panelSummaries': [
          {
            'panels': [
              {'en': 'Panel 1 summary'},
            ],
          },
        ],
      };

      final comic = Comic.fromMap(map);

      expect(comic.id, 'test-comic');
      expect(comic.title, 'Test Comic');
      expect(comic.pageCount, 10);
      expect(comic.pageSummaries.length, 1);
      expect(comic.pageSummaries[0]['en'], 'Page 1 summary');
      expect(comic.panelSummaries.length, 1);
      expect(comic.panelSummaries[0]['panels'][0]['en'], 'Panel 1 summary');

      final backToMap = comic.toMap();
      expect(backToMap['id'], 'test-comic');
      expect(backToMap['pageSummaries'], isA<List>());
      expect((backToMap['pageSummaries'] as List)[0]['en'], 'Page 1 summary');
    });

    test('should handle missing optional fields in fromMap', () {
      final map = {
        'id': 'test-comic',
        'title': 'Test Comic',
        'lastReadDate': DateTime.now().toIso8601String(),
      };

      final comic = Comic.fromMap(map);

      expect(comic.id, 'test-comic');
      expect(comic.pageCount, 0);
      expect(comic.pageSummaries, isEmpty);
      expect(comic.panelSummaries, isEmpty);
    });
  });
}
