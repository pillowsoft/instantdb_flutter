import 'dart:async';
import 'package:dio/dio.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/types.dart';
import '../core/logging_config.dart';

/// Authentication manager for InstantDB
class AuthManager {
  final String appId;
  final String baseUrl;
  final Dio _dio;

  final Signal<AuthUser?> _currentUser = signal(null);
  String? _authToken;

  /// Current authenticated user
  ReadonlySignal<AuthUser?> get currentUser => _currentUser.readonly();

  /// Stream of authentication state changes
  Stream<AuthUser?> get onAuthStateChange => _currentUser.toStream();

  AuthManager({
    required this.appId,
    required this.baseUrl,
  }) : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: {
            'Content-Type': 'application/json',
          },
        ));

  /// Sign in with email and password
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    // Validate email format
    if (!_isValidEmail(email)) {
      throw InstantException(
        message: 'Invalid email format',
        code: 'invalid_email',
      );
    }

    try {
      final response = await _dio.post('/v1/auth/signin', data: {
        'email': email,
        'password': password,
      });

      final data = response.data as Map<String, dynamic>;
      final user = AuthUser.fromJson(data['user']);
      final token = data['token'] as String;

      _authToken = token;
      _currentUser.value = user;

      // Update Dio headers
      _dio.options.headers['Authorization'] = 'Bearer $token';

      return user;
    } on DioException catch (e) {
      throw InstantException(
        message: 'Sign in failed: ${e.response?.data?['message'] ?? e.message}',
        code: 'auth_error',
        originalError: e,
      );
    }
  }

  /// Sign up with email and password
  Future<AuthUser> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    // Validate email format
    if (!_isValidEmail(email)) {
      throw InstantException(
        message: 'Invalid email format',
        code: 'invalid_email',
      );
    }

    // Validate password strength
    if (!_isStrongPassword(password)) {
      throw InstantException(
        message: 'Password is too weak. Must be at least 8 symbols long and contain uppercase, lowercase, numbers, and special symbols',
        code: 'weak_password',
      );
    }

    try {
      final response = await _dio.post('/v1/auth/signup', data: {
        'email': email,
        'password': password,
        if (metadata != null) 'metadata': metadata,
      });

      final data = response.data as Map<String, dynamic>;
      final user = AuthUser.fromJson(data['user']);
      final token = data['token'] as String;

      _authToken = token;
      _currentUser.value = user;

      // Update Dio headers
      _dio.options.headers['Authorization'] = 'Bearer $token';

      return user;
    } on DioException catch (e) {
      throw InstantException(
        message: 'Sign up failed: ${e.response?.data?['message'] ?? e.message}',
        code: 'auth_error',
        originalError: e,
      );
    }
  }

  /// Sign in with a token
  Future<AuthUser> signInWithToken(String token) async {
    try {
      _authToken = token;
      _dio.options.headers['Authorization'] = 'Bearer $token';

      final response = await _dio.get('/v1/auth/me');
      final user = AuthUser.fromJson(response.data as Map<String, dynamic>);

      _currentUser.value = user;
      return user;
    } on DioException catch (e) {
      _authToken = null;
      _dio.options.headers.remove('Authorization');
      
      throw InstantException(
        message: 'Token authentication failed: ${e.response?.data?['message'] ?? e.message}',
        code: 'auth_error',
        originalError: e,
      );
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    _authToken = null;
    _currentUser.value = null;
    _dio.options.headers.remove('Authorization');
  }

  /// Get the current auth token
  String? get authToken => _authToken;

  /// Check if user is authenticated
  bool get isAuthenticated => _currentUser.value != null && _authToken != null;

  /// Refresh the current user
  Future<AuthUser?> refreshUser() async {
    if (_authToken == null) return null;

    try {
      final response = await _dio.get('/v1/auth/me');
      final user = AuthUser.fromJson(response.data as Map<String, dynamic>);
      _currentUser.value = user;
      return user;
    } on DioException catch (e) {
      // Token might be expired, sign out
      await signOut();
      throw InstantException(
        message: 'Failed to refresh user: ${e.response?.data?['message'] ?? e.message}',
        code: 'auth_error',
        originalError: e,
      );
    }
  }

  /// Update user metadata
  Future<AuthUser> updateUser(Map<String, dynamic> metadata) async {
    if (!isAuthenticated) {
      throw InstantException(message: 'User not authenticated', code: 'not_authenticated');
    }

    try {
      final response = await _dio.patch('/v1/auth/me', data: {
        'metadata': metadata,
      });

      final user = AuthUser.fromJson(response.data as Map<String, dynamic>);
      _currentUser.value = user;
      return user;
    } on DioException catch (e) {
      throw InstantException(
        message: 'Failed to update user: ${e.response?.data?['message'] ?? e.message}',
        code: 'auth_error',
        originalError: e,
      );
    }
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    // Validate email format
    if (!_isValidEmail(email)) {
      throw InstantException(
        message: 'Invalid email format',
        code: 'invalid_email',
      );
    }

    try {
      await _dio.post('/v1/auth/reset-password', data: {
        'email': email,
      });
    } on DioException catch (e) {
      throw InstantException(
        message: 'Failed to reset password: ${e.response?.data?['message'] ?? e.message}',
        code: 'auth_error',
        originalError: e,
      );
    }
  }

  /// Send magic link email
  Future<void> sendMagicLink(String email) async {
    // Validate email format
    if (!_isValidEmail(email)) {
      throw InstantException(
        message: 'Invalid email format',
        code: 'invalid_email',
      );
    }

    try {
      await _dio.post('/v1/auth/magic-link', data: {
        'email': email,
        'appId': appId,
      });
    } on DioException catch (e) {
      throw InstantException(
        message: 'Failed to send magic link: ${e.response?.data?['message'] ?? e.message}',
        code: 'auth_error',
        originalError: e,
      );
    }
  }

  /// Send magic code email
  Future<void> sendMagicCode(String email) async {
    InstantDBLogging.auth.debug('AuthManager: sendMagicCode called with email: $email');
    
    // Validate email format
    if (!_isValidEmail(email)) {
      InstantDBLogging.auth.warning('AuthManager: Invalid email format: $email');
      throw InstantException(
        message: 'Invalid email format',
        code: 'invalid_email',
      );
    }

    try {
      // First try the REST endpoint approach
      InstantDBLogging.auth.debug('AuthManager: Sending POST request to ${baseUrl}/runtime/auth/send_magic_code');
      InstantDBLogging.auth.debug('AuthManager: Request data - email: $email, app-id: $appId');
      
      final response = await _dio.post('/runtime/auth/send_magic_code', data: {
        'email': email,
        'app-id': appId,
      });
      
      InstantDBLogging.auth.debug('AuthManager: Magic code request successful - Status: ${response.statusCode}');
      InstantDBLogging.auth.debug('AuthManager: Response data: ${response.data}');
      
    } on DioException catch (e) {
      InstantDBLogging.auth.severe('AuthManager: DioException in sendMagicCode', e);
      InstantDBLogging.auth.severe('AuthManager: Status code: ${e.response?.statusCode}');
      InstantDBLogging.auth.severe('AuthManager: Response data: ${e.response?.data}');
      InstantDBLogging.auth.severe('AuthManager: Request URL: ${e.requestOptions.uri}');
      InstantDBLogging.auth.severe('AuthManager: Request headers: ${e.requestOptions.headers}');
      
      String errorMessage = 'Unknown error';
      String errorCode = 'auth_error';
      
      if (e.response?.data is Map<String, dynamic>) {
        final responseData = e.response?.data as Map<String, dynamic>;
        errorMessage = responseData['message'] ?? responseData['error'] ?? errorMessage;
        
        // Provide more specific error messages based on InstantDB's responses
        if (responseData['hint'] != null) {
          errorMessage += ' (${responseData['hint']})';
        }
        if (responseData['type'] != null) {
          errorCode = responseData['type'].toString();
        }
      } else if (e.response?.data is String) {
        errorMessage = e.response?.data as String;
      } else {
        errorMessage = e.message ?? errorMessage;
      }
      
      // Check for specific error types
      if (e.response?.statusCode == 404) {
        errorCode = 'endpoint_not_found';
        errorMessage = 'Auth endpoint not found. InstantDB might use a different auth method.';
      } else if (e.response?.statusCode == 400) {
        errorCode = 'bad_request';
      } else if (e.response?.statusCode == 401) {
        errorCode = 'unauthorized';
      } else if (e.response?.statusCode == 403) {
        errorCode = 'forbidden';
      }
      
      InstantDBLogging.auth.severe('AuthManager: Final error - code: $errorCode, message: $errorMessage');
      
      throw InstantException(
        message: errorMessage,
        code: errorCode,
        originalError: e,
      );
    } catch (e, stackTrace) {
      InstantDBLogging.auth.severe('AuthManager: Unexpected error in sendMagicCode', e, stackTrace);
      throw InstantException(
        message: 'Unexpected error: $e',
        code: 'unknown_error',
        originalError: e,
      );
    }
  }

  /// Verify magic code and sign in
  Future<AuthUser> verifyMagicCode({
    required String email,
    required String code,
  }) async {
    InstantDBLogging.auth.debug('AuthManager: verifyMagicCode called with email: $email, code: ${code.replaceAll(RegExp(r'.'), '*')}');
    
    // Validate email format
    if (!_isValidEmail(email)) {
      InstantDBLogging.auth.warning('AuthManager: Invalid email format: $email');
      throw InstantException(
        message: 'Invalid email format',
        code: 'invalid_email',
      );
    }

    // Validate magic code format (typically 6 digits)
    if (code.isEmpty || code.length < 6) {
      InstantDBLogging.auth.warning('AuthManager: Invalid magic code format - length: ${code.length}');
      throw InstantException(
        message: 'Invalid magic code format',
        code: 'invalid_code',
      );
    }

    try {
      InstantDBLogging.auth.debug('AuthManager: Sending POST request to ${baseUrl}/runtime/auth/verify_magic_code');
      InstantDBLogging.auth.debug('AuthManager: Request data - email: $email, appId: $appId');
      
      final response = await _dio.post('/runtime/auth/verify_magic_code', data: {
        'email': email,
        'code': code,
        'app-id': appId,
      });

      InstantDBLogging.auth.debug('AuthManager: Magic code verification successful - Status: ${response.statusCode}');
      InstantDBLogging.auth.debug('AuthManager: Response data keys: ${(response.data as Map<String, dynamic>).keys}');
      
      final data = response.data as Map<String, dynamic>;
      final userData = data['user'] as Map<String, dynamic>;
      
      InstantDBLogging.auth.debug('AuthManager: User object fields: ${userData.keys}');
      InstantDBLogging.auth.debug('AuthManager: Full user data: $userData');
      
      final user = AuthUser.fromJson(userData);

      // The AuthUser should now properly parse the refresh_token field
      final token = user.refreshToken;
      if (token == null) {
        InstantDBLogging.auth.severe('No token found after AuthUser parsing. User data keys: ${userData.keys}, AuthUser refreshToken: ${user.refreshToken}');
        throw InstantException(
          message: 'No authentication token received from server',
          code: 'missing_token',
        );
      }

      _authToken = token;
      _currentUser.value = user;

      // Update Dio headers
      _dio.options.headers['Authorization'] = 'Bearer $token';

      InstantDBLogging.auth.debug('AuthManager: User successfully authenticated: ${user.email}');
      return user;
      
    } on DioException catch (e) {
      InstantDBLogging.auth.severe('AuthManager: DioException in verifyMagicCode', e);
      InstantDBLogging.auth.severe('AuthManager: Status code: ${e.response?.statusCode}');
      InstantDBLogging.auth.severe('AuthManager: Response data: ${e.response?.data}');
      InstantDBLogging.auth.severe('AuthManager: Request URL: ${e.requestOptions.uri}');
      
      final errorMessage = e.response?.data?['message'] ?? e.message ?? 'Unknown error';
      InstantDBLogging.auth.severe('AuthManager: Final error message: $errorMessage');
      
      throw InstantException(
        message: 'Failed to verify magic code: $errorMessage',
        code: 'auth_error',
        originalError: e,
      );
    } catch (e, stackTrace) {
      InstantDBLogging.auth.severe('AuthManager: Unexpected error in verifyMagicCode', e, stackTrace);
      throw InstantException(
        message: 'Unexpected error: $e',
        code: 'unknown_error',
        originalError: e,
      );
    }
  }

  /// Validate email format using regex
  bool _isValidEmail(String email) {
    if (email.isEmpty) return false;
    
    // Basic email validation regex
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    
    return emailRegex.hasMatch(email) && email.length <= 254;
  }

  /// Validate password strength
  bool _isStrongPassword(String password) {
    if (password.length < 8) return false;
    
    // For international characters, be more lenient
    if (password.runes.any((rune) => rune > 127)) {
      // Contains non-ASCII characters - just check length and basic requirements
      final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password) || 
                       password.runes.any((rune) => rune > 127);
      final hasNumber = RegExp(r'[0-9]').hasMatch(password);
      final hasSpecial = RegExp(r'[!@#\$%\^&*()\-_=+\[\]{}|;:,.<>?/~`™]').hasMatch(password);
      
      return hasLetter && (hasNumber || hasSpecial);
    }
    
    // For ASCII-only passwords, apply stricter rules
    // Check for uppercase letter
    if (!RegExp(r'[A-Z]').hasMatch(password)) return false;
    
    // Check for lowercase letter
    if (!RegExp(r'[a-z]').hasMatch(password)) return false;
    
    // Check for number
    if (!RegExp(r'[0-9]').hasMatch(password)) return false;
    
    // Check for special character (include a wider range)
    if (!RegExp(r'[!@#\$%\^&*()\-_=+\[\]{}|;:,.<>?/~`™]').hasMatch(password)) return false;
    
    return true;
  }
}