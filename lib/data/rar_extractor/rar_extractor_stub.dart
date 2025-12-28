import 'dart:typed_data';

import 'package:archive/archive.dart' as zip;

import 'rar_extractor_interface.dart';

class RarExtractorImpl implements RarExtractor {
  @override
  Future<List<zip.ArchiveFile>> extractImages(Uint8List rarBytes) {
    throw UnsupportedError(
      'Cannot create a RarExtractor without dart:html or dart:io',
    );
  }
}
