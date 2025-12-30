import 'package:comic_reader/models/comic.dart';
import 'package:comic_reader/models/page_panel_summaries.dart';
import 'package:comic_reader/models/translated_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Comic Model', () {
    test('fromMap creates a valid Comic object', () {
      final map = {
        'id': 'test-id',
        'title': 'Test Comic',
        'pageCount': 2,
        'currentPage': 1,
        'lastReadDate': '2023-10-27T10:00:00.000',
        'pageImages': ['url1', 'url2'],
        'predictions': {
          'pagePredictions': [
            {
              'panels': [
                {
                  'id': 'p1',
                  'displayName': 'panel',
                  'confidence': 1.0,
                  'normalizedBox': {
                    'left': 0.1,
                    'top': 0.1,
                    'right': 0.5,
                    'bottom': 0.5,
                  },
                },
              ],
            },
          ],
        },
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

      expect(comic.id, 'test-id');
      expect(comic.title, 'Test Comic');
      expect(comic.pageCount, 2);
      expect(comic.currentPage, 1);
      expect(comic.pageImages, ['url1', 'url2']);
      expect(comic.predictions.length, 1);
      expect(comic.predictions.first.panels.length, 1);
      expect(comic.pageSummaries.length, 1);
      expect(comic.pageSummaries.first.en, 'Page 1 summary');
      expect(comic.panelSummaries.length, 1);
      expect(comic.panelSummaries.first.panels.first.en, 'Panel 1 summary');
    });

    test('toMap returns a valid map', () {
      final comic = Comic(
        id: 'test-id',
        title: 'Test Comic',
        pageCount: 1,
        pageImages: ['url1'],
        pageSummaries: [
          const TranslatedText(translations: {'en': 'Summary'}),
        ],
        panelSummaries: [
          const PagePanelSummaries(
            panels: [
              TranslatedText(translations: {'en': 'Panel'}),
            ],
          ),
        ],
      );

      final map = comic.toMap();

      expect(map['id'], 'test-id');
      expect(map['title'], 'Test Comic');
      expect(map['pageCount'], 1);
      expect(map['pageImages'], ['url1']);
      expect(map['pageSummaries'], [
        {'en': 'Summary'},
      ]);
      expect(map['panelSummaries'], [
        {
          'panels': [
            {'en': 'Panel'},
          ],
        },
      ]);
    });
  });
}
