import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';

void main() {
  group('Advanced Query Engine Tests', () {
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
        appId: 'test-advanced-queries',
        config: InstantConfig(
          syncEnabled: false, // Disable sync for unit tests
          persistenceDir: 'test_db_advanced_$testId',
        ),
      );
    });

    tearDown(() async {
      await db.dispose();
    });

    group('WHERE clause operators', () {
      setUp(() async {
        // Create test data
        final users = [
          {
            'id': 'user1',
            'name': 'Alice',
            'age': 25,
            'score': 85.5,
            'active': true,
          },
          {
            'id': 'user2',
            'name': 'Bob',
            'age': 30,
            'score': 92.0,
            'active': false,
          },
          {
            'id': 'user3',
            'name': 'Charlie',
            'age': 35,
            'score': 78.3,
            'active': true,
          },
          {
            'id': 'user4',
            'name': 'Diana',
            'age': 28,
            'score': 95.2,
            'active': true,
          },
        ];

        for (final user in users) {
          await db.transact([...db.create('users', user)]);
        }

        // Wait for operations to complete
        await Future.delayed(const Duration(milliseconds: 100));
      });

      test('should support greater than operator', () async {
        final querySignal = db.query({
          'users': {
            'where': {
              'age': {'>': 28},
            },
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        expect(querySignal.value.isLoading, isFalse);
        expect(querySignal.value.hasData, isTrue);

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(2)); // Bob (30) and Charlie (35)

        for (final user in users) {
          expect((user['age'] as int) > 28, isTrue);
        }
      });

      test('should support less than or equal operator', () async {
        final querySignal = db.query({
          'users': {
            'where': {
              'age': {'<=': 28},
            },
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(2)); // Alice (25) and Diana (28)

        for (final user in users) {
          expect((user['age'] as int) <= 28, isTrue);
        }
      });

      test('should support not equal operator', () async {
        final querySignal = db.query({
          'users': {
            'where': {
              'age': {'!=': 30},
            },
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(3)); // All except Bob

        for (final user in users) {
          expect(user['age'], isNot(equals(30)));
        }
      });

      test('should support in operator', () async {
        final querySignal = db.query({
          'users': {
            'where': {
              'age': {
                'in': [25, 35],
              },
            },
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(2)); // Alice and Charlie

        for (final user in users) {
          expect([25, 35].contains(user['age']), isTrue);
        }
      });

      test('should support not in operator', () async {
        final querySignal = db.query({
          'users': {
            'where': {
              'age': {
                'not_in': [25, 30],
              },
            },
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(2)); // Charlie and Diana

        for (final user in users) {
          expect([25, 30].contains(user['age']), isFalse);
        }
      });

      test('should support boolean values', () async {
        final querySignal = db.query({
          'users': {
            'where': {'active': true},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(3)); // Alice, Charlie, Diana

        for (final user in users) {
          expect(user['active'], isTrue);
        }
      });

      test('should support AND conditions', () async {
        final querySignal = db.query({
          'users': {
            'where': {
              'age': {'>': 25},
              'active': true,
            },
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(2)); // Charlie and Diana

        for (final user in users) {
          expect((user['age'] as int) > 25, isTrue);
          expect(user['active'], isTrue);
        }
      });

      test('should support OR conditions', () async {
        final querySignal = db.query({
          'users': {
            'where': {
              '\$or': [
                {'age': 25},
                {'age': 35},
              ],
            },
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(2)); // Alice and Charlie

        for (final user in users) {
          expect([25, 35].contains(user['age']), isTrue);
        }
      });

      test('should support range queries', () async {
        final querySignal = db.query({
          'users': {
            'where': {
              'score': {'>=': 80.0, '<': 95.0},
            },
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(2)); // Alice (85.5) and Bob (92.0)

        for (final user in users) {
          final score = user['score'] as double;
          expect(score >= 80.0 && score < 95.0, isTrue);
        }
      });
    });

    group('ORDER BY functionality', () {
      setUp(() async {
        // Create test data with various fields for sorting
        final posts = [
          {
            'id': 'post1',
            'title': 'Beta Post',
            'views': 150,
            'created': 1640000000,
            'priority': 2,
          },
          {
            'id': 'post2',
            'title': 'Alpha Post',
            'views': 300,
            'created': 1640000100,
            'priority': 1,
          },
          {
            'id': 'post3',
            'title': 'Gamma Post',
            'views': 75,
            'created': 1640000200,
            'priority': 1,
          },
          {
            'id': 'post4',
            'title': 'Delta Post',
            'views': 200,
            'created': 1640000050,
            'priority': 3,
          },
        ];

        for (final post in posts) {
          await db.transact([...db.create('posts', post)]);
        }

        await Future.delayed(const Duration(milliseconds: 100));
      });

      test('should sort by single field ascending', () async {
        final querySignal = db.query({
          'posts': {
            'orderBy': {'views': 'asc'},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final posts = querySignal.value.data!['posts'] as List;
        expect(posts.length, equals(4));

        // Should be ordered: Gamma (75), Beta (150), Delta (200), Alpha (300)
        expect(posts[0]['title'], equals('Gamma Post'));
        expect(posts[1]['title'], equals('Beta Post'));
        expect(posts[2]['title'], equals('Delta Post'));
        expect(posts[3]['title'], equals('Alpha Post'));
      });

      test('should sort by single field descending', () async {
        final querySignal = db.query({
          'posts': {
            'orderBy': {'views': 'desc'},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final posts = querySignal.value.data!['posts'] as List;
        expect(posts.length, equals(4));

        // Should be ordered: Alpha (300), Delta (200), Beta (150), Gamma (75)
        expect(posts[0]['title'], equals('Alpha Post'));
        expect(posts[1]['title'], equals('Delta Post'));
        expect(posts[2]['title'], equals('Beta Post'));
        expect(posts[3]['title'], equals('Gamma Post'));
      });

      test('should sort by multiple fields', () async {
        final querySignal = db.query({
          'posts': {
            'orderBy': [
              {'priority': 'asc'},
              {'views': 'desc'},
            ],
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final posts = querySignal.value.data!['posts'] as List;
        expect(posts.length, equals(4));

        // Should be ordered by priority ASC, then views DESC within same priority
        // Priority 1: Alpha (300), Gamma (75)
        // Priority 2: Beta (150)
        // Priority 3: Delta (200)
        expect(
          posts[0]['title'],
          equals('Alpha Post'),
        ); // Priority 1, Views 300
        expect(posts[1]['title'], equals('Gamma Post')); // Priority 1, Views 75
        expect(posts[2]['title'], equals('Beta Post')); // Priority 2, Views 150
        expect(
          posts[3]['title'],
          equals('Delta Post'),
        ); // Priority 3, Views 200
      });

      test('should sort by string fields', () async {
        final querySignal = db.query({
          'posts': {
            'orderBy': {'title': 'asc'},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final posts = querySignal.value.data!['posts'] as List;
        expect(posts.length, equals(4));

        // Should be alphabetical: Alpha, Beta, Delta, Gamma
        expect(posts[0]['title'], equals('Alpha Post'));
        expect(posts[1]['title'], equals('Beta Post'));
        expect(posts[2]['title'], equals('Delta Post'));
        expect(posts[3]['title'], equals('Gamma Post'));
      });
    });

    group('Pagination', () {
      setUp(() async {
        // Create 25 test items for pagination testing
        for (int i = 1; i <= 25; i++) {
          await db.transact([
            ...db.create('items', {
              'id': 'item$i',
              'number': i,
              'category': i % 3 == 0 ? 'A' : (i % 3 == 1 ? 'B' : 'C'),
            }),
          ]);
        }

        await Future.delayed(const Duration(milliseconds: 200));
      });

      test('should support limit', () async {
        final querySignal = db.query({
          'items': {
            'limit': 5,
            'orderBy': {'number': 'asc'},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final items = querySignal.value.data!['items'] as List;
        expect(items.length, equals(5));

        // Should get items 1-5
        for (int i = 0; i < 5; i++) {
          expect(items[i]['number'], equals(i + 1));
        }
      });

      test('should support offset', () async {
        final querySignal = db.query({
          'items': {
            'limit': 5,
            'offset': 10,
            'orderBy': {'number': 'asc'},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final items = querySignal.value.data!['items'] as List;
        expect(items.length, equals(5));

        // Should get items 11-15
        for (int i = 0; i < 5; i++) {
          expect(items[i]['number'], equals(i + 11));
        }
      });

      test('should support pagination with where clause', () async {
        final querySignal = db.query({
          'items': {
            'where': {'category': 'B'},
            'limit': 3,
            'offset': 2,
            'orderBy': {'number': 'asc'},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final items = querySignal.value.data!['items'] as List;
        expect(items.length, lessThanOrEqualTo(3));

        // All items should be category B
        for (final item in items) {
          expect(item['category'], equals('B'));
        }
      });

      test('should handle offset beyond available data', () async {
        final querySignal = db.query({
          'items': {
            'limit': 5,
            'offset': 100,
            'orderBy': {'number': 'asc'},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final items = querySignal.value.data!['items'] as List;
        expect(items.length, equals(0));
      });
    });

    group('Nested Queries and Includes', () {
      setUp(() async {
        // Create users and their posts
        final users = [
          {'id': 'user1', 'name': 'Alice', 'email': 'alice@test.com'},
          {'id': 'user2', 'name': 'Bob', 'email': 'bob@test.com'},
        ];

        final posts = [
          {
            'id': 'post1',
            'title': 'Alice Post 1',
            'authorId': 'user1',
            'published': true,
          },
          {
            'id': 'post2',
            'title': 'Alice Post 2',
            'authorId': 'user1',
            'published': false,
          },
          {
            'id': 'post3',
            'title': 'Bob Post 1',
            'authorId': 'user2',
            'published': true,
          },
        ];

        for (final user in users) {
          await db.transact([...db.create('users', user)]);
        }

        for (final post in posts) {
          await db.transact([...db.create('posts', post)]);
        }

        await Future.delayed(const Duration(milliseconds: 100));
      });

      test('should include related entities (one-to-one)', () async {
        final querySignal = db.query({
          'posts': {
            'include': {'author': {}},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final posts = querySignal.value.data!['posts'] as List;
        expect(posts.length, equals(3));

        for (final post in posts) {
          expect(post['author'], isNotNull);
          expect(post['author']['name'], isA<String>());

          // Verify relationship is correct
          if (post['authorId'] == 'user1') {
            expect(post['author']['name'], equals('Alice'));
          } else {
            expect(post['author']['name'], equals('Bob'));
          }
        }
      });

      test('should include related entities (one-to-many)', () async {
        final querySignal = db.query({
          'users': {
            'include': {'posts': {}},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(2));

        for (final user in users) {
          expect(user['posts'], isA<List>());
          final userPosts = user['posts'] as List;

          if (user['name'] == 'Alice') {
            expect(userPosts.length, equals(2));
          } else if (user['name'] == 'Bob') {
            expect(userPosts.length, equals(1));
          }

          // All posts should belong to this user
          for (final post in userPosts) {
            expect(post['authorId'], equals(user['id']));
          }
        }
      });

      test('should support nested includes with where clauses', () async {
        final querySignal = db.query({
          'users': {
            'include': {
              'posts': {
                'where': {'published': true},
                'orderBy': {'title': 'asc'},
              },
            },
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final users = querySignal.value.data!['users'] as List;
        expect(users.length, equals(2));

        for (final user in users) {
          final userPosts = user['posts'] as List;

          // All included posts should be published
          for (final post in userPosts) {
            expect(post['published'], isTrue);
          }

          if (user['name'] == 'Alice') {
            expect(userPosts.length, equals(1)); // Only 1 published post
          } else if (user['name'] == 'Bob') {
            expect(userPosts.length, equals(1)); // 1 published post
          }
        }
      });
    });

    group('Aggregation Functions', () {
      setUp(() async {
        // Create test data for aggregations
        final sales = [
          {
            'id': 'sale1',
            'amount': 100.0,
            'region': 'North',
            'date': '2024-01-01',
          },
          {
            'id': 'sale2',
            'amount': 250.0,
            'region': 'South',
            'date': '2024-01-02',
          },
          {
            'id': 'sale3',
            'amount': 175.0,
            'region': 'North',
            'date': '2024-01-03',
          },
          {
            'id': 'sale4',
            'amount': 300.0,
            'region': 'South',
            'date': '2024-01-04',
          },
        ];

        for (final sale in sales) {
          await db.transact([...db.create('sales', sale)]);
        }

        await Future.delayed(const Duration(milliseconds: 100));
      });

      test('should support count aggregation', () async {
        final querySignal = db.query({
          'sales': {
            '\$aggregate': {'count': '*'},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final results = querySignal.value.data!['sales'] as List;
        expect(results.length, equals(1));
        final result = results.first as Map;
        expect(result['count'], equals(4));
      });

      test('should support sum aggregation', () async {
        final querySignal = db.query({
          'sales': {
            '\$aggregate': {'sum': 'amount'},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final results = querySignal.value.data!['sales'] as List;
        expect(results.length, equals(1));
        final result = results.first as Map;
        expect(result['sum'], equals(825.0)); // 100 + 250 + 175 + 300
      });

      test('should support average aggregation', () async {
        final querySignal = db.query({
          'sales': {
            '\$aggregate': {'avg': 'amount'},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final results = querySignal.value.data!['sales'] as List;
        expect(results.length, equals(1));
        final result = results.first as Map;
        expect(result['avg'], equals(206.25)); // 825 / 4
      });

      test('should support min/max aggregation', () async {
        final querySignal = db.query({
          'sales': {
            '\$aggregate': {'min': 'amount', 'max': 'amount'},
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final results = querySignal.value.data!['sales'] as List;
        expect(results.length, equals(1));
        final result = results.first as Map;
        expect(result['min'], equals(100.0));
        expect(result['max'], equals(300.0));
      });

      test('should support group by with aggregations', () async {
        final querySignal = db.query({
          'sales': {
            '\$aggregate': {'sum': 'amount', 'count': '*'},
            '\$groupBy': ['region'],
          },
        });

        await Future.delayed(const Duration(milliseconds: 100));

        final results = querySignal.value.data!['sales'] as List;
        expect(results.length, equals(2));

        for (final result in results) {
          if (result['region'] == 'North') {
            expect(result['sum'], equals(275.0)); // 100 + 175
            expect(result['count'], equals(2));
          } else if (result['region'] == 'South') {
            expect(result['sum'], equals(550.0)); // 250 + 300
            expect(result['count'], equals(2));
          }
        }
      });
    });

    group('Performance Tests', () {
      test('should handle large dataset queries efficiently', () async {
        // Create 1000 test records
        final stopwatch = Stopwatch()..start();

        for (int i = 1; i <= 1000; i++) {
          await db.transact([
            ...db.create('large_items', {
              'id': 'item$i',
              'value': i,
              'category': 'category${i % 10}',
              'active': i % 2 == 0,
            }),
          ]);

          // Batch operations to avoid overwhelming the system
          if (i % 50 == 0) {
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }

        final createTime = stopwatch.elapsedMilliseconds;
        print('Created 1000 records in ${createTime}ms');

        // Query with complex conditions
        stopwatch.reset();

        final querySignal = db.query({
          'large_items': {
            'where': {
              'value': {'>': 500},
              'active': true,
            },
            'orderBy': {'value': 'desc'},
            'limit': 50,
          },
        });

        await Future.delayed(const Duration(milliseconds: 200));
        stopwatch.stop();

        final queryTime = stopwatch.elapsedMilliseconds;
        print('Complex query completed in ${queryTime}ms');

        final items = querySignal.value.data!['large_items'] as List;
        expect(items.length, equals(50));
        expect(queryTime, lessThan(1000)); // Should complete within 1 second

        // Verify results are correct
        for (final item in items) {
          expect(item['value'] as int > 500, isTrue);
          expect(item['active'], isTrue);
        }
      });

      test('should cache repeated queries', () async {
        // Create test data
        for (int i = 1; i <= 10; i++) {
          await db.transact([
            ...db.create('cache_items', {'id': 'item$i', 'value': i}),
          ]);
        }

        await Future.delayed(const Duration(milliseconds: 100));

        final query = {
          'cache_items': {
            'orderBy': {'value': 'asc'},
          },
        };

        // First query
        final stopwatch = Stopwatch()..start();
        final querySignal1 = db.query(query);
        await Future.delayed(const Duration(milliseconds: 100));
        final firstQueryTime = stopwatch.elapsedMilliseconds;

        // Second identical query (should use cache)
        stopwatch.reset();
        final querySignal2 = db.query(query);
        await Future.delayed(const Duration(milliseconds: 50));
        final secondQueryTime = stopwatch.elapsedMilliseconds;

        print(
          'First query: ${firstQueryTime}ms, Second query: ${secondQueryTime}ms',
        );

        // Should return same signal instance (cached)
        expect(identical(querySignal1, querySignal2), isTrue);

        // Results should be identical
        expect(querySignal1.value.data, equals(querySignal2.value.data));
      });
    });
  });
}
