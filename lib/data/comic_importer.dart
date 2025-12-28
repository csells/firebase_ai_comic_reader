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

  /// Imports a comic from CBZ bytes.
  ///
  /// Steps:
  /// 1. Validate user is logged in.
  /// 2. Generate a unique comic ID based on filename.
  /// 3. Decompress and filter images.
  /// 4. Upload pages to Firebase Storage (cover 0%..70%).
  /// 5. Generate & upload thumbnail (no extra progress shift, it finishes near
  ///    70%).
  /// 6. Save comic in Firestore (initial).
  /// 7. (Predictions) Fetch panel data for each page (cover 70%..85%).
  /// 8. (Summaries) Summarize each page (cover 85%..100%).
  ///
  /// If cancelled or on error, attempts cleanup.
  ///
  /// The same [progressStream] is used for all phases. We simply scale the
  /// fraction so the bar stays between 0 and 1 overall.
  Future<String> importComic(
    Uint8List comicBytes,
    String fileName,
    StreamController<double> progressStream,
    Future<void> cancelFuture,
  ) async {
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final baseName = path.basenameWithoutExtension(fileName);
    final comicId = baseName;
    final userId = user.uid;
    const rootPath = 'comic_store';
    final userRootPath = '$rootPath/$userId';
    final comicRootPath = '$userRootPath/comics/$comicId';
    final thumbnailPath = '$userRootPath/thumbnails/$comicId.jpg';

    debugPrint('Importing comic: $comicId for user: $userId');

    var isCancelled = false;
    unawaited(cancelFuture.then((_) => isCancelled = true));

    void checkCancellation() {
      if (isCancelled) {
        throw Exception('Import cancelled');
      }
    }

    try {
      debugPrint('Decompressing comic archive: $fileName');
      // 1) Decompress archive
      var imageFiles = <zip.ArchiveFile>[];

      final fileExt = path.extension(fileName).toLowerCase();
      if (fileExt == '.cbr') {
        debugPrint('RAR archive detected (.cbr). Using RarExtractor.');
        final extractor = getRarExtractor();
        imageFiles.addAll(await extractor.extractImages(comicBytes));
      } else {
        debugPrint('Zip archive detected (.cbz). Using ZipDecoder.');
        // Default to Zip (CBZ)
        try {
          final archive = zip.ZipDecoder().decodeBytes(comicBytes);
          imageFiles = _extractImagesFromArchive(archive);
          debugPrint(
            'Zip extraction complete. Found ${imageFiles.length} images.',
          );
        } catch (e) {
          debugPrint('Error during Zip decoding: $e');
          rethrow;
        }
      }

      checkCancellation();

      debugPrint('Final filtered image count: ${imageFiles.length}');
      // 2) Extract relevant image files (already filtered above) Check count
      if (imageFiles.isEmpty) {
        throw Exception('No valid image files found in the provided archive.');
      }

      // Phase 1: Upload & Analyze images => 0% .. 100%
      final totalFiles = imageFiles.length;
      final pageUrls = <String>[];
      final pageSummaries = List<TranslatedText?>.filled(totalFiles, null);
      final panelSummaries = List<PagePanelSummaries?>.filled(totalFiles, null);
      final predictions = <Predictions>[];

      for (var i = 0; i < totalFiles; i++) {
        checkCancellation();
        final file = imageFiles[i];
        final filename = path.basename(file.name);
        final innerFilePath = '$comicRootPath/$filename';
        debugPrint('Processing page ${i + 1}/$totalFiles: $filename');

        final imageBytes = Uint8List.fromList(file.content as List<int>);

        // 1. Upload
        final ref = _storage.ref(innerFilePath);
        await ref.putData(imageBytes);
        final downloadUrl = await ref.getDownloadURL();
        pageUrls.add(downloadUrl);

        // 2. Analyze
        try {
          final analysis = await _analyzePage(imageBytes);

          // Save Page Summaries
          final summariesMap = analysis['summaries'] as Map<String, String>;
          pageSummaries[i] = TranslatedText(
            en: summariesMap['en'] ?? '',
            es: summariesMap['es'] ?? '',
            fr: summariesMap['fr'] ?? '',
          );

          // Save Panels & Panel Summaries
          if (analysis.containsKey('panels')) {
            final panelsList = analysis['panels'] as List<Panel>;
            predictions.add(Predictions(panels: panelsList));

            // Extract Panel Summaries
            final panelSummaryMaps =
                analysis['panel_summaries'] as List<Map<String, String>>;
            final panelTexts = panelSummaryMaps
                .map(
                  (m) => TranslatedText(
                    en: m['en'] ?? '',
                    es: m['es'] ?? '',
                    fr: m['fr'] ?? '',
                  ),
                )
                .toList();
            panelSummaries[i] = PagePanelSummaries(panels: panelTexts);
          } else {
            predictions.add(Predictions(panels: []));
            panelSummaries[i] = const PagePanelSummaries();
          }
        } catch (e) {
          debugPrint('Fatal error analyzing page $i: $e');
          rethrow; // Surface to the user immediately
        }

        // 3. Progress
        final progress = (i + 1) / totalFiles;
        progressStream.add(progress);
      }

      // Generate & upload thumbnail
      await _createThumbnail(
        imageFiles.first,
        thumbnailPath,
        isCancelled: () => isCancelled,
      );
      checkCancellation();

      // Save complete comic to Firestore
      final comic = Comic(
        id: comicId,
        title: comicId,
        thumbnailImage: '$userRootPath/thumbnails/$comicId.jpg',
        pageCount: pageUrls.length,
        pageImages: pageUrls,
        predictions: predictions,
        pageSummaries: pageSummaries
            .map((s) => s ?? const TranslatedText())
            .toList(),
        panelSummaries: panelSummaries
            .map((p) => p ?? const PagePanelSummaries())
            .toList(),
      );

      await _repository.addComic(userId, comic);
      debugPrint('Comic saved to Firestore: $comicId');

      return comicId;
    } catch (e, stackTrace) {
      // Cleanup partial uploads on error or cancellation
      debugPrint('Import failed: $e');
      try {
        await _cleanupIfCancelled(user.uid, comicId);
      } on Exception catch (cleanupError) {
        debugPrint(
          'Cleanup failed (expected if no files uploaded): $cleanupError',
        );
        // Do NOT rethrow cleanupError, it would mask the original error 'e'
      }
      // Rethrow the original error and stack trace
      Error.throwWithStackTrace(e, stackTrace);
    } finally {
      await progressStream.close();
    }
  }

  /// Extract images from the CBZ archive while ignoring known irrelevant files.
  List<zip.ArchiveFile> _extractImagesFromArchive(zip.Archive archive) =>
      _extractImagesFromArchiveList(archive.files);

  /// Helper for both Zip and Rar lists
  List<zip.ArchiveFile> _extractImagesFromArchiveList(
    List<zip.ArchiveFile> files,
  ) {
    final imageFiles = files
        .where(
          (file) =>
              file.isFile &&
              !_shouldSkipFile(file.name.toLowerCase()) &&
              _isAllowedExtension(file.name.toLowerCase()),
        )
        .toList();

    imageFiles.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return imageFiles;
  }

  bool _shouldSkipFile(String filename) {
    for (final prefix in _ignoredPrefixes) {
      if (filename.startsWith(prefix.toLowerCase())) {
        return true;
      }
    }
    return _ignoredFiles.contains(filename);
  }

  bool _isAllowedExtension(String filename) {
    final extension = path.extension(filename).toLowerCase();
    return _allowedExtensions.contains(extension);
  }

  /// Creates a thumbnail from the first image file and uploads it.
  Future<void> _createThumbnail(
    zip.ArchiveFile firstImageFile,
    String thumbnailPath, {
    required bool Function() isCancelled,
  }) async {
    if (isCancelled()) {
      throw Exception('Import cancelled');
    }

    debugPrint('Creating thumbnail for: $thumbnailPath');
    final originalImageData = Uint8List.fromList(
      firstImageFile.content as List<int>,
    );
    final originalImage = img.decodeImage(originalImageData);
    if (originalImage == null) {
      throw Exception('Failed to decode first image for thumbnail.');
    }

    final resizedThumbnail = img.copyResize(
      originalImage,
      width: 400,
      interpolation: img.Interpolation.linear,
    );
    final thumbnailBytes = Uint8List.fromList(
      img.encodeJpg(resizedThumbnail, quality: 90),
    );

    if (isCancelled()) {
      throw Exception('Import cancelled');
    }

    final thumbnailRef = _storage.ref(thumbnailPath);
    await thumbnailRef.putData(thumbnailBytes);
    debugPrint('Thumbnail uploaded: $thumbnailPath');
  }

  final GeminiService _geminiService = GeminiService();

  /// Analyzes a comic page using Gemini.
  Future<Map<String, dynamic>> _analyzePage(Uint8List imageBytes) async =>
      _geminiService.analyzePage(imageBytes);

  /// Deletes partial upload if import is cancelled or error.
  Future<void> _cleanupIfCancelled(String userId, String comicId) async {
    debugPrint('Cleaning up partial upload: $userId, $comicId');
    await _repository.cleanupPartialUpload(userId, comicId);
  }
}
