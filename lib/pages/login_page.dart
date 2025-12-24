import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _auth = FirebaseAuth.instance;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter both email and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // First, try to sign in
      debugPrint('Attempting to sign in user: $email');
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      debugPrint('Sign in successful for: $email');
    } on FirebaseAuthException catch (e) {
      debugPrint('Sign in failed: ${e.code}');
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        // If user not found (or invalid credentials), try to create the account.
        try {
          debugPrint('Attempting to create account for: $email');
          await _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          debugPrint('Account created and signed in for: $email');
        } on FirebaseAuthException catch (createError) {
          debugPrint('Account creation failed: ${createError.code}');
          setState(() => _errorMessage = createError.message);
        }
      } else {
        setState(() => _errorMessage = e.message);
      }
    } catch (e) {
      debugPrint('Unexpected error during login: $e');
      setState(() => _errorMessage = 'An unexpected error occurred: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comic Reader Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.menu_book, size: 80, color: Colors.blue),
                const SizedBox(height: 24),
                const Text(
                  'Welcome to AI Comic Reader',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _handleLogin(),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _handleLogin(),
                  obscureText: true,
                  autocorrect: false,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : const Text('Sign In', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'New users will be registered automatically.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
