// 241223: TODO:
// 1. Improve LLM prompt to handle situations where there is no text in the image.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' as zip;
import 'package:comic_reader/data/comic_repository_firebase.dart';
import 'package:comic_reader/gemini_api_key.dart' as gemini_api_key;
import 'package:comic_reader/models/comic.dart';
import 'package:comic_reader/models/comic_predictions.dart';
import 'package:comic_reader/models/predictions.dart';
import 'package:comic_reader/utils/auth_utils.dart'; // getGoogleAccessToken
import 'package:comic_reader/utils/prediction_utils.dart' as pred_utils;
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_storage/firebase_storage.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
    'system volume information'
  ];

  static const List<String> _ignoredFiles = [
    'thumbs.db',
    'desktop.ini',
    '.ds_store'
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
        final tempDir =
            await Directory.systemTemp.createTemp('comic_reader_rar_');
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
                final relativePath =
                    path.relative(entity.path, from: extractDir.path);
                // Create ArchiveFile. mode/compress defaults are fine.
                final archiveFile =
                    zip.ArchiveFile(relativePath, bytes.length, bytes);
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

      // Phase 1: Upload images => 0% .. 70%
      final pageUrls = await _uploadFilesScaled(
        imageFiles: imageFiles,
        comicRootPath: comicRootPath,
        progressStream: progressStream,
        startFrac: 0.0,
        endFrac: 0.70,
        isCancelled: () => isCancelled,
      );
      checkCancellation();

      // Generate & upload thumbnail
      await _createThumbnail(
        imageFiles.first,
        thumbnailPath,
        isCancelled: () => isCancelled,
      );
      checkCancellation();

      // Save comic to Firestore
      await _saveComic(
        userId: userId,
        comicId: comicId,
        thumbnailUrl: '$userRootPath/thumbnails/$comicId.jpg',
        pageUrls: pageUrls,
      );

      // Phase 2: Predictions => 70% .. 85%
      var comic = await _repository.getComicById(userId, comicId);
      if (enablePredictions) {
        try {
          final accessToken = await getGoogleAccessToken();
          if (accessToken != null) {
            final totalPages = comic.pageImages.length;
            for (int i = 0; i < totalPages; i++) {
              checkCancellation();
              final imageUrl = comic.pageImages[i];
              try {
                final predictionsJson = await pred_utils.getPanelsREST(
                  accessToken: accessToken,
                  imageUrl: imageUrl,
                  confidenceThreshold: 0.3,
                  maxPredictions: 16,
                );
                final predictions = Predictions.fromJson(predictionsJson);
                comic.predictions ??= ComicPredictions(pagePredictions: []);
                comic.predictions!.pagePredictions.add(predictions);
              } catch (e) {
                debugPrint('Error fetching predictions for page $i: $e');
                rethrow;
              }

              final subFraction = (i + 1) / totalPages;
              final scaled = 0.70 + (0.85 - 0.70) * subFraction;
              progressStream.add(scaled);

              // Save progress
              await _repository.updateComic(userId, comic);
            }
          }
        } catch (authError) {
          debugPrint('Predictions failed due to auth issue: $authError');
          rethrow;
        }
      }
      checkCancellation();

      // Phase 3: Summaries => 85% .. 100%
      comic = await _repository.getComicById(userId, comicId);
      final totalSummaryPages = comic.pageImages.length;

      // Initialize structures if not already there
      comic.pageSummaries ??=
          List.generate(totalSummaryPages, (_) => {}, growable: false);
      comic.panelSummaries ??= List.generate(
          totalSummaryPages, (_) => {'panels': <Map<String, String>>[]},
          growable: false);

      for (int i = 0; i < totalSummaryPages; i++) {
        checkCancellation();

        // Skip if already summarized (partial resume)
        if (comic.pageSummaries![i].isNotEmpty) continue;

        final imageUrl = comic.pageImages[i];

        try {
          // Download image once for both page and panel summaries
          final response = await http.get(Uri.parse(imageUrl));
          if (response.statusCode == 200) {
            final imageBytes = response.bodyBytes;
            final base64Image = base64Encode(imageBytes);

            // 1. Page Summary
            final pageSummaryMap = await _generateSummary(base64Image, 'page');
            comic.pageSummaries![i] = pageSummaryMap;

            // 2. Panel Summaries
            // Check if we have panels for this page
            if (comic.predictions != null &&
                i < comic.predictions!.pagePredictions.length) {
              final pagePreds = comic.predictions!.pagePredictions[i];
              final panels = pagePreds.panels;

              if (panels.isNotEmpty) {
                final decodedImage = img.decodeImage(imageBytes);
                if (decodedImage != null) {
                  final List<Map<String, String>> panelMaps = [];

                  for (final panel in panels) {
                    // Crop panel
                    final x =
                        (panel.normalizedBox.left * decodedImage.width).round();
                    final y =
                        (panel.normalizedBox.top * decodedImage.height).round();
                    final w = (panel.normalizedBox.width * decodedImage.width)
                        .round();
                    final h = (panel.normalizedBox.height * decodedImage.height)
                        .round();

                    // Boundary checks
                    final safeX = x.clamp(0, decodedImage.width - 1);
                    final safeY = y.clamp(0, decodedImage.height - 1);
                    final safeW = (w + safeX > decodedImage.width)
                        ? decodedImage.width - safeX
                        : w;
                    final safeH = (h + safeY > decodedImage.height)
                        ? decodedImage.height - safeY
                        : h;

                    if (safeW > 0 && safeH > 0) {
                      final crop = img.copyCrop(decodedImage,
                          x: safeX, y: safeY, width: safeW, height: safeH);
                      final cropBytes = img.encodeJpg(crop);
                      final base64Crop = base64Encode(cropBytes);

                      final panelSummaryMap =
                          await _generateSummary(base64Crop, 'panel');
                      panelMaps.add(panelSummaryMap);
                    } else {
                      panelMaps.add({});
                    }
                  }
                  comic.panelSummaries![i] = {'panels': panelMaps};
                }
              }
            }
          }

          // Save progress after each page's summary
          await _repository.updateComic(userId, comic);
        } catch (e) {
          debugPrint('Error summarizing page $i: $e');
          rethrow;
        }

        final subFraction = (i + 1) / totalSummaryPages;
        final scaled = 0.85 + (1.0 - 0.85) * subFraction;
        progressStream.add(scaled);
      }
      // Final update at the end
      await _repository.updateComic(userId, comic);

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
      List<zip.ArchiveFile> files) {
    final imageFiles = files
        .where((file) =>
            file.isFile &&
            !_shouldSkipFile(file.name.toLowerCase()) &&
            _isAllowedExtension(file.name.toLowerCase()))
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

  /// Uploads image files to Firebase Storage and returns their download URLs.
  ///
  /// [startFrac] and [endFrac] define how to scale the fraction
  /// of this upload sub-task into the overall 0..1 range.
  Future<List<String>> _uploadFilesScaled({
    required List<zip.ArchiveFile> imageFiles,
    required String comicRootPath,
    required StreamController<double> progressStream,
    required double startFrac,
    required double endFrac,
    required bool Function() isCancelled,
  }) async {
    final pageUrls = <String>[];
    final totalFiles = imageFiles.length;
    if (totalFiles == 0) {
      return pageUrls;
    }

    for (int i = 0; i < totalFiles; i++) {
      if (isCancelled()) {
        throw Exception('Import cancelled');
      }
      final file = imageFiles[i];
      final filename = path.basename(file.name);
      final innerFilePath = '$comicRootPath/$filename';
      debugPrint('Uploading: $innerFilePath');

      final data = Uint8List.fromList(file.content as List<int>);
      final ref = _storage.ref(innerFilePath);

      await ref.putData(data);
      final downloadUrl = await ref.getDownloadURL();
      pageUrls.add(downloadUrl);

      // partial progress for this sub-task from startFrac..endFrac
      final subFraction = (i + 1) / totalFiles; // 0..1
      final scaled = startFrac + (endFrac - startFrac) * subFraction;
      progressStream.add(scaled);
    }

    return pageUrls;
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
    final originalImageData =
        Uint8List.fromList(firstImageFile.content as List<int>);
    final originalImage = img.decodeImage(originalImageData);
    if (originalImage == null) {
      throw Exception('Failed to decode first image for thumbnail.');
    }

    final resizedThumbnail = img.copyResize(originalImage, width: 200);
    final thumbnailBytes =
        Uint8List.fromList(img.encodeJpg(resizedThumbnail, quality: 85));

    if (isCancelled()) {
      throw Exception('Import cancelled');
    }

    final thumbnailRef = _storage.ref(thumbnailPath);
    await thumbnailRef.putData(thumbnailBytes);
    debugPrint('Thumbnail uploaded: $thumbnailPath');
  }

  /// Saves a newly imported Comic record to Firestore.
  Future<void> _saveComic({
    required String userId,
    required String comicId,
    required String thumbnailUrl,
    required List<String> pageUrls,
  }) async {
    final comic = Comic(
      id: comicId,
      title: comicId,
      thumbnailImage: thumbnailUrl,
      pageCount: pageUrls.length,
      pageImages: pageUrls,
    );

    await _repository.addComic(userId, comic);
    debugPrint('Comic saved to Firestore: $comicId');
  }

  /// Generates a summary for a given image (page or panel) in multiple languages.
  /// Returns a `Map<String, String>` with keys 'en', 'es', 'fr'.
  Future<Map<String, String>> _generateSummary(
      String base64Image, String contextType) async {
    // Prompt adapted for context
    final promptContext = contextType == 'panel'
        ? 'panel of a comic book'
        : 'page of a comic book';

    final prompt =
        'You are an expert OCR and translation model. Analyze this $promptContext. '
        '1. Extract the text and arrange it narratively. '
        '2. Summarize the story/content in three languages: English (en), Spanish (es), and French (fr). '
        '3. Return ONLY a valid JSON object with keys "en", "es", "fr" and the respective summaries. '
        'If no text/content, return empty strings.';

    // 3) Request body
    final apiKey = gemini_api_key.geminiApiKey;
    if (apiKey.isEmpty) {
      debugPrint('Gemini Error: API Key is missing or empty.');
      return {'en': '', 'es': '', 'fr': ''};
    }

    final requestBody = {
      'contents': [
        {
          'parts': [
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Image,
              }
            },
            {'text': prompt},
          ]
        }
      ],
      'generationConfig': {'responseMimeType': 'application/json'}
    };

    // 4) Call Gemini 1.5-flash
    final endpoint =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey';

    debugPrint('Gemini Summary Request: ${jsonEncode(requestBody)}');
    final llmResponse = await http.post(
      Uri.parse(endpoint),
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json',
      },
      body: jsonEncode(requestBody),
    );
    debugPrint(
        'Gemini Summary Response: ${llmResponse.statusCode} - ${llmResponse.body}');

    if (llmResponse.statusCode == 200) {
      final jsonResponse = jsonDecode(llmResponse.body) as Map<String, dynamic>;
      final candidate = jsonResponse['candidates']?[0];
      final contentText = candidate['content']['parts'][0]['text'];

      if (contentText != null) {
        try {
          final parsed = jsonDecode(contentText);
          if (parsed is Map) {
            return {
              'en': parsed['en']?.toString() ?? '',
              'es': parsed['es']?.toString() ?? '',
              'fr': parsed['fr']?.toString() ?? '',
            };
          }
        } catch (e) {
          debugPrint('Error parsing JSON summary: $e');
          rethrow;
        }
      }
    } else {
      debugPrint(
          'Request failed: ${llmResponse.statusCode} - ${llmResponse.body}');
      throw Exception(
          'Gemini request failed with status ${llmResponse.statusCode}: ${llmResponse.body}');
    }
    return {'en': '', 'es': '', 'fr': ''};
  }

  /// Deletes partial upload if import is cancelled or error.
  Future<void> _cleanupIfCancelled(String userId, String comicId) async {
    debugPrint('Cleaning up partial upload: $userId, $comicId');
    await _repository.cleanupPartialUpload(userId, comicId);
  }
}
