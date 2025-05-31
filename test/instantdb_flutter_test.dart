import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';

void main() {
  group('InstantDB Flutter Tests', () {
    late InstantDB db;
    late String appId;

    setUpAll(() async {
      // Initialize database factory for testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      
      // Load .env file for testing
      try {
        await dotenv.load(fileName: '.env');
        appId = dotenv.env['INSTANTDB_API_ID'] ?? 'test-app-id';
      } catch (e) {
        // If .env file doesn't exist, use a test app ID
        appId = 'test-app-id';
      }
    });

    setUp(() async {
      // Initialize InstantDB instance with unique persistence dir for each test
      final testId = DateTime.now().millisecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: appId,
        config: InstantConfig(
          syncEnabled: false, // Disable sync for unit tests
          persistenceDir: 'test_db_$testId',
        ),
      );
    });

    tearDown(() async {
      await db.dispose();
    });

    test('should initialize InstantDB instance', () {
      expect(db.appId, equals(appId));
      expect(db.isReady.value, isTrue);
    });

    test('should generate unique IDs', () {
      final id1 = db.id();
      final id2 = db.id();
      
      expect(id1, isNotEmpty);
      expect(id2, isNotEmpty);
      expect(id1, isNot(equals(id2)));
    });

    test('should create and query entities', () async {
      // Create a simple entity
      final entityId = db.id();
      await db.transact([
        ...db.create('users', {
          'id': entityId,
          'name': 'Test User',
          'email': 'test@example.com',
        }),
      ]);

      // Query the entity
      final querySignal = db.query({
        'users': {
          'where': {'id': entityId},
        },
      });

      // Wait for the query to complete
      await Future.delayed(const Duration(milliseconds: 100));

      expect(querySignal.value.isLoading, isFalse);
      expect(querySignal.value.hasData, isTrue);
      
      final users = querySignal.value.data!['users'] as List;
      expect(users, hasLength(1));
      expect(users.first['name'], equals('Test User'));
      expect(users.first['email'], equals('test@example.com'));
    });

    test('should update entities', () async {
      // Create entity
      final entityId = db.id();
      await db.transact([
        ...db.create('users', {
          'id': entityId,
          'name': 'Original Name',
        }),
      ]);

      // Update entity
      await db.transact([
        db.update(entityId, {'name': 'Updated Name'}),
      ]);

      // Query updated entity
      final querySignal = db.query({
        'users': {
          'where': {'id': entityId},
        },
      });

      await Future.delayed(const Duration(milliseconds: 100));

      final users = querySignal.value.data!['users'] as List;
      expect(users.first['name'], equals('Updated Name'));
    });

    test('should delete entities', () async {
      // Create entity
      final entityId = db.id();
      await db.transact([
        ...db.create('users', {
          'id': entityId,
          'name': 'To Be Deleted',
        }),
      ]);

      // Delete entity
      await db.transact([
        db.delete(entityId),
      ]);

      // Query should return empty
      final querySignal = db.query({
        'users': {
          'where': {'id': entityId},
        },
      });

      await Future.delayed(const Duration(milliseconds: 100));

      final users = querySignal.value.data!['users'] as List;
      expect(users, isEmpty);
    });

    test('should handle query with where conditions', () async {
      // Create multiple entities
      for (int i = 0; i < 3; i++) {
        await db.transact([
          ...db.create('posts', {
            'id': db.id(),
            'title': 'Post $i',
            'status': i % 2 == 0 ? 'published' : 'draft',
          }),
        ]);
      }

      // Query published posts only
      final querySignal = db.query({
        'posts': {
          'where': {'status': 'published'},
        },
      });

      await Future.delayed(const Duration(milliseconds: 100));

      final posts = querySignal.value.data!['posts'] as List;
      expect(posts.length, equals(2)); // Posts 0 and 2
      for (final post in posts) {
        expect(post['status'], equals('published'));
      }
    });

    group('Schema validation', () {
      test('should validate string schema', () {
        final schema = Schema.string(minLength: 3, maxLength: 10);
        
        expect(schema.validate('hello'), isTrue);
        expect(schema.validate('hi'), isFalse); // Too short
        expect(schema.validate('this is too long'), isFalse); // Too long
        expect(schema.validate(123), isFalse); // Wrong type
      });

      test('should validate object schema', () {
        final userSchema = Schema.object({
          'name': Schema.string(minLength: 1),
          'age': Schema.number(min: 0, max: 150),
          'email': Schema.email(),
        }, required: ['name', 'email']);

        expect(userSchema.validate({
          'name': 'John',
          'age': 30,
          'email': 'john@example.com',
        }), isTrue);

        expect(userSchema.validate({
          'name': 'John',
          // Missing required email
        }), isFalse);

        expect(userSchema.validate({
          'name': 'John',
          'email': 'invalid-email',
        }), isFalse);
      });

      test('should validate array schema', () {
        final numbersSchema = Schema.array(Schema.number(), minLength: 1, maxLength: 5);
        
        expect(numbersSchema.validate([1, 2, 3]), isTrue);
        expect(numbersSchema.validate([]), isFalse); // Too short
        expect(numbersSchema.validate([1, 2, 3, 4, 5, 6]), isFalse); // Too long
        expect(numbersSchema.validate([1, 'two', 3]), isFalse); // Invalid item
      });
    });

    group('Authentication', () {
      test('should handle auth state', () {
        expect(db.auth.isAuthenticated, isFalse);
        expect(db.auth.currentUser.value, isNull);
      });

      // Note: Real auth tests would require a test server
      // These are just structure tests
    });
  });
}