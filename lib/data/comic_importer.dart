import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:archive/archive.dart' as zip;
import 'package:comic_reader/data/comic_repository_firebase.dart';
import 'package:comic_reader/models/comic.dart';
import 'package:comic_reader/models/comic_predictions.dart';
import 'package:comic_reader/models/panel.dart';
import 'package:comic_reader/models/predictions.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_storage/firebase_storage.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:rar/rar.dart';

class ComicImporter {
  final fs.FirebaseStorage _storage = fs.FirebaseStorage.instance;
  final ComicRepositoryFirebase _repository = ComicRepositoryFirebase();

  // Toggle whether we do panel predictions or skip them.
  final bool enablePredictions;

  ComicImporter({this.enablePredictions = true});

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
  /// 5. Generate & upload thumbnail (no extra progress shift, it finishes near 70%).
  /// 6. Save comic in Firestore (initial).
  /// 7. (Predictions) Fetch panel data for each page (cover 70%..85%).
  /// 8. (Summaries) Summarize each page (cover 85%..100%).
  ///
  /// If cancelled or on error, attempts cleanup.
  ///
  /// The same [progressStream] is used for all phases. We simply
  /// scale the fraction so the bar stays between 0 and 1 overall.
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
    final rootPath = 'comic_store';
    final userRootPath = '$rootPath/$userId';
    final comicRootPath = '$userRootPath/comics/$comicId';
    final thumbnailPath = '$userRootPath/thumbnails/$comicId.jpg';

    debugPrint('Importing comic: $comicId for user: $userId');

    bool isCancelled = false;
    cancelFuture.then((_) => isCancelled = true);

    void checkCancellation() {
      if (isCancelled) {
        throw Exception('Import cancelled');
      }
    }

    try {
      // 1) Decompress archive
      List<zip.ArchiveFile> imageFiles;

      if (path.extension(fileName).toLowerCase() == '.cbr') {
        // RAR support via 'rar' package (requires file I/O)
        final tempDir = await Directory.systemTemp.createTemp(
          'comic_reader_rar_',
        );
        try {
          final tempRarFile = File(path.join(tempDir.path, 'temp.cbr'));
          await tempRarFile.writeAsBytes(comicBytes);

          final extractDir = Directory(path.join(tempDir.path, 'extracted'));
          await extractDir.create();

          // Extract using Rar class static method
          final result = await Rar.extractRarFile(
            rarFilePath: tempRarFile.path,
            destinationPath: extractDir.path,
          );

          if (result['success'] != true) {
            throw Exception('RAR extraction failed: ${result['message']}');
          }

          // Read extracted files into ArchiveFiles
          imageFiles = [];
          if (await extractDir.exists()) {
            await for (final entity in extractDir.list(recursive: true)) {
              if (entity is File) {
                // Filter out directories if list returns them, but check isFile
                // Also check standard ignore list
                final filename = path.basename(entity.path);
                if (_shouldSkipFile(filename.toLowerCase()) ||
                    !_isAllowedExtension(filename.toLowerCase())) {
                  continue;
                }

                final bytes = await entity.readAsBytes();
                final relativePath = path.relative(
                  entity.path,
                  from: extractDir.path,
                );
                // Create ArchiveFile. mode/compress defaults are fine.
                final archiveFile = zip.ArchiveFile(
                  relativePath,
                  bytes.length,
                  bytes,
                );
                imageFiles.add(archiveFile);
              }
            }
          }
        } finally {
          // Cleanup
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }

        // Sort
        imageFiles.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      } else {
        // Default to Zip (CBZ)
        final archive = zip.ZipDecoder().decodeBytes(comicBytes);
        imageFiles = _extractImagesFromArchive(archive);
      }

      checkCancellation();

      // 2) Extract relevant image files (already filtered above)
      // Check count
      if (imageFiles.isEmpty) {
        throw Exception('No valid image files found in the provided archive.');
      }

      // Phase 1: Upload & Analyze images => 0% .. 100%
      final totalFiles = imageFiles.length;
      final pageUrls = <String>[];
      final List<Map<String, String>> pageSummaries = List.generate(
        totalFiles,
        (_) => {},
        growable: false,
      );
      final List<Map<String, dynamic>> panelSummaries = List.generate(
        totalFiles,
        (_) => {'panels': <Map<String, String>>[]},
        growable: false,
      );
      final comicPredictions = ComicPredictions(pagePredictions: []);

      for (int i = 0; i < totalFiles; i++) {
        checkCancellation();
        final file = imageFiles[i];
        final filename = path.basename(file.name);
        final innerFilePath = '$comicRootPath/$filename';
        debugPrint('Processing page ${i + 1}/$totalFiles: $filename');

        final imageBytes = Uint8List.fromList(file.content as List<int>);
        final base64Image = base64Encode(imageBytes);

        // 1. Upload
        final ref = _storage.ref(innerFilePath);
        await ref.putData(imageBytes);
        final downloadUrl = await ref.getDownloadURL();
        pageUrls.add(downloadUrl);

        // 2. Analyze
        try {
          final analysis = await _analyzePage(base64Image);

          // Save Page Summaries
          pageSummaries[i] = analysis['summaries'] as Map<String, String>;

          // Save Panels & Panel Summaries
          if (analysis.containsKey('panels')) {
            final panelsList = analysis['panels'] as List<Panel>;
            final predictions = Predictions(panels: panelsList);
            comicPredictions.pagePredictions.add(predictions);

            // Extract Panel Summaries
            final List<Map<String, String>> panelSummaryMaps =
                analysis['panel_summaries'] as List<Map<String, String>>;
            panelSummaries[i] = {'panels': panelSummaryMaps};
          } else {
            comicPredictions.pagePredictions.add(Predictions(panels: []));
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
        predictions: comicPredictions,
        pageSummaries: pageSummaries,
        panelSummaries: panelSummaries,
      );

      await _repository.addComic(userId, comic);
      debugPrint('Comic saved to Firestore: $comicId');

      return comicId;
    } catch (e) {
      // Cleanup partial uploads on error or cancellation
      if (isCancelled) {
        await _cleanupIfCancelled(user.uid, comicId);
      } else {
        await _cleanupIfCancelled(user.uid, comicId);
      }
      rethrow;
    } finally {
      await progressStream.close();
    }
  }

  /// Extract images from the CBZ archive while ignoring known irrelevant files.
  List<zip.ArchiveFile> _extractImagesFromArchive(zip.Archive archive) {
    return _extractImagesFromArchiveList(archive.files);
  }

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

    final resizedThumbnail = img.copyResize(originalImage, width: 200);
    final thumbnailBytes = Uint8List.fromList(
      img.encodeJpg(resizedThumbnail, quality: 85),
    );

    if (isCancelled()) {
      throw Exception('Import cancelled');
    }

    final thumbnailRef = _storage.ref(thumbnailPath);
    await thumbnailRef.putData(thumbnailBytes);
    debugPrint('Thumbnail uploaded: $thumbnailPath');
  }

  /// Analyzes a comic page using Gemini.
  /// Returns a `Map<String, dynamic>` with:
  /// - 'summaries': `Map<String, String>` (en, es, fr)
  /// - 'panels': `List<Panel>`
  /// - 'panel_summaries': `List<Map<String, String>>`
  Future<Map<String, dynamic>> _analyzePage(String base64Image) async {
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
      '\n'
      'IMPORTANT: You MUST return a valid JSON object strictly following this schema: \n'
      '$schemaJson \n'
      '\n'
      'If no text or content is present, return empty strings for the summaries.',
    );

    final model = FirebaseAI.googleAI().generativeModel(
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
          InlineDataPart('image/jpeg', base64Decode(base64Image)),
          TextPart('Analyze this comic page.'),
        ]),
      ]);

      final contentText = response.text;
      if (contentText == null) {
        return {
          'summaries': {'en': '', 'es': '', 'fr': ''},
        };
      }

      final parsed = jsonDecode(contentText) as Map<String, dynamic>;
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
      }
      return result;
    } catch (e) {
      debugPrint('Gemini Error: $e');
      rethrow;
    }
  }

  /// Deletes partial upload if import is cancelled or error.
  Future<void> _cleanupIfCancelled(String userId, String comicId) async {
    debugPrint('Cleaning up partial upload: $userId, $comicId');
    await _repository.cleanupPartialUpload(userId, comicId);
  }
}
