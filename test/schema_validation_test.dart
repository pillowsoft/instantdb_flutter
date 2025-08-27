import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';

void main() {
  group('Schema Validation Tests', () {
    late InstantDB db;
    late InstantSchema schema;

    setUpAll(() async {
      // Initialize database factory for testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // Initialize InstantDB instance with unique persistence dir for each test
      final testId = DateTime.now().millisecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: 'test-schema-validation',
        config: InstantConfig(
          syncEnabled: false, // Disable sync for unit tests
          persistenceDir: 'test_db_schema_$testId',
        ),
      );

      // Create a comprehensive schema for testing
      schema = InstantSchemaBuilder()
          .addEntity(
            'users',
            Schema.object(
              {
                'id': Schema.id(),
                'name': Schema.string(minLength: 1, maxLength: 100),
                'email': Schema.email(),
                'age': Schema.number(min: 0, max: 150),
                'isActive': Schema.boolean(),
                'preferences': Schema.optional(
                  Schema.object({
                    'theme': Schema.string(),
                    'notifications': Schema.boolean(),
                  }),
                ),
                'tags': Schema.optional(
                  Schema.array(Schema.string(), minLength: 0, maxLength: 10),
                ),
                'metadata': Schema.optional(Schema.object({})),
              },
              required: ['id', 'name', 'email'],
            ),
          )
          .addEntity(
            'posts',
            Schema.object(
              {
                'id': Schema.id(),
                'title': Schema.string(minLength: 1, maxLength: 200),
                'content': Schema.string(minLength: 10),
                'authorId': Schema.id(),
                'published': Schema.boolean(),
                'publishedAt': Schema.optional(Schema.number()),
                'categories': Schema.array(
                  Schema.string(),
                  minLength: 1,
                  maxLength: 5,
                ),
                'viewCount': Schema.number(min: 0),
              },
              required: [
                'id',
                'title',
                'content',
                'authorId',
                'published',
                'categories',
                'viewCount',
              ],
            ),
          )
          .build();
    });

    tearDown(() async {
      await db.dispose();
    });

    group('Basic Schema Validation', () {
      test('should validate valid user data', () {
        final userData = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
          'age': 30,
          'isActive': true,
        };

        final isValid = schema.validateEntity('users', userData);
        expect(isValid, isTrue);
      });

      test('should reject invalid email format', () {
        final userData = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'invalid-email',
          'age': 30,
          'isActive': true,
        };

        final isValid = schema.validateEntity('users', userData);
        expect(isValid, isFalse);
      });

      test('should reject missing required fields', () {
        final userData = {
          'id': 'user123',
          'name': 'John Doe',
          // Missing required 'email' field
          'age': 30,
          'isActive': true,
        };

        final isValid = schema.validateEntity('users', userData);
        expect(isValid, isFalse);
      });

      test('should validate string length constraints', () {
        // Valid name length
        final validData = {
          'id': 'user123',
          'name': 'John',
          'email': 'john@example.com',
        };
        expect(schema.validateEntity('users', validData), isTrue);

        // Name too long
        final tooLongName = {
          'id': 'user123',
          'name': 'A' * 101, // 101 characters, max is 100
          'email': 'john@example.com',
        };
        expect(schema.validateEntity('users', tooLongName), isFalse);

        // Empty name
        final emptyName = {
          'id': 'user123',
          'name': '',
          'email': 'john@example.com',
        };
        expect(schema.validateEntity('users', emptyName), isFalse);
      });

      test('should validate number constraints', () {
        // Valid age
        final validAge = {
          'id': 'user123',
          'name': 'John',
          'email': 'john@example.com',
          'age': 25,
        };
        expect(schema.validateEntity('users', validAge), isTrue);

        // Age too young
        final tooYoung = {
          'id': 'user123',
          'name': 'John',
          'email': 'john@example.com',
          'age': -1,
        };
        expect(schema.validateEntity('users', tooYoung), isFalse);

        // Age too old
        final tooOld = {
          'id': 'user123',
          'name': 'John',
          'email': 'john@example.com',
          'age': 151,
        };
        expect(schema.validateEntity('users', tooOld), isFalse);
      });
    });

    group('Optional Fields Validation', () {
      test('should allow missing optional fields', () {
        final userData = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
          // Optional fields omitted
        };

        final isValid = schema.validateEntity('users', userData);
        expect(isValid, isTrue);
      });

      test('should validate optional object fields when present', () {
        final validPreferences = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
          'preferences': {'theme': 'dark', 'notifications': true},
        };

        expect(schema.validateEntity('users', validPreferences), isTrue);

        final invalidPreferences = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
          'preferences': {
            'theme': 123, // Should be string
            'notifications': true,
          },
        };

        expect(schema.validateEntity('users', invalidPreferences), isFalse);
      });

      test('should allow null for optional fields', () {
        final userData = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
          'preferences': null,
          'tags': null,
        };

        final isValid = schema.validateEntity('users', userData);
        expect(isValid, isTrue);
      });
    });

    group('Array Validation', () {
      test('should validate array items', () {
        final validTags = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
          'tags': ['developer', 'flutter', 'dart'],
        };

        expect(schema.validateEntity('users', validTags), isTrue);

        final invalidTags = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
          'tags': ['developer', 123, 'dart'], // 123 is not a string
        };

        expect(schema.validateEntity('users', invalidTags), isFalse);
      });

      test('should validate array length constraints', () {
        final tooManyTags = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
          'tags': List.generate(11, (i) => 'tag$i'), // 11 items, max is 10
        };

        expect(schema.validateEntity('users', tooManyTags), isFalse);

        final validArrayLength = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
          'tags': ['tag1', 'tag2'],
        };

        expect(schema.validateEntity('users', validArrayLength), isTrue);
      });

      test('should validate required arrays', () {
        final validPost = {
          'id': 'post123',
          'title': 'My Post',
          'content':
              'This is a long post content with more than 10 characters.',
          'authorId': 'user123',
          'published': true,
          'categories': ['tech', 'programming'],
          'viewCount': 0,
        };

        expect(schema.validateEntity('posts', validPost), isTrue);

        final missingCategories = {
          'id': 'post123',
          'title': 'My Post',
          'content':
              'This is a long post content with more than 10 characters.',
          'authorId': 'user123',
          'published': true,
          // categories is required but missing
          'viewCount': 0,
        };

        expect(schema.validateEntity('posts', missingCategories), isFalse);

        final emptyCategoriesArray = {
          'id': 'post123',
          'title': 'My Post',
          'content':
              'This is a long post content with more than 10 characters.',
          'authorId': 'user123',
          'published': true,
          'categories': [], // Empty array, but min length is 1
          'viewCount': 0,
        };

        expect(schema.validateEntity('posts', emptyCategoriesArray), isFalse);
      });
    });

    group('Complex Object Validation', () {
      test('should validate nested object structures', () {
        final validComplexUser = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
          'age': 30,
          'isActive': true,
          'preferences': {'theme': 'dark', 'notifications': false},
          'tags': ['developer', 'flutter'],
          'metadata': {
            'lastLogin': '2024-01-15T10:30:00Z',
            'loginCount': 42,
            'profile': {
              'bio': 'Flutter developer',
              'location': 'San Francisco',
            },
          },
        };

        final isValid = schema.validateEntity('users', validComplexUser);
        expect(isValid, isTrue);
      });

      test('should handle deeply nested validation', () {
        final deeplyNested = {
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
          'metadata': {
            'level1': {
              'level2': {
                'level3': {'data': 'deep value'},
              },
            },
          },
        };

        // Should be valid since metadata is an open object schema
        final isValid = schema.validateEntity('users', deeplyNested);
        expect(isValid, isTrue);
      });
    });

    group('Schema Integration with Database', () {
      test('should store and retrieve schema-validated entities', () async {
        final userData = {
          'id': 'user123',
          'name': 'Jane Smith',
          'email': 'jane@example.com',
          'age': 28,
          'isActive': true,
          'preferences': {'theme': 'light', 'notifications': true},
          'tags': ['designer', 'ui/ux'],
        };

        // Validate before storing
        final isValid = schema.validateEntity('users', userData);
        expect(isValid, isTrue);

        // Store in database
        await db.transact([...db.create('users', userData)]);

        // Wait for storage
        await Future.delayed(const Duration(milliseconds: 100));

        // Retrieve and validate structure
        final querySignal = db.query({'users': {}});
        await Future.delayed(const Duration(milliseconds: 100));

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(1));

        final retrievedUser = users.first;
        expect(retrievedUser['name'], equals('Jane Smith'));
        expect(retrievedUser['email'], equals('jane@example.com'));
        expect(retrievedUser['preferences'], isA<Map>());
        expect(retrievedUser['tags'], isA<List>());
      });

      test('should handle schema validation errors gracefully', () {
        final invalidUser = {
          'id': 'user123',
          'name': '', // Invalid: empty name
          'email': 'invalid-email', // Invalid: bad email format
          'age': -5, // Invalid: negative age
        };

        final isValid = schema.validateEntity('users', invalidUser);
        expect(isValid, isFalse);

        // In a real implementation, you might want to throw validation errors
        // or collect validation messages for user feedback
      });
    });

    group('Custom Validation Rules', () {
      test('should support custom string patterns', () {
        final phoneSchema = Schema.string(
          pattern: RegExp(r'^\+?[\d\s\-\(\)]+$'),
        );

        expect(phoneSchema.validate('+1 (555) 123-4567'), isTrue);
        expect(phoneSchema.validate('555-123-4567'), isTrue);
        expect(phoneSchema.validate('invalid-phone'), isFalse);
        expect(phoneSchema.validate('abc123'), isFalse);
      });

      test('should create entity schemas with automatic fields', () {
        final schema = InstantSchemaBuilder()
            .addEntity('testEntity', Schema.object({'name': Schema.string()}))
            .build();

        final entitySchema =
            schema.getEntitySchema('testEntity') as ObjectSchema;

        // Should automatically add id, createdAt, updatedAt
        expect(entitySchema.properties.containsKey('id'), isTrue);
        expect(entitySchema.properties.containsKey('createdAt'), isTrue);
        expect(entitySchema.properties.containsKey('updatedAt'), isTrue);
        expect(entitySchema.required.contains('id'), isTrue);
      });

      test('should validate various data types correctly', () {
        // String validation
        final stringSchema = Schema.string(minLength: 2, maxLength: 10);
        expect(stringSchema.validate('hello'), isTrue);
        expect(stringSchema.validate('h'), isFalse);
        expect(stringSchema.validate('this is too long'), isFalse);
        expect(stringSchema.validate(123), isFalse);

        // Number validation
        final numberSchema = Schema.number(min: 0, max: 100);
        expect(numberSchema.validate(50), isTrue);
        expect(numberSchema.validate(50.5), isTrue);
        expect(numberSchema.validate(-1), isFalse);
        expect(numberSchema.validate(101), isFalse);
        expect(numberSchema.validate('50'), isFalse);

        // Boolean validation
        final boolSchema = Schema.boolean();
        expect(boolSchema.validate(true), isTrue);
        expect(boolSchema.validate(false), isTrue);
        expect(boolSchema.validate('true'), isFalse);
        expect(boolSchema.validate(1), isFalse);

        // Array validation
        final arraySchema = Schema.array(
          Schema.string(),
          minLength: 1,
          maxLength: 3,
        );
        expect(arraySchema.validate(['one']), isTrue);
        expect(arraySchema.validate(['one', 'two']), isTrue);
        expect(arraySchema.validate([]), isFalse);
        expect(arraySchema.validate(['one', 'two', 'three', 'four']), isFalse);
        expect(arraySchema.validate(['one', 2]), isFalse);
      });

      test('should handle edge cases in validation', () {
        final schema = Schema.object(
          {
            'optionalString': Schema.optional(Schema.string()),
            'requiredNumber': Schema.number(),
          },
          required: ['requiredNumber'],
        );

        // Valid cases
        expect(schema.validate({'requiredNumber': 42}), isTrue);
        expect(
          schema.validate({'requiredNumber': 42, 'optionalString': 'hello'}),
          isTrue,
        );
        expect(
          schema.validate({'requiredNumber': 42, 'optionalString': null}),
          isTrue,
        );

        // Invalid cases
        expect(schema.validate({}), isFalse); // Missing required field
        expect(
          schema.validate({'optionalString': 'hello'}),
          isFalse,
        ); // Missing required field
        expect(
          schema.validate({'requiredNumber': '42'}),
          isFalse,
        ); // Wrong type
        expect(
          schema.validate({'requiredNumber': 42, 'optionalString': 123}),
          isFalse,
        ); // Wrong optional type
      });
    });

    group('Schema Description and Introspection', () {
      test('should provide readable schema descriptions', () {
        expect(Schema.string().description, equals('String'));
        expect(Schema.string(minLength: 5).description, contains('min: 5'));
        expect(Schema.number(min: 0, max: 100).description, contains('min: 0'));
        expect(Schema.boolean().description, equals('Boolean'));
        expect(
          Schema.array(Schema.string()).description,
          equals('Array<String>'),
        );
        expect(Schema.optional(Schema.string()).description, equals('String?'));
      });

      test('should allow schema introspection', () {
        final userSchema = schema.getEntitySchema('users');
        expect(userSchema, isNotNull);
        expect(userSchema, isA<ObjectSchema>());

        final objectSchema = userSchema as ObjectSchema;
        expect(objectSchema.properties.containsKey('name'), isTrue);
        expect(objectSchema.properties.containsKey('email'), isTrue);
        expect(objectSchema.required.contains('id'), isTrue);
        expect(objectSchema.required.contains('name'), isTrue);
      });
    });

    group('Performance Tests', () {
      test('should validate large objects efficiently', () {
        final largeObject = <String, dynamic>{
          'id': 'user123',
          'name': 'John Doe',
          'email': 'john@example.com',
        };

        // Add many optional fields
        for (int i = 0; i < 100; i++) {
          largeObject['field$i'] = 'value$i';
        }

        final stopwatch = Stopwatch()..start();

        final isValid = schema.validateEntity('users', largeObject);

        stopwatch.stop();

        expect(isValid, isTrue);
        expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Should be fast
      });

      test('should validate many objects efficiently', () {
        final users = List.generate(
          1000,
          (i) => {
            'id': 'user$i',
            'name': 'User $i',
            'email': 'user$i@example.com',
            'age': 20 + (i % 50),
            'isActive': i % 2 == 0,
          },
        );

        final stopwatch = Stopwatch()..start();

        int validCount = 0;
        for (final user in users) {
          if (schema.validateEntity('users', user)) {
            validCount++;
          }
        }

        stopwatch.stop();

        expect(validCount, equals(1000));
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(1000),
        ); // Should validate 1000 objects in under 1s
      });
    });
  });
}
