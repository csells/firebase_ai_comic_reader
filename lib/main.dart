import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'pages/library_page.dart';
import 'pages/login_page.dart';
import 'pages/reader_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseOptions = DefaultFirebaseOptions.currentPlatform;
  await Firebase.initializeApp(options: firebaseOptions);

  runApp(const App());
}

/// A listenable that triggers whenever the Firebase Auth state changes.
class AuthRefreshListenable extends ChangeNotifier {
  AuthRefreshListenable() {
    FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }
}

final GoRouter _router = GoRouter(
  refreshListenable: AuthRefreshListenable(),
  routes: [
    GoRoute(
      name: 'sign-in',
      path: '/sign-in',
      builder: (context, state) => const LoginPage(),
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

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: _router,
    debugShowCheckedModeBanner: false,
  );
}
