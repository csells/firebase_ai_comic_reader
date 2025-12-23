// Testing auth stuff for ML: TEMPORARY FIXES to get demo done

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

Future<String?> getGoogleAccessToken() async {
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser == null) return null;

  final GoogleSignIn googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  );

  GoogleSignInAccount? googleUser = await googleSignIn.signInSilently();

  // If silent sign-in fails, try interactive sign-in
  if (googleUser == null) {
    try {
      googleUser = await googleSignIn.signIn();
    } catch (e) {
      // Handle sign-in errors (e.g., user cancellation)
      debugPrint('Google Sign-In Error: $e');
      return null;
    }
  }

  // Check again if we have a user after potentially interactive sign-in
  if (googleUser == null) return null;

  final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
  return googleAuth.accessToken;
}

void getAndPrintToken() async {
  String? accessToken = await getGoogleAccessToken();

  if (accessToken != null) {
    debugPrint('Google Access Token: $accessToken');
    // Use the access token, e.g., for API calls
  } else {
    debugPrint('Failed to get Google Access Token');
    // Handle the case where the token retrieval failed
  }
}

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
