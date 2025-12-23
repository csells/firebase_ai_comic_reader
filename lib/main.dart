import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';

import 'firebase_options.dart';
import 'pages/library_page.dart';
import 'pages/reader_page.dart';

// This file has to be manually created. It's excluded from the git
// repository to avoid leaking your client ID.See the README.md for details.
import 'google_client_id.dart' as google_client_id;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseOptions = DefaultFirebaseOptions.currentPlatform;
  await Firebase.initializeApp(options: firebaseOptions);

  FirebaseUIAuth.configureProviders([
    GoogleProvider(
      clientId: google_client_id.googleClientId,
    ),
  ]);

  runApp(const App());
}

final GoRouter _router = GoRouter(
  routes: [
    GoRoute(
      name: 'sign-in',
      path: '/sign-in',
      builder: (context, state) => SignInScreen(
        actions: [
          AuthStateChangeAction<SignedIn>((context, state) {
            context.goNamed('library');
          }),
        ],
      ),
    ),
    GoRoute(
      name: 'library',
      path: '/',
      builder: (context, state) => const LibraryPage(),
      routes: [
        GoRoute(
          name: 'reader',
          path: 'reader/:comicId',
          builder: (context, state) {
            final comicId = state.pathParameters['comicId']!;
            final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
            return ReaderPage(comicId: comicId, userId: userId);
          },
        ),
      ],
    ),
  ],
  redirect: (context, state) {
    final isSignedIn = FirebaseAuth.instance.currentUser != null;
    final isSignInRoute = state.matchedLocation == '/sign-in';

    if (!isSignedIn && !isSignInRoute) {
      return '/sign-in';
    } else if (isSignedIn && isSignInRoute) {
      return '/';
    }

    return null;
  },
);

/// The root widget of the Comic Reader application.
///
/// This widget sets up the MaterialApp with routing configuration and theme settings.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
    );
  }
}
