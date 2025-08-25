# Migration Guide: Upgrading to Modern InstantDB APIs

This guide helps you migrate from the older InstantDB Flutter APIs to the new modern APIs that provide full feature parity with the InstantDB React/JS SDK.

## Overview

The new APIs provide:
- ✅ **Fluent transaction system** with `tx` namespace
- ✅ **Advanced query operators** for complex filtering
- ✅ **Room-based presence system** for better organization
- ✅ **Topic pub/sub messaging** within rooms
- ✅ **Lookup references** by attributes instead of IDs
- ✅ **Deep merge operations** for nested updates
- ✅ **Improved method naming** matching React SDK conventions

**Important**: All old APIs remain fully functional. You can migrate incrementally at your own pace.

## Breaking Changes

**None!** This is a fully backward-compatible upgrade. All existing code continues to work without modification.

## New Features Migration

### 1. Transaction System (tx namespace)

**Before:**
```dart
// Old transaction approach
await db.transact([
  ...db.create('todos', {
    'id': db.id(),
    'text': 'Learn InstantDB',
    'completed': false,
  }),
]);

await db.transact([
  db.update(todoId, {'completed': true}),
]);
```

**After (Recommended):**
```dart
// New tx namespace approach
final todoId = db.id();
await db.transactChunk(
  db.tx['todos'][todoId].update({
    'text': 'Learn InstantDB',
    'completed': false,
  })
);

await db.transactChunk(
  db.tx['todos'][todoId].update({'completed': true})
);
```

**Benefits:**
- More intuitive syntax
- Better IDE support and autocompletion
- Chainable operations
- Matches React SDK patterns

### 2. Query Method Names

**Before:**
```dart
// Old query method
final querySignal = db.query({'users': {}});
```

**After (Recommended):**
```dart
// New explicit method names
final querySignal = db.subscribeQuery({'users': {}}); // For reactive queries
final result = await db.queryOnce({'users': {}}); // For one-time queries
```

**Benefits:**
- Clearer intent (subscription vs one-time)
- Matches React SDK naming
- Better API discoverability

### 3. Presence System

**Before:**
```dart
// Old direct room ID approach
await db.presence.updateCursor('room-id', x: 100, y: 200);
await db.presence.setTyping('room-id', true);
await db.presence.sendReaction('room-id', '❤️');

Watch((context) {
  final cursors = db.presence.getCursors('room-id').value;
  final typing = db.presence.getTyping('room-id').value;
  return MyWidget(cursors: cursors, typing: typing);
});
```

**After (Recommended):**
```dart
// New room-based approach
final room = db.presence.joinRoom('room-id');

await room.updateCursor(x: 100, y: 200);
await room.setTyping(true);
await room.sendReaction('❤️');

Watch((context) {
  final cursors = room.getCursors().value;
  final typing = room.getTyping().value;
  return MyWidget(cursors: cursors, typing: typing);
});
```

**Benefits:**
- Better organization and scoping
- Topic-based messaging support
- Cleaner API surface
- Room isolation

### 4. Authentication Helpers

**Before:**
```dart
// Old approach - accessing auth state
final user = db.auth.currentUser.value;
```

**After (New convenience methods):**
```dart
// New convenience methods
final user = db.getAuth(); // One-time check
final userSignal = db.subscribeAuth(); // Reactive updates

// Use in widgets
Watch((context) {
  final user = db.subscribeAuth().value;
  return user != null ? WelcomeWidget() : LoginWidget();
});
```

## Advanced Features Migration

### Deep Merge Operations

**New Feature:**
```dart
// Deep merge for nested object updates
await db.transactChunk(
  db.tx['users'][userId].merge({
    'preferences': {
      'theme': 'dark',
      'notifications': {
        'email': false, // Only updates email setting
      }
    }
  })
);
```

This preserves other nested fields that aren't specified in the merge operation.

### Advanced Query Operators

**New Feature:**
```dart
// Advanced filtering with new operators
final advancedQuery = db.subscribeQuery({
  'users': {
    'where': {
      // Comparison operators
      'age': {'\$gte': 18, '\$lt': 65},
      'salary': {'\$gt': 50000},
      
      // String pattern matching
      'email': {'\$like': '%@company.com'},
      'name': {'\$ilike': '%john%'}, // Case insensitive
      
      // Array operations
      'tags': {'\$contains': 'vip'},
      'skills': {'\$size': {'\$gte': 3}},
      
      // Existence checks
      'profilePicture': {'\$exists': true},
      'deletedAt': {'\$isNull': true},
      
      // Complex logic
      '\$and': [
        {'status': 'active'},
        {'\$or': [
          {'department': 'engineering'},
          {'department': 'design'}
        ]}
      ]
    }
  }
});
```

### Lookup References

**New Feature:**
```dart
// Reference entities by attributes instead of IDs
await db.transactChunk(
  db.tx['tasks'][taskId].update({
    'assignee': lookup('users', 'email', 'alice@company.com'),
    'project': lookup('projects', 'name', 'Website Redesign'),
  })
);
```

### Topic-based Messaging

**New Feature:**
```dart
final room = db.presence.joinRoom('project-room');

// Publish messages to specific topics
await room.publishTopic('design-updates', {
  'type': 'element-moved',
  'elementId': 'logo',
  'position': {'x': 100, 'y': 50},
});

// Subscribe to topic updates
room.subscribeTopic('design-updates').listen((data) {
  handleDesignUpdate(data);
});

room.subscribeTopic('chat-messages').listen((data) {
  handleChatMessage(data);
});
```

## Incremental Migration Strategy

### Phase 1: New Projects
Start using the new APIs for all new code:

```dart
class NewFeature extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Use new APIs for new features
    return InstantBuilderTyped<List<Task>>(
      query: {
        'tasks': {
          'where': {
            'status': {'\$ne': 'completed'},
            'dueDate': {'\$gte': DateTime.now().millisecondsSinceEpoch},
          }
        }
      },
      transformer: (data) => Task.fromList(data['tasks']),
      builder: (context, tasks) => TaskList(tasks: tasks),
    );
  }
}
```

### Phase 2: Update High-Traffic Areas
Migrate heavily used code paths to benefit from performance improvements:

```dart
// High-traffic query - migrate to new API
class UserDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // OLD: db.query({'users': {}})
    // NEW: More specific and efficient
    return InstantBuilderTyped<List<User>>(
      query: {
        'users': {
          'where': {'status': 'active'},
          'orderBy': {'lastLoginAt': 'desc'},
          'limit': 50,
        }
      },
      transformer: (data) => User.fromList(data['users']),
      builder: (context, users) => UserGrid(users: users),
    );
  }
}
```

### Phase 3: Collaborative Features
Migrate presence/collaboration features to the room-based API:

```dart
class CollaborativeEditor extends StatefulWidget {
  final String documentId;
  
  @override
  _CollaborativeEditorState createState() => _CollaborativeEditorState();
}

class _CollaborativeEditorState extends State<CollaborativeEditor> {
  InstantRoom? room;
  
  @override
  void initState() {
    super.initState();
    // Migrate from old direct room API to new room-scoped API
    final db = context.read<InstantDB>();
    room = db.presence.joinRoom('doc-${widget.documentId}');
  }
  
  void _updateCursor(Offset position) {
    // OLD: db.presence.updateCursor('doc-${widget.documentId}', ...)
    // NEW: room-scoped approach
    room?.updateCursor(x: position.dx, y: position.dy);
  }
  
  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      // OLD: db.presence.getCursors('doc-${widget.documentId}').value
      // NEW: room-scoped approach
      final cursors = room?.getCursors().value ?? {};
      return EditorCanvas(cursors: cursors);
    });
  }
}
```

### Phase 4: Complete Migration (Optional)
Optionally migrate remaining code for consistency:

```dart
// Migrate simple transactions to tx API for consistency
class TodoActions {
  final InstantDB db;
  
  TodoActions(this.db);
  
  Future<void> createTodo(String text) async {
    // OLD: db.transact([...db.create('todos', {...})])
    // NEW: tx namespace
    final todoId = db.id();
    await db.transactChunk(
      db.tx['todos'][todoId].update({
        'text': text,
        'completed': false,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      })
    );
  }
}
```

## Testing Your Migration

### Before Migration
```dart
test('old API test', () async {
  final db = await InstantDB.init(appId: 'test');
  
  await db.transact([
    ...db.create('users', {'id': db.id(), 'name': 'Alice'}),
  ]);
  
  final query = db.query({'users': {}});
  final result = query.value;
  expect(result.data!['users'], hasLength(1));
});
```

### After Migration
```dart
test('new API test', () async {
  final db = await InstantDB.init(appId: 'test');
  
  final userId = db.id();
  await db.transactChunk(
    db.tx['users'][userId].update({'name': 'Alice'})
  );
  
  final result = await db.queryOnce({'users': {}});
  expect(result.data!['users'], hasLength(1));
  
  // Test advanced operators
  final filteredResult = await db.queryOnce({
    'users': {
      'where': {'name': {'\$like': 'A%'}}
    }
  });
  expect(filteredResult.data!['users'], hasLength(1));
});
```

## Performance Benefits

### Query Performance
```dart
// OLD: Less efficient broad queries
final allUsers = db.query({'users': {}});

// NEW: More efficient specific queries
final activeUsers = db.subscribeQuery({
  'users': {
    'where': {
      'status': 'active',
      'lastSeenAt': {'\$gte': DateTime.now().subtract(Duration(days: 7)).millisecondsSinceEpoch}
    },
    'limit': 50,
  }
});
```

### Transaction Performance
```dart
// OLD: Multiple separate transactions
await db.transact([db.update(id, {'field1': 'value1'})]);
await db.transact([db.update(id, {'field2': 'value2'})]);

// NEW: Batched operations
await db.transactChunk(
  db.tx['entity'][id]
    .update({'field1': 'value1'})
    .merge({'field2': 'value2'})
);
```

### Presence Performance
```dart
// OLD: Multiple room ID lookups
db.presence.getCursors('room-1').value;
db.presence.getTyping('room-1').value;
db.presence.getReactions('room-1').value;

// NEW: Scoped room access
final room = db.presence.joinRoom('room-1');
room.getCursors().value;
room.getTyping().value;
room.getReactions().value;
```

## Common Pitfalls

### 1. Don't Mix Old and New Transaction Styles
```dart
// AVOID: Mixing transaction styles
await db.transact([
  db.tx['users'][id].update({'name': 'Alice'}), // ❌ Wrong - tx operations in old transact
]);

// CORRECT: Use consistent API
await db.transactChunk(
  db.tx['users'][id].update({'name': 'Alice'}) // ✅ Correct
);
```

### 2. Remember to Import lookup Function
```dart
// Add to your imports when using lookup references
import 'package:instantdb_flutter/instantdb_flutter.dart'; // lookup is included
```

### 3. Room Lifecycle Management
```dart
// AVOID: Not cleaning up rooms
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final room = db.presence.joinRoom('room-1'); // ❌ Creates new room each build
    return Container();
  }
}

// CORRECT: Proper room lifecycle
class MyWidget extends StatefulWidget {
  @override
  _MyWidgetState createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  InstantRoom? room;
  
  @override
  void initState() {
    super.initState();
    room = db.presence.joinRoom('room-1'); // ✅ Create once
  }
  
  @override
  void dispose() {
    db.presence.leaveRoom('room-1'); // ✅ Clean up
    super.dispose();
  }
}
```

## Support and Resources

- **Documentation**: See `ADVANCED_FEATURES.md` for detailed API documentation
- **Examples**: Check the updated example app showcasing all new features
- **Migration Support**: All old APIs remain functional - migrate at your own pace
- **Issues**: Report any migration issues on the GitHub repository

## Summary

The new InstantDB Flutter APIs provide significant improvements:

- 🚀 **Better Performance** - More efficient queries and transactions
- 🎯 **Improved Developer Experience** - Cleaner, more intuitive APIs
- 🔧 **Advanced Features** - Complex queries, room-based presence, topic messaging
- 🔄 **Full Compatibility** - Works alongside existing code
- 📱 **React SDK Parity** - Consistent experience across platforms

Start with new features and high-traffic areas, then gradually migrate the rest of your codebase when convenient.