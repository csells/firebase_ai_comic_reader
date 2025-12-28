import 'dart:typed_data';

import 'package:archive/archive.dart' as zip;

import 'rar_extractor_stub.dart'
    if (dart.library.html) 'rar_extractor_web.dart'
    if (dart.library.io) 'rar_extractor_native.dart';

/// Abstract interface for RAR extraction, with platform-specific
/// implementations.
abstract class RarExtractor {
  Future<List<zip.ArchiveFile>> extractImages(Uint8List rarBytes);
}

RarExtractor getRarExtractor() => RarExtractorImpl();
