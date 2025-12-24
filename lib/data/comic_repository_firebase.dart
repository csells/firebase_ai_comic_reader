import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/comic.dart';
import 'comic_repository.dart';

class ComicRepositoryFirebase implements ComicRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  Future<List<Comic>> getAllComics(String userId) async {
    // Firebase Auth access:
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('comics')
        .get();
    return snapshot.docs.map((doc) => Comic.fromMap(doc.data())).toList();
  }

  @override
  Future<Comic> getComicById(String userId, String comicId) async {
    // Firebase Auth access:
    final doc = await _firestore
        .collection('users')
        .doc(userId)
        .collection('comics')
        .doc(comicId)
        .get();
    if (doc.exists) {
      return Comic.fromMap(doc.data()!);
    }
    throw Exception('Comic not found');
  }

  @override
  Future<void> addComic(String userId, Comic comic) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('comics')
        .doc(comic.id)
        .set(comic.toMap());
  }

  @override
  Future<void> updateComic(String userId, Comic comic) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('comics')
        .doc(comic.id)
        .update(comic.toMap());
  }

  @override
  Future<void> deleteComic(String userId, String comicId) async {
    try {
      // Delete comic document from Firestore
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('comics')
          .doc(comicId)
          .delete();
    } catch (e) {
      debugPrint('ComicReader: Firestore: Error deleting comic: $e');
      rethrow;
    }
    try {
      // Delete comic files from Firebase Storage
      final comicRef = _storage.ref('comic_store/$userId/comics/$comicId');
      final comicFiles = await comicRef.listAll();

      // Delete all files in the comic folder
      await Future.wait(comicFiles.items.map((item) => item.delete()));
    } catch (e) {
      debugPrint(
        'ComicReader: Firebase Storage: Error deleting comic files: $e',
      );
      rethrow;
    }
    try {
      // Delete thumbnail from Firebase Storage
      await _storage
          .ref('comic_store/$userId/thumbnails/$comicId.jpg')
          .delete();
    } catch (e) {
      debugPrint('ComicReader: Firebase Storage: Error deleting thumbnail: $e');
      rethrow;
    }
  }

  Future<void> cleanupPartialUpload(String userId, String comicId) async {
    await deleteComic(userId, comicId);
  }

  @override
  Future<void> updateCurrentPage(
    String userId,
    String comicId,
    int currentPage,
  ) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('comics')
        .doc(comicId)
        .update({
          'currentPage': currentPage,
          'lastReadDate': DateTime.now().toIso8601String(),
        });
  }
}
