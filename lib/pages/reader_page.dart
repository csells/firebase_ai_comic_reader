import 'package:flutter/material.dart';

import '../data/comic_repository_firebase.dart';
import '../models/comic.dart';
import '../views/reader_view.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({required this.comicId, required this.userId, super.key});
  final String comicId;
  final String userId;

  @override
  State<ReaderPage> createState() => ReaderPageState();
}

class ReaderPageState extends State<ReaderPage> {
  final ComicRepositoryFirebase _repository = ComicRepositoryFirebase();
  late Future<Comic> _comicFuture;

  @override
  void initState() {
    super.initState();
    _comicFuture = _repository.getComicById(widget.userId, widget.comicId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Comic>(
    future: _comicFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      } else if (snapshot.hasError) {
        return Scaffold(body: Center(child: Text('Error: ${snapshot.error}')));
      } else if (snapshot.hasData) {
        return ReaderView(comic: snapshot.data!, userId: widget.userId);
      } else {
        return const Scaffold(
          body: Center(child: Text('No comic data available')),
        );
      }
    },
  );
}
