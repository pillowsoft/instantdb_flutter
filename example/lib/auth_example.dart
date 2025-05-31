import 'package:flutter/material.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';

/// Example of how to add authentication to an InstantDB app
/// This is optional - InstantDB works fine with anonymous users
class AuthExample extends StatefulWidget {
  const AuthExample({super.key});

  @override
  State<AuthExample> createState() => _AuthExampleState();
}

class _AuthExampleState extends State<AuthExample> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final db = InstantProvider.of(context);
      await db.auth.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      
      // Navigation would happen here
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in successfully!')),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signUp() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final db = InstantProvider.of(context);
      await db.auth.signUp(
        email: _emailController.text,
        password: _passwordController.text,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created successfully!')),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('InstantDB Auth Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Show current user status
            AuthBuilder(
              builder: (context, user) {
                if (user != null) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Icon(Icons.check_circle, 
                            color: Colors.green, 
                            size: 48,
                          ),
                          const SizedBox(height: 8),
                          Text('Signed in as: ${user.email}'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () async {
                              final db = InstantProvider.of(context);
                              await db.auth.signOut();
                            },
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Login form for anonymous users
                return Column(
                  children: [
                    const Text(
                      'Sign in to sync your todos across devices',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      enabled: !_isLoading,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: _isLoading ? null : _signIn,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Sign In'),
                        ),
                        OutlinedButton(
                          onPressed: _isLoading ? null : _signUp,
                          child: const Text('Sign Up'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Note: The app works without signing in!\nAuthentication is optional.',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Example of protected content that requires authentication
class AuthGuardExample extends StatelessWidget {
  const AuthGuardExample({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthGuard(
      child: const Scaffold(
        body: Center(
          child: Text('This content is only visible to authenticated users'),
        ),
      ),
      fallback: const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('Please sign in to view this content'),
            ],
          ),
        ),
      ),
    );
  }
}