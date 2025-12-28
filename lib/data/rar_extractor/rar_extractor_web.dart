import 'package:archive/archive.dart' as zip;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:rar/rar.dart';

import 'rar_extractor_interface.dart';

class RarExtractorImpl implements RarExtractor {
  @override
  Future<List<zip.ArchiveFile>> extractImages(Uint8List rarBytes) async {
    debugPrint('Using RarWeb virtual filesystem for extraction.');
    final imageFiles = <zip.ArchiveFile>[];
    try {
      const inputPath = '/input.cbr';
      const extractPath = '/extracted/';

      // 1. Store bytes in virtual FS
      RarWeb.storeFileData(inputPath, rarBytes);

      // 2. Extract in virtual FS
      final result = await Rar.extractRarFile(
        rarFilePath: inputPath,
        destinationPath: extractPath,
      );
      debugPrint('RarWeb extraction result: $result');

      if (result['success'] != true) {
        throw Exception('RAR extraction failed (Web): ${result['message']}');
      }

      // 3. List and read extracted files
      final virtualFiles = RarWeb.listVirtualFiles();
      for (final virtualPath in virtualFiles) {
        if (virtualPath.startsWith(extractPath)) {
          final filename = path.basename(virtualPath);
          final extension = path.extension(filename).toLowerCase();

          // Simple filter (should ideally match ComicImporter's filters)
          if (['.jpg', '.jpeg', '.png'].contains(extension)) {
            final bytes = RarWeb.getFileData(virtualPath);
            if (bytes != null) {
              final relativePath = path.relative(
                virtualPath,
                from: extractPath,
              );
              imageFiles.add(
                zip.ArchiveFile(relativePath, bytes.length, bytes),
              );
            }
          }
        }
      }
    } finally {
      RarWeb.clearFileSystem();
    }
    return imageFiles;
  }
}
