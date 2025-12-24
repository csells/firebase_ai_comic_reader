// Testing auth stuff for ML: TEMPORARY FIXES to get demo done

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

Future<String?> getFirebaseAuthToken() async {
  try {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return null;

    final idToken = await currentUser.getIdToken();
    return idToken;
  } catch (e) {
    debugPrint('Firebase Auth Token Error: $e');
    return null;
  }
}
