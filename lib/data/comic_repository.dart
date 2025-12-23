import 'dart:async';

import '../models/comic.dart';

abstract class ComicRepository {
  Future<List<Comic>> getAllComics(String userId);
  Future<Comic> getComicById(String userId, String comicId);
  Future<void> addComic(String userId, Comic comic);
  Future<void> updateComic(String userId, Comic comic);
  Future<void> deleteComic(String userId, String comicId);
  Future<void> updateCurrentPage(
      String userId, String comicId, int currentPage);
}
