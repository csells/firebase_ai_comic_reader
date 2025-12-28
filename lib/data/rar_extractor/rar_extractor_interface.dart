import 'dart:typed_data';

import 'package:archive/archive.dart' as zip;

abstract class RarExtractor {
  Future<List<zip.ArchiveFile>> extractImages(Uint8List rarBytes);
}
