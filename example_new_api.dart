import 'package:instantdb_flutter/instantdb_flutter.dart';

/// Example showcasing the new InstantDB Flutter API features
/// This demonstrates the tx namespace, advanced query operators, and lookup functionality
void main() async {
  // Initialize InstantDB with the new API
  final db = await InstantDB.init(
    appId: 'your-app-id',
    config: const InstantConfig(
      syncEnabled: true,
      verboseLogging: true,
    ),
  );

  print('🚀 InstantDB initialized with new features!');

  // Example 1: Using the new tx namespace API
  print('\n📝 Example 1: New Transaction API');
  
  // Create a user with the new tx API
  final userId = db.id();
  await db.transactChunk(
    db.tx.users[userId].update({
      'name': 'Alice Smith',
      'email': 'alice@example.com',
      'age': 28,
      'status': 'active',
    })
  );
  
  // Create a goal and link it to the user
  final goalId = db.id();
  await db.transactChunk(
    db.tx.goals[goalId]
        .update({'title': 'Learn Flutter', 'completed': false})
        .merge({'priority': 'high', 'tags': ['flutter', 'mobile']}) // Deep merge
        .link({'userId': userId}) // Link to user
  );
  
  print('✅ Created user and goal with new tx API');

  // Example 2: Advanced Query Operators
  print('\n🔍 Example 2: Advanced Query Operators');
  
  // Query users with advanced operators
  final adultUsersQuery = db.subscribeQuery({
    'users': {
      'where': {
        'age': {'\$gte': 18}, // Greater than or equal to 18
        'status': {'\$ne': 'inactive'}, // Not equal to inactive
        'name': {'\$like': 'A%'}, // Names starting with A
      },
      'orderBy': {'age': 'desc'},
      'limit': 10,
    }
  });
  
  // Listen to query results
  effect(() {
    final result = adultUsersQuery.value;
    if (result.hasData) {
      final users = result.data!['users'] as List;
      print('Found ${users.length} adult users starting with A');
      for (final user in users) {
        print('  - ${user['name']}, age ${user['age']}');
      }
    }
  });

  // Example 3: Lookup References
  print('\n🔗 Example 3: Lookup References');
  
  // Create a task that references a user by email (not ID)
  final taskId = db.id();
  await db.transactChunk(
    db.tx.tasks[taskId].update({
      'title': 'Review Flutter docs',
      'assignee': lookup('users', 'email', 'alice@example.com'), // Lookup user by email
      'dueDate': DateTime.now().add(Duration(days: 7)).millisecondsSinceEpoch,
    })
  );
  
  print('✅ Created task with lookup reference to user');

  // Example 4: Complex Queries with Multiple Operators
  print('\n🎯 Example 4: Complex Queries');
  
  final complexQuery = db.subscribeQuery({
    'tasks': {
      'where': {
        '\$and': [
          {'dueDate': {'\$gt': DateTime.now().millisecondsSinceEpoch}}, // Future due date
          {
            '\$or': [
              {'priority': 'high'},
              {'priority': 'urgent'},
            ]
          },
          {'title': {'\$ilike': '%flutter%'}}, // Case-insensitive contains flutter
        ]
      },
      'include': {
        'assignee': {
          'where': {'status': 'active'}
        }
      },
      'orderBy': {'dueDate': 'asc'}
    }
  });
  
  // Example 5: Merge Operations for Deep Updates
  print('\n🔄 Example 5: Merge Operations');
  
  // Update user preferences with deep merge
  await db.transactChunk(
    db.tx.users[userId].merge({
      'preferences': {
        'theme': 'dark',
        'notifications': {
          'email': true,
          'push': false,
        },
        'language': 'en',
      },
      'settings': {
        'privacy': 'friends',
      }
    })
  );
  
  // Later, update just the notification settings without affecting other preferences
  await db.transactChunk(
    db.tx.users[userId].merge({
      'preferences': {
        'notifications': {
          'email': false, // Only update email, preserve push setting
        }
      }
    })
  );
  
  print('✅ Used merge operation for deep nested updates');

  // Example 6: String Pattern Matching
  print('\n🔎 Example 6: String Pattern Matching');
  
  final patternQuery = db.subscribeQuery({
    'users': {
      'where': {
        '\$or': [
          {'email': {'\$like': '%@gmail.com'}}, // Gmail users
          {'email': {'\$like': '%@company.com'}}, // Company users
        ],
        'name': {'\$ilike': '%smith%'}, // Case-insensitive name contains 'smith'
      }
    }
  });

  // Example 7: Array and Collection Operations
  print('\n📚 Example 7: Array Operations');
  
  // Query tasks with specific tags
  final taggedTasksQuery = db.subscribeQuery({
    'tasks': {
      'where': {
        'tags': {'\$contains': 'urgent'}, // Tasks containing 'urgent' tag
        'status': {'\$in': ['todo', 'in_progress']}, // Status in list
      }
    }
  });

  // Example 8: Null and Existence Checks
  print('\n✨ Example 8: Null and Existence Checks');
  
  final incompleteTasksQuery = db.subscribeQuery({
    'tasks': {
      'where': {
        'completedAt': {'\$isNull': true}, // Not completed yet
        'assignee': {'\$exists': true}, // Must have an assignee
        'tags': {'\$size': {'\$gt': 0}}, // Must have at least one tag
      }
    }
  });

  print('🎉 All examples completed! The new API provides:');
  print('  • Fluent tx namespace for transactions');
  print('  • Advanced query operators (\$gt, \$lt, \$like, \$ilike, etc.)');
  print('  • Lookup references by attributes');
  print('  • Deep merge operations');
  print('  • Complex logical queries (\$and, \$or, \$not)');
  print('  • String pattern matching');
  print('  • Array and collection operations');
  print('  • Null and existence checks');

  // Clean up
  await db.dispose();
}