import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as zip;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:rar/rar.dart';

import 'rar_extractor_interface.dart';

class RarExtractorImpl implements RarExtractor {
  @override
  Future<List<zip.ArchiveFile>> extractImages(Uint8List rarBytes) async {
    final imageFiles = <zip.ArchiveFile>[];
    final tempDir = await Directory.systemTemp.createTemp('comic_reader_rar_');
    try {
      final tempRarFile = File(path.join(tempDir.path, 'temp.cbr'));
      await tempRarFile.writeAsBytes(rarBytes);

      final extractDir = Directory(path.join(tempDir.path, 'extracted'));
      await extractDir.create();

      final result = await Rar.extractRarFile(
        rarFilePath: tempRarFile.path,
        destinationPath: extractDir.path,
      );

      if (result['success'] != true) {
        throw Exception('RAR extraction failed: ${result['message']}');
      }

      if (await extractDir.exists()) {
        await for (final entity in extractDir.list(recursive: true)) {
          if (entity is File) {
            final filename = path.basename(entity.path);
            final extension = path.extension(filename).toLowerCase();
            if (['.jpg', '.jpeg', '.png'].contains(extension)) {
              final bytes = await entity.readAsBytes();
              final relativePath = path.relative(
                entity.path,
                from: extractDir.path,
              );
              imageFiles.add(
                zip.ArchiveFile(relativePath, bytes.length, bytes),
              );
            }
          }
        }
      }
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
    return imageFiles;
  }
}
