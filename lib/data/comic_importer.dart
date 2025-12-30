import 'dart:async';

import 'package:archive/archive.dart' as zip;
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_storage/firebase_storage.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

import '../models/comic.dart';
import '../models/page_panel_summaries.dart';
import '../models/panel.dart';
import '../models/predictions.dart';
import '../models/translated_text.dart';
import 'comic_repository_firebase.dart';
import 'gemini_service.dart';
import 'rar_extractor/rar_extractor.dart';

class ComicImporter {
  ComicImporter({this.enablePredictions = true});
  final fs.FirebaseStorage _storage = fs.FirebaseStorage.instance;
  final ComicRepositoryFirebase _repository = ComicRepositoryFirebase();
  final GeminiService _geminiService = GeminiService();

  final bool enablePredictions;

  static const List<String> _ignoredPrefixes = [
    '.',
    '__MACOSX',
    r'$RECYCLE.BIN',
    'System Volume Information',
    '__macosx',
    r'$recycle.bin',
    'system volume information',
  ];

  static const List<String> _ignoredFiles = [
    'thumbs.db',
    'desktop.ini',
    '.ds_store',
  ];

  static const List<String> _allowedExtensions = ['.jpg', '.jpeg', '.png'];

  /// Imports a comic from CBZ/CBR bytes.
  Future<String> importComic(
    Uint8List comicBytes,
    String fileName,
    StreamController<double> progressStream,
    Future<void> cancelFuture,
  ) async {
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final comicId = path.basenameWithoutExtension(fileName);
    final userId = user.uid;
    final userRootPath = 'comic_store/$userId';
    final comicRootPath = '$userRootPath/comics/$comicId';
    final thumbnailPath = '$userRootPath/thumbnails/$comicId.jpg';

    debugPrint('Importing comic: $comicId for user: $userId');

    var isCancelled = false;
    unawaited(cancelFuture.then((_) => isCancelled = true));

    void checkCancellation() {
      if (isCancelled) throw Exception('Import cancelled');
    }

    try {
      // 1. Process Archive
      final imageFiles = await _extractImages(comicBytes, fileName);
      checkCancellation();

      if (imageFiles.isEmpty) {
        throw Exception('No valid image files found in the archive.');
      }

      // 2. Upload & Analyze Pages
      final pageData = await _processPages(
        imageFiles,
        comicRootPath,
        progressStream,
        checkCancellation,
      );

      // 3. Create Thumbnail
      await _createThumbnail(
        imageFiles.first,
        thumbnailPath,
        checkCancellation: checkCancellation,
      );

      // 4. Save to Firestore
      final comic = Comic(
        id: comicId,
        title: comicId,
        thumbnailImage: thumbnailPath,
        pageCount: pageData.urls.length,
        pageImages: pageData.urls,
        predictions: pageData.predictions,
        pageSummaries: pageData.summaries,
        panelSummaries: pageData.panelSummaries,
      );

      await _repository.addComic(userId, comic);
      debugPrint('Comic saved to Firestore: $comicId');

      return comicId;
    } catch (e, stackTrace) {
      debugPrint('Import failed: $e');
      await _cleanup(userId, comicId);
      Error.throwWithStackTrace(e, stackTrace);
    } finally {
      await progressStream.close();
    }
  }

  // --- Archive Processing ---

  Future<List<zip.ArchiveFile>> _extractImages(
    Uint8List comicBytes,
    String fileName,
  ) async {
    final fileExt = path.extension(fileName).toLowerCase();
    if (fileExt == '.cbr') {
      return getRarExtractor().extractImages(comicBytes);
    }

    try {
      final archive = zip.ZipDecoder().decodeBytes(comicBytes);
      final images = archive.files
          .where(
            (f) =>
                f.isFile &&
                !_shouldSkipFile(f.name.toLowerCase()) &&
                _isAllowedExtension(f.name.toLowerCase()),
          )
          .toList();

      images.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return images;
    } catch (e) {
      throw Exception('Failed to decode ZIP archive: $e');
    }
  }

  bool _shouldSkipFile(String filename) {
    final lower = filename.toLowerCase();
    return _ignoredPrefixes.any((p) => lower.startsWith(p.toLowerCase())) ||
        _ignoredFiles.contains(lower);
  }

  bool _isAllowedExtension(String filename) =>
      _allowedExtensions.contains(path.extension(filename).toLowerCase());

  // --- Page Processing ---

  Future<
    ({
      List<String> urls,
      List<TranslatedText> summaries,
      List<PagePanelSummaries> panelSummaries,
      List<Predictions> predictions,
    })
  >
  _processPages(
    List<zip.ArchiveFile> imageFiles,
    String comicRootPath,
    StreamController<double> progressStream,
    VoidCallback checkCancellation,
  ) async {
    final urls = <String>[];
    final summaries = <TranslatedText>[];
    final panelSummaries = <PagePanelSummaries>[];
    final predictions = <Predictions>[];

    for (var i = 0; i < imageFiles.length; i++) {
      checkCancellation();
      final file = imageFiles[i];
      final imageBytes = Uint8List.fromList(file.content as List<int>);

      // Upload
      final fileName = path.basename(file.name);
      final ref = _storage.ref('$comicRootPath/$fileName');
      await ref.putData(imageBytes);
      urls.add(await ref.getDownloadURL());

      // Analyze
      final analysis = await _geminiService.analyzePage(imageBytes);
      summaries.add(
        TranslatedText(translations: {'en': analysis['summary'] as String}),
      );

      final panels = (analysis['panels'] as List<Panel>?) ?? [];
      predictions.add(Predictions(panels: panels));

      final panelSummaryStrings =
          (analysis['panel_summaries'] as List<String>?) ?? [];
      panelSummaries.add(
        PagePanelSummaries(
          panels: panelSummaryStrings
              .map((s) => TranslatedText(translations: {'en': s}))
              .toList(),
        ),
      );

      progressStream.add((i + 1) / imageFiles.length);
    }

    return (
      urls: urls,
      summaries: summaries,
      panelSummaries: panelSummaries,
      predictions: predictions,
    );
  }

  // --- Thumbnail & Cleanup ---

  Future<void> _createThumbnail(
    zip.ArchiveFile firstImageFile,
    String thumbnailPath, {
    required VoidCallback checkCancellation,
  }) async {
    checkCancellation();
    debugPrint('Creating thumbnail: $thumbnailPath');

    final bytes = Uint8List.fromList(firstImageFile.content as List<int>);
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image for thumbnail');

    final thumbnail = img.copyResize(
      image,
      width: 400,
      interpolation: img.Interpolation.linear,
    );
    final thumbnailBytes = Uint8List.fromList(
      img.encodeJpg(thumbnail, quality: 90),
    );

    checkCancellation();
    await _storage.ref(thumbnailPath).putData(thumbnailBytes);
  }

  Future<void> _cleanup(String userId, String comicId) async {
    try {
      debugPrint('Cleaning up failed import: $comicId');
      await _repository.deleteComic(userId, comicId);
    } on Exception catch (e) {
      debugPrint('Cleanup failed (expected if nothing was saved): $e');
    }
  }
}
