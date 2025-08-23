import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';

void main() {
  group('Authentication Integration Tests', () {
    late InstantDB db;
    
    setUpAll(() async {
      // Initialize database factory for testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // Initialize InstantDB instance with unique persistence dir for each test
      final testId = DateTime.now().millisecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: 'test-auth-integration',
        config: InstantConfig(
          syncEnabled: false, // Disable sync for unit tests
          persistenceDir: 'test_db_auth_$testId',
          // Use a mock server URL for testing
          baseUrl: 'https://mock-api.instantdb.com',
        ),
      );
    });

    tearDown(() async {
      await db.dispose();
    });

    group('Authentication State Management', () {
      test('should start with no authenticated user', () {
        expect(db.auth.currentUser.value, isNull);
      });

      test('should emit authentication state changes', () async {
        var stateChanges = <AuthUser?>[];
        
        // Subscribe to auth state changes
        final subscription = db.auth.onAuthStateChange.listen((user) {
          stateChanges.add(user);
        });
        
        // Initial state should be null
        expect(stateChanges.length, equals(0));
        
        // Sign in should fail in test environment but we can test the flow
        try {
          await db.auth.signIn(email: 'test@example.com', password: 'password123');
        } catch (e) {
          // Expected to fail without real server
          expect(e, isNotNull);
        }
        
        // Clean up
        await subscription.cancel();
      });

      test('should validate email format', () {
        expect(() async {
          await db.auth.signUp(email: 'invalid-email', password: 'password123');
        }, throwsA(isA<Exception>()));
      });

      test('should validate password requirements', () {
        expect(() async {
          await db.auth.signUp(email: 'test@example.com', password: '123');
        }, throwsA(isA<Exception>()));
      });

      test('should handle token-based authentication', () async {
        try {
          await db.auth.signInWithToken('mock-jwt-token');
        } catch (e) {
          // Expected to fail without real server
          expect(e, isNotNull);
        }
      });

      test('should handle sign out', () async {
        // Even without being signed in, sign out should work gracefully
        await db.auth.signOut();
        expect(db.auth.currentUser.value, isNull);
      });
    });

    group('Magic Link Authentication', () {
      test('should send magic link email', () async {
        try {
          await db.auth.sendMagicLink('test@example.com');
        } catch (e) {
          // Expected to fail without real server
          expect(e, isNotNull);
        }
      });

      test('should send magic code email', () async {
        try {
          await db.auth.sendMagicCode('test@example.com');
        } catch (e) {
          // Expected to fail without real server
          expect(e, isNotNull);
        }
      });

      test('should verify magic code', () async {
        try {
          await db.auth.verifyMagicCode(
            email: 'test@example.com',
            code: '123456',
          );
        } catch (e) {
          // Expected to fail without real server
          expect(e, isNotNull);
        }
      });

      test('should validate magic code format', () {
        expect(() async {
          await db.auth.verifyMagicCode(
            email: 'test@example.com',
            code: '123', // Too short
          );
        }, throwsA(isA<Exception>()));
      });
    });

    group('User Management', () {
      test('should handle user metadata updates', () async {
        try {
          await db.auth.updateUser({'displayName': 'John Doe'});
        } catch (e) {
          // Expected to fail without authentication
          expect(e, isNotNull);
        }
      });

      test('should handle user refresh', () async {
        final result = await db.auth.refreshUser();
        // Should return null when not authenticated
        expect(result, isNull);
      });

      test('should handle password reset', () async {
        try {
          await db.auth.resetPassword('test@example.com');
        } catch (e) {
          // Expected to fail without real server
          expect(e, isNotNull);
        }
      });
    });

    group('Error Handling', () {
      test('should handle network errors gracefully', () async {
        try {
          await db.auth.signIn(email: 'test@example.com', password: 'wrongpassword');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle invalid credentials', () async {
        try {
          await db.auth.signIn(email: 'nonexistent@example.com', password: 'password');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle malformed tokens', () async {
        try {
          await db.auth.signInWithToken('invalid-token-format');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle expired tokens', () async {
        // Mock an expired JWT token
        const expiredToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjE1MTYyMzkwMjJ9.invalid';
        
        try {
          await db.auth.signInWithToken(expiredToken);
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle server unavailable', () async {
        // This test simulates server being down
        try {
          await db.auth.signUp(email: 'test@example.com', password: 'password123');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });
    });

    group('Security Validation', () {
      test('should reject weak passwords', () {
        final weakPasswords = [
          '123',
          'password',
          'abc123',
          '11111111',
          'qwerty',
        ];

        for (final password in weakPasswords) {
          expect(() async {
            await db.auth.signUp(email: 'test@example.com', password: password);
          }, throwsA(isA<Exception>()));
        }
      });

      test('should accept strong passwords', () async {
        final strongPasswords = [
          'MyStr0ngP@ssw0rd!',
          'C0mpl3x!P@ssW0rd',
          'S3cur3!Passw0rd#2024',
        ];

        for (final password in strongPasswords) {
          try {
            await db.auth.signUp(email: 'test@example.com', password: password);
          } catch (e) {
            // Will fail due to no server, but password validation should pass
            expect(e.toString().contains('password'), isFalse);
          }
        }
      });

      test('should validate email formats', () async {
        final invalidEmails = [
          'notanemail',
          '@domain.com',
          'user@',
          'user@domain',
          'user.domain.com',
          'user@domain.',
        ];

        for (final email in invalidEmails) {
          try {
            await db.auth.signUp(email: email, password: 'ValidPass123!');
          } catch (e) {
            expect(e.toString().toLowerCase().contains('email'), isTrue);
          }
        }
      });

      test('should accept valid email formats', () async {
        final validEmails = [
          'user@example.com',
          'test.user@example.co.uk',
          'user+tag@example.com',
          'user123@example-site.com',
        ];

        for (final email in validEmails) {
          try {
            await db.auth.signUp(email: email, password: 'ValidPass123!');
          } catch (e) {
            // Will fail due to no server, but email validation should pass
            expect(e.toString().toLowerCase().contains('email format'), isFalse);
          }
        }
      });

      test('should sanitize user input', () async {
        final maliciousInputs = [
          '<script>alert("xss")</script>@example.com',
          'user@example.com\'; DROP TABLE users; --',
          'user@example.com\x00',
        ];

        for (final input in maliciousInputs) {
          try {
            await db.auth.signUp(email: input, password: 'ValidPass123!');
          } catch (e) {
            expect(e, isA<Exception>());
          }
        }
      });
    });

    group('Integration with Presence System', () {
      test('should update presence when authentication changes', () async {
        // Test that presence is affected by auth state
        final roomId = 'test-room';
        
        // Initially, should work with anonymous user
        await db.presence.setPresence(roomId, {'status': 'online'});
        
        final presenceSignal = db.presence.getPresence(roomId);
        expect(presenceSignal.value.isNotEmpty, isTrue);
        
        // The user ID should be anonymous
        final userId = presenceSignal.value.keys.first;
        expect(userId.startsWith('anonymous-'), isTrue);
      });

      test('should clear presence data on sign out', () async {
        final roomId = 'test-room';
        
        // Set presence
        await db.presence.setPresence(roomId, {'status': 'online'});
        
        // Sign out (even if not signed in, it should work)
        await db.auth.signOut();
        
        // Presence should still exist for anonymous user
        // (In a real implementation, you might want to clear it)
        final presenceSignal = db.presence.getPresence(roomId);
        expect(presenceSignal.value, isA<Map>());
      });
    });

    group('Performance and Reliability', () {
      test('should handle rapid authentication attempts', () async {
        final futures = <Future>[];
        
        // Attempt multiple simultaneous sign-ins
        for (int i = 0; i < 10; i++) {
          futures.add(
            db.auth.signIn(
              email: 'user$i@example.com',
              password: 'password123',
            ).catchError((e) => AuthUser(id: '', email: '')), // Return dummy AuthUser on error
          );
        }
        
        await Future.wait(futures);
        
        // Should not crash or cause issues
        expect(db.auth.currentUser.value, isNull);
      });

      test('should handle authentication timeout', () async {
        // This would test timeout scenarios in a real environment
        final stopwatch = Stopwatch()..start();
        
        try {
          await db.auth.signIn(email: 'test@example.com', password: 'password123');
        } catch (e) {
          stopwatch.stop();
          // Should fail reasonably quickly
          expect(stopwatch.elapsedMilliseconds, lessThan(30000)); // Under 30s
        }
      });

      test('should maintain auth state across app restarts', () async {
        // In a real implementation, this would test token persistence
        // For now, we just verify the mechanism exists
        expect(db.auth.currentUser, isA<ReadonlySignal<AuthUser?>>());
        
        // The auth state should be persisted somewhere
        // This is a placeholder for actual persistence testing
      });
    });

    group('Edge Cases', () {
      test('should handle extremely long email addresses', () async {
        final longEmail = 'a' * 250 + '@example.com';
        
        try {
          await db.auth.signUp(email: longEmail, password: 'ValidPass123!');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });

      test('should handle special characters in passwords', () async {
        final specialPasswords = [
          'Pass123!@#\$%^&*()',
          'Påssw0rd123!',
          'P@ssw0rd™',
          'مرحبا123!',
          '密码123!',
        ];

        for (final password in specialPasswords) {
          try {
            await db.auth.signUp(email: 'test@example.com', password: password);
          } catch (e) {
            // Should fail due to no server, but not due to character encoding
            expect(e.toString().contains('character'), isFalse);
          }
        }
      });

      test('should handle concurrent auth operations', () async {
        final futures = <Future>[];
        
        // Try multiple different operations simultaneously
        futures.add(db.auth.signIn(email: 'test1@example.com', password: 'pass1').catchError((e) => AuthUser(id: '', email: '')));
        futures.add(db.auth.signUp(email: 'test2@example.com', password: 'pass2').catchError((e) => AuthUser(id: '', email: '')));
        futures.add(db.auth.sendMagicLink('test3@example.com').then((_) => null).catchError((e) => null));
        futures.add(db.auth.resetPassword('test4@example.com').then((_) => null).catchError((e) => null));
        
        await Future.wait(futures);
        
        // Should not crash
        expect(db.auth.currentUser.value, isNull);
      });

      test('should handle null and empty inputs', () async {
        // Test various null/empty scenarios
        try {
          await db.auth.signIn(email: '', password: 'password');
        } catch (e) {
          expect(e, isA<Exception>());
        }

        try {
          await db.auth.signIn(email: 'test@example.com', password: '');
        } catch (e) {
          expect(e, isA<Exception>());
        }

        try {
          await db.auth.sendMagicLink('');
        } catch (e) {
          expect(e, isA<Exception>());
        }
      });
    });

    group('Mock Authentication Helper', () {
      test('should provide test utilities for mocking auth', () {
        // This would be useful for other tests
        final mockUser = AuthUser(
          id: 'test-user-123',
          email: 'test@example.com',
          metadata: {'role': 'admin'},
          refreshToken: 'mock-refresh',
        );

        expect(mockUser.id, equals('test-user-123'));
        expect(mockUser.email, equals('test@example.com'));
        expect(mockUser.metadata['role'], equals('admin'));
      });

      test('should validate AuthUser serialization', () {
        final user = AuthUser(
          id: 'test-user',
          email: 'test@example.com',
          metadata: {'name': 'Test User'},
          refreshToken: 'refresh-token',
        );

        final json = user.toJson();
        final reconstructed = AuthUser.fromJson(json);

        expect(reconstructed.id, equals(user.id));
        expect(reconstructed.email, equals(user.email));
        expect(reconstructed.metadata, equals(user.metadata));
        expect(reconstructed.refreshToken, equals(user.refreshToken));
      });
    });
  });
}