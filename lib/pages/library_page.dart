// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:comic_reader/data/comic_importer.dart';
import 'package:comic_reader/data/comic_repository_firebase.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_storage/firebase_storage.dart' as fs;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;
  final ComicRepositoryFirebase _repository = ComicRepositoryFirebase();
  List<String> _comicThumbnailUrls = [];
  List<String> _comicIds = [];

  @override
  void initState() {
    super.initState();
    _loadComicThumbnails();
  }

  /// Loads thumbnail URLs (and comic IDs) for all comics.
  /// If the user isn't signed in, navigates them to the sign-in page.
  Future<void> _loadComicThumbnails() async {
    final storage = fs.FirebaseStorage.instance;
    final user = _auth.currentUser;

    if (user == null) {
      debugPrint('ComicReader: User not logged in. Redirecting to sign-in.');
      if (context.mounted) {
        context.goNamed('sign-in');
      }
      return;
    }

    final userId = user.uid;
    final thumbnailsRef = storage.ref().child('comic_store/$userId/thumbnails');

    try {
      final result = await thumbnailsRef.listAll();
      final thumbnailUrls = await Future.wait(
        result.items.map((ref) => ref.getDownloadURL()),
      );

      // Derive the comic ID from each thumbnail's file name
      final comicIds = result.items.map((ref) {
        final baseName = path.basenameWithoutExtension(ref.name);
        return baseName; // Use the .jpg-less baseName as the comicId
      }).toList();

      setState(() {
        _comicThumbnailUrls = thumbnailUrls;
        _comicIds = comicIds;
      });
    } catch (e) {
      debugPrint('ComicReader: Error loading thumbnails: $e');
      if (mounted) {
        _showErrorDialog(context, 'Failed to load comic thumbnails: $e');
      }
    }
  }

  /// Displays a progress dialog while importing a new comic.
  void _showProgressDialog(
    BuildContext context,
    Stream<double> progressStream,
    VoidCallback onCancel,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StreamBuilder<double>(
          stream: progressStream,
          builder: (context, snapshot) {
            final progress = snapshot.data ?? 0.0;
            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(value: progress),
                  const SizedBox(height: 20),
                  Text(
                    'Importing comic... ${(progress * 100).toStringAsFixed(0)}%',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onCancel();
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('An error occurred'),
          content: SingleChildScrollView(
            child: SelectableText(
              message,
              style: const TextStyle(fontFamily: 'Courier'),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Lets the user pick a .cbz file, then imports it to Firebase.
  Future<void> _pickAndImportComic() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cbz', 'cbr'],
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      final comicBytes = result.files.single.bytes!;
      final fileName = result.files.single.name;
      final comicImporter = ComicImporter();

      final progressStream = StreamController<double>();
      final cancelCompleter = Completer<void>();
      bool dialogShown = false;

      try {
        final user = _auth.currentUser;
        if (user == null) {
          debugPrint('ComicReader: User not logged in. Cannot import comic.');
          return;
        }

        if (context.mounted) {
          _showProgressDialog(context, progressStream.stream, () {
            cancelCompleter.complete();
          });
          dialogShown = true;
        }

        // Actually import the comic
        final comicPath = await comicImporter.importComic(
          comicBytes,
          fileName,
          progressStream,
          cancelCompleter.future,
        );
        debugPrint('ComicReader: Comic imported to: $comicPath');

        // Close progress dialog on success
        if (mounted && dialogShown) {
          Navigator.of(context).pop();
          dialogShown = false;
        }

        // Reload the library display
        await _loadComicThumbnails();
      } catch (e) {
        debugPrint('ComicReader: Error importing comic: $e');

        // Close progress dialog before showing error dialog
        if (mounted && dialogShown) {
          Navigator.of(context).pop();
          dialogShown = false;
        }

        if (mounted) {
          _showErrorDialog(context, 'Error importing comic: $e');
        }
      } finally {
        // Ensure stream is closed if it wasn't already
        if (!progressStream.isClosed) {
          progressStream.close();
        }
      }
    } else {
      // Cases where file picking fails or yields no bytes
      if (result != null && result.files.single.path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a valid CBZ or CBR file.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Deletes a single comic (Firestore + Storage), then refreshes the library UI.
  Future<void> _deleteComic(String comicId) async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('ComicReader: User not logged in. Cannot delete comic.');
      return;
    }

    final userId = user.uid;

    try {
      // Delete from Firestore & Storage
      await _repository.deleteComic(userId, comicId);

      // Refresh
      await _loadComicThumbnails();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comic deleted successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('ComicReader: Error deleting comic: $e');
      if (mounted) {
        _showErrorDialog(context, 'Error deleting comic: $e');
      }
    }
  }

  /// Shows a confirmation dialog before deleting the comic.
  void _showDeleteConfirmationDialog(String comicId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Comic'),
          content: const Text('Are you sure you want to delete this comic?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteComic(comicId);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  /// Main UI layout: grid of thumbnail images, plus an import (+) button.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comic Library'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await _auth.signOut();
              if (context.mounted) {
                context.goNamed('sign-in');
              }
            },
          ),
        ],
      ),
      body: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 2 / 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        padding: const EdgeInsets.all(10),
        itemCount: _comicThumbnailUrls.length,
        itemBuilder: (context, index) {
          final url = _comicThumbnailUrls[index];
          final comicId = _comicIds[index];

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    // Navigate to Reader
                    if (context.mounted) {
                      context.goNamed(
                        'reader',
                        pathParameters: {'comicId': comicId},
                      );
                    }
                  },
                  onLongPress: () {
                    // Keep long-press as an alternative
                    _showDeleteConfirmationDialog(comicId);
                  },
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) =>
                          const Center(child: Icon(Icons.error)),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.delete,
                      color: Colors.white,
                      size: 18,
                    ),
                    tooltip: 'Delete Comic',
                    onPressed: () {
                      _showDeleteConfirmationDialog(comicId);
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndImportComic,
        child: const Icon(Icons.add),
      ),
    );
  }
}
