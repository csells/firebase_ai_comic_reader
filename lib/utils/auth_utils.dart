import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Retrieves the Firebase Auth ID token for the current user.
///
/// Throws an [Exception] if no user is signed in or if the token retrieval fails.
Future<String> getFirebaseAuthToken() async {
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('No user signed in');
    }

    final idToken = await currentUser.getIdToken();
    if (idToken == null) {
      throw Exception('Failed to retrieve authentication token');
    }
    return idToken;
  } catch (e) {
    debugPrint('Firebase Auth Token Error: $e');
    rethrow;
  }
}
