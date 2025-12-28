import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/comic.dart';

class ComicRepositoryFirebase {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<List<Comic>> getAllComics(String userId) async {
    // Firebase Auth access:
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('comics')
        .get();
    return snapshot.docs.map((doc) => Comic.fromMap(doc.data())).toList();
  }

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

  Future<void> addComic(String userId, Comic comic) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('comics')
          .doc(comic.id)
          .set(comic.toMap());
    } catch (e) {
      debugPrint('Error adding comic (${comic.id}): $e');
      rethrow;
    }
  }

  Future<void> updateComic(String userId, Comic comic) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('comics')
          .doc(comic.id)
          .update(comic.toMap());
    } catch (e) {
      debugPrint('Error updating comic (${comic.id}): $e');
      rethrow;
    }
  }

  Future<void> deleteComic(String userId, String comicId) async {
    try {
      // 1. Delete comic document from Firestore
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('comics')
          .doc(comicId)
          .delete();

      // 2. Delete comic files from Firebase Storage
      final comicRef = _storage.ref('comic_store/$userId/comics/$comicId');
      try {
        final comicFiles = await comicRef.listAll();
        await Future.wait(
          comicFiles.items.map(
            (item) => item.delete().catchError((e) {
              if (e is FirebaseException && e.code == 'object-not-found') {
                return; // Ignore
              }
              throw e;
            }),
          ),
        );
      } catch (e) {
        if (e is FirebaseException && e.code == 'object-not-found') {
          // Parent folder not found is fine
        } else {
          rethrow;
        }
      }

      // 3. Delete thumbnail from Firebase Storage
      try {
        await _storage
            .ref('comic_store/$userId/thumbnails/$comicId.jpg')
            .delete();
      } catch (e) {
        if (e is FirebaseException && e.code == 'object-not-found') {
          // Ignore
        } else {
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('Error deleting comic ($comicId): $e');
      rethrow;
    }
  }

  Future<void> cleanupPartialUpload(String userId, String comicId) async {
    await deleteComic(userId, comicId);
  }

  Future<void> updateCurrentPage(
    String userId,
    String comicId,
    int currentPage,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('comics')
          .doc(comicId)
          .update({
            'currentPage': currentPage,
            'lastReadDate': DateTime.now().toIso8601String(),
          });
    } catch (e) {
      debugPrint('Error updating current page ($comicId): $e');
      rethrow;
    }
  }
}
