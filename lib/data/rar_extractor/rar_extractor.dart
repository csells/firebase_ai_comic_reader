import 'rar_extractor_interface.dart';
import 'rar_extractor_stub.dart'
    if (dart.library.html) 'rar_extractor_web.dart'
    if (dart.library.io) 'rar_extractor_native.dart';

RarExtractor getRarExtractor() => RarExtractorImpl();
