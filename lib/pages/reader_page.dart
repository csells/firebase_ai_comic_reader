// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../views/reader_view.dart';
import 'package:comic_reader/models/comic.dart';
import 'package:comic_reader/data/comic_repository_firebase.dart';

import 'package:comic_reader/utils/auth_utils.dart' as auth_utils;
//import 'package:comic_reader/utils/prediction_utils.dart' as prediction_utils;

// TODO: On load, iterate through comic images and send them to the prediction
// API. Also, consider just processing the current page while testing:
class ReaderPage extends StatefulWidget {
  final String comicId;
  final String userId;

  const ReaderPage({super.key, required this.comicId, required this.userId});

  @override
  State<ReaderPage> createState() => ReaderPageState();
}

class ReaderPageState extends State<ReaderPage> {
  final ComicRepositoryFirebase _repository = ComicRepositoryFirebase();
  late Future<Comic> _comicFuture;
  late Future<String?> firebaseAuthToken;

  @override
  void initState() {
    super.initState();
    _comicFuture = _repository.getComicById(widget.userId, widget.comicId);
    _initializeFirebaseToken();
  }

  // TODO: 241224: GET FIREBASE AUTH TOKEN! We do NOT need Google Auth scope
  // here! In fact, it damages the user experience. The Google Auth scope is
  // only for the prediction API while calling the model, which is only done
  // during the comic import process. Therefore, we need to get the Firebase
  // Auth token instead! #VeryImportant #FirebaseAuth #FirebaseToken
  //
  // Create separate async method for token initialization
  Future<void> _initializeFirebaseToken() async {
    firebaseAuthToken = auth_utils.getFirebaseAuthToken();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Comic>(
      future: _comicFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        } else if (snapshot.hasData) {
          return FutureBuilder<String?>(
            future: firebaseAuthToken,
            builder: (context, tokenSnapshot) {
              if (tokenSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              } else if (tokenSnapshot.hasError) {
                return Scaffold(
                  body: Center(child: Text('Error: ${tokenSnapshot.error}')),
                );
              } else {
                debugPrint(
                    'ReaderPage: Firebase Auth Token: ${tokenSnapshot.data}');
                return ReaderView(
                  comic: snapshot.data!,
                  userId: widget.userId,
                  firebaseAuthToken: tokenSnapshot.data,
                );
              }
            },
          );
        } else {
          return const Scaffold(
            body: Center(child: Text('No comic data available')),
          );
        }
      },
    );
  }
}
