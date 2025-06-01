import 'package:flutter/material.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  
  bool _isLoading = false;
  bool _codeSent = false;
  String? _userEmail;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendMagicCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _errorMessage = 'Please enter a valid email address';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = InstantProvider.of(context);
      await db.auth.sendMagicCode(email);
      
      setState(() {
        _codeSent = true;
        _userEmail = email;
        _isLoading = false;
      });
      
      // Focus on code input
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).requestFocus();
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter the verification code';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = InstantProvider.of(context);
      await db.auth.verifyMagicCode(
        email: _userEmail!,
        code: code,
      );
      
      // Clear the form
      _emailController.clear();
      _codeController.clear();
      
      setState(() {
        _isLoading = false;
        _codeSent = false;
        _userEmail = null;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully signed in!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _codeSent = false;
      _userEmail = null;
      _errorMessage = null;
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = InstantProvider.of(context);
    
    return StreamBuilder<AuthUser?>(
      stream: db.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final user = snapshot.data;
        
        if (user != null) {
          // User is signed in
          return _buildSignedInView(user);
        }
        
        // User is not signed in
        if (_codeSent) {
          return _buildCodeVerificationView();
        }
        
        return _buildEmailInputView();
      },
    );
  }

  Widget _buildEmailInputView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.mail_outline,
                size: 64,
                color: Colors.indigo,
              ),
              const SizedBox(height: 24),
              Text(
                'Sign in with Magic Code',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your email to receive a verification code',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_isLoading,
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: 'you@example.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: const OutlineInputBorder(),
                  errorText: _errorMessage,
                ),
                onSubmitted: (_) => _sendMagicCode(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isLoading ? null : _sendMagicCode,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Send Code'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeVerificationView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 64,
                color: Colors.indigo,
              ),
              const SizedBox(height: 24),
              Text(
                'Enter Verification Code',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a code to $_userEmail',
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                enabled: !_isLoading,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: InputDecoration(
                  labelText: 'Verification Code',
                  hintText: '123456',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  errorText: _errorMessage,
                ),
                onSubmitted: (_) => _verifyCode(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isLoading ? null : _verifyCode,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Verify Code'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isLoading ? null : _reset,
                child: const Text('Use different email'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignedInView(AuthUser user) {
    final db = InstantProvider.of(context);
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.indigo,
                child: Text(
                  user.email.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 36,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Signed in as',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                user.email,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('User ID', user.id),
                      const Divider(),
                      _buildInfoRow('Email', user.email),
                      if (user.refreshToken != null) ...[
                        const Divider(),
                        _buildInfoRow(
                          'Token',
                          '${user.refreshToken!.substring(0, 20)}...',
                          isMonospace: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () async {
                  await db.auth.signOut();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Signed out successfully'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isMonospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: isMonospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}