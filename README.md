# InstantDB Flutter

A real-time, offline-first database client for Flutter with reactive bindings. This package provides a Flutter/Dart port of [InstantDB](https://instantdb.com), enabling you to build real-time, collaborative applications with ease.

## Features

- ✅ **Real-time synchronization** - Changes sync instantly across all connected clients
- ✅ **Offline-first** - Local SQLite storage with automatic sync when online
- ✅ **Reactive UI** - Widgets automatically update when data changes using Signals
- ✅ **Type-safe queries** - InstaQL query language with schema validation
- ✅ **Transactions** - Atomic operations with optimistic updates and rollback
- ✅ **Authentication** - Built-in user authentication and session management
- ✅ **Conflict resolution** - Automatic handling of concurrent data modifications
- ✅ **Flutter widgets** - Purpose-built reactive widgets for common patterns

## Quick Start

### 1. Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  instantdb_flutter: ^0.1.0
```

### 2. Initialize InstantDB

```dart
import 'package:instantdb_flutter/instantdb_flutter.dart';

// Initialize your database
final db = await InstantDB.init(
  appId: 'your-app-id', // Get this from instantdb.com
  config: const InstantConfig(
    syncEnabled: true,
  ),
);
```

### 3. Define Your Schema (Optional)

```dart
final todoSchema = Schema.object({
  'id': Schema.id(),
  'text': Schema.string(minLength: 1),
  'completed': Schema.boolean(),
  'createdAt': Schema.number(),
});

final schema = InstantSchemaBuilder()
  .addEntity('todos', todoSchema)
  .build();
```

### 4. Build Reactive UI

```dart
class TodoList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InstantProvider(
      db: db,
      child: InstantBuilderTyped<List<Map<String, dynamic>>>(
        query: {
          'todos': {
            'orderBy': {'createdAt': 'desc'},
          },
        },
        transformer: (data) => (data['todos'] as List).cast<Map<String, dynamic>>(),
        builder: (context, todos) {
          return ListView.builder(
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
              return ListTile(
                title: Text(todo['text']),
                leading: Checkbox(
                  value: todo['completed'],
                  onChanged: (value) => _toggleTodo(todo['id']),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

### 5. Perform Mutations

```dart
// Create a new todo - IMPORTANT: Always use db.id() for entity IDs
await db.transact([
  ...db.create('todos', {
    'id': db.id(), // Generates a proper UUID - required by InstantDB
    'text': 'Learn InstantDB Flutter',
    'completed': false,
    'createdAt': DateTime.now().millisecondsSinceEpoch,
  }),
]);

// Update a todo
await db.transact([
  db.update(todoId, {'completed': true}),
]);

// Delete a todo
await db.transact([
  db.delete(todoId),
]);
```

## Core Concepts

### Reactive Queries

InstantDB Flutter uses [Signals](https://pub.dev/packages/signals_flutter) for reactivity. Queries return `Signal<QueryResult>` objects that automatically update when underlying data changes.

```dart
// Simple query
final querySignal = db.query({
  'users': {
    'where': {'active': true},
  },
});

// Access the current value
final result = querySignal.value;
if (result.hasData) {
  final users = result.data!['users'];
}

// React to changes
Watch((context) {
  final result = querySignal.value;
  return Text('Users: ${result.data?['users']?.length ?? 0}');
});
```

### Transactions

All mutations happen within transactions, which provide atomicity and enable optimistic updates:

```dart
await db.transact([
  db.update(userId, {'name': 'New Name'}),
  ...db.create('posts', {
    'id': db.id(), // Always include UUID for new entities
    'title': 'Hello World',
    'authorId': userId,
  }),
]);
```

### Real-time Sync

When sync is enabled, changes are automatically synchronized across all connected clients:

```dart
// Enable sync during initialization
final db = await InstantDB.init(
  appId: 'your-app-id',
  config: const InstantConfig(
    syncEnabled: true,
  ),
);

// Monitor connection status
ConnectionStatusBuilder(
  builder: (context, isOnline) {
    return Icon(
      isOnline ? Icons.cloud_done : Icons.cloud_off,
    );
  },
)
```

### Presence System

InstantDB includes a real-time presence system for collaborative features:

```dart
// Update cursor position
await db.presence.updateCursor('room-id', x: 100, y: 200);

// Set typing indicator
await db.presence.setTyping('room-id', true);

// Send emoji reaction
await db.presence.sendReaction('room-id', '❤️', metadata: {
  'x': position.dx,
  'y': position.dy,
});

// Leave room (clears all presence data)
await db.presence.leaveRoom('room-id');

// Listen to presence updates
Watch((context) {
  final cursors = db.presence.getCursors('room-id').value;
  final typingUsers = db.presence.getTypingUsers('room-id').value;
  final reactions = db.presence.getReactions('room-id').value;
  
  return YourCollaborativeWidget(
    cursors: cursors,
    typingUsers: typingUsers, 
    reactions: reactions,
  );
});
```

## Widget Reference

### InstantProvider

Provides InstantDB instance to the widget tree:

```dart
InstantProvider(
  db: db,
  child: MyApp(),
)
```

### InstantBuilder

Generic reactive query widget:

```dart
InstantBuilder(
  query: {'todos': {}},
  builder: (context, data) => TodoList(todos: data['todos']),
  loadingBuilder: (context) => CircularProgressIndicator(),
  errorBuilder: (context, error) => Text('Error: $error'),
)
```

### InstantBuilderTyped

Type-safe reactive query widget:

```dart
InstantBuilderTyped<List<Todo>>(
  query: {'todos': {}},
  transformer: (data) => Todo.fromList(data['todos']),
  builder: (context, todos) => TodoList(todos: todos),
)
```

### AuthBuilder

Reactive authentication state widget:

```dart
AuthBuilder(
  builder: (context, user) {
    if (user != null) {
      return WelcomeScreen(user: user);
    } else {
      return LoginScreen();
    }
  },
)
```

## Query Language (InstaQL)

InstantDB uses a declarative query language similar to GraphQL:

```dart
// Basic query
{'users': {}}

// With conditions
{
  'users': {
    'where': {'active': true, 'role': 'admin'},
  }
}

// With ordering and limits
{
  'posts': {
    'orderBy': {'createdAt': 'desc'},
    'limit': 10,
    'offset': 20,
  }
}

// With relationships
{
  'users': {
    'include': {
      'posts': {
        'orderBy': {'createdAt': 'desc'},
        'limit': 5,
      },
    },
  }
}
```

## Authentication

InstantDB includes built-in authentication:

```dart
// Sign up
final user = await db.auth.signUp(
  email: 'user@example.com',
  password: 'password',
);

// Sign in
final user = await db.auth.signIn(
  email: 'user@example.com', 
  password: 'password',
);

// Sign out
await db.auth.signOut();

// Listen to auth state
db.auth.onAuthStateChange.listen((user) {
  if (user != null) {
    // User signed in
  } else {
    // User signed out
  }
});
```

## Schema Validation

Define and validate your data schemas:

```dart
final userSchema = Schema.object({
  'name': Schema.string(minLength: 1, maxLength: 100),
  'email': Schema.email(),
  'age': Schema.number(min: 0, max: 150),
  'posts': Schema.array(Schema.string()).optional(),
}, required: ['name', 'email']);

// Validate data
final isValid = userSchema.validate({
  'name': 'John Doe',
  'email': 'john@example.com',
  'age': 30,
});
```

## Example App

Check out the [example todo app](example/) for a complete demonstration of:
- Real-time synchronization between multiple instances
- Offline functionality with local persistence
- Reactive UI updates
- CRUD operations with transactions

To run the example:

```bash
cd example
flutter pub get
flutter run
```

## Testing

The package includes comprehensive tests. To run them:

```bash
flutter test
```

For integration testing with a real InstantDB instance, create a `.env` file:

```
INSTANTDB_API_ID=your-test-app-id
```

## Architecture

InstantDB Flutter is built on several key components:

- **Triple Store**: Local SQLite-based storage using the RDF triple model
- **Query Engine**: InstaQL parser and executor with reactive bindings
- **Sync Engine**: WebSocket-based real-time synchronization with conflict resolution
- **Transaction System**: Atomic operations with optimistic updates
- **Reactive Layer**: Signals-based reactivity for automatic UI updates

## Performance Tips

1. **Use specific queries**: Avoid querying all data when you only need a subset
2. **Implement pagination**: Use `limit` and `offset` for large datasets
3. **Cache management**: The package automatically manages query caches
4. **Dispose resources**: Properly dispose of InstantDB instances
5. **UUID Generation**: Always use `db.id()` for entity IDs to ensure server compatibility

```dart
// Good: Specific query with UUID
await db.transact([
  ...db.create('todos', {
    'id': db.id(), // Required UUID format
    'completed': false,
    'text': 'My todo',
  }),
]);

{'todos': {'where': {'completed': false}, 'limit': 20}}

// Avoid: Querying everything or custom IDs
{'todos': {}}

// Avoid: Custom string IDs (will cause server errors)
'id': 'my-custom-id' // ❌ Invalid - not a UUID
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- 📖 [Documentation](https://instantdb.com/docs)
- 💬 [Discord Community](https://discord.gg/instantdb)
- 🐛 [Issue Tracker](https://github.com/instantdb/instantdb-flutter/issues)
- 📧 [Email Support](mailto:support@instantdb.com)

## Acknowledgments

- [InstantDB](https://instantdb.com) - The original JavaScript implementation
- [Signals Flutter](https://pub.dev/packages/signals_flutter) - Reactive state management
- [SQLite](https://sqlite.org) - Local data persistence
