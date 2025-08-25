# Advanced Features Guide

This guide covers the advanced features available in InstantDB Flutter that provide feature parity with the InstantDB React/JS SDK.

## Transaction System (tx namespace)

The new `tx` namespace provides a fluent API for building transactions that's more intuitive and closely matches the React SDK.

### Basic Operations

```dart
// Create a new entity
final todoId = db.id();
await db.transactChunk(
  db.tx['todos'][todoId].update({
    'text': 'Learn InstantDB',
    'completed': false,
    'createdAt': DateTime.now().millisecondsSinceEpoch,
  })
);

// Update an existing entity
await db.transactChunk(
  db.tx['todos'][todoId].update({
    'completed': true,
    'completedAt': DateTime.now().millisecondsSinceEpoch,
  })
);
```

### Advanced Operations

```dart
// Deep merge for nested updates
await db.transactChunk(
  db.tx['users'][userId].merge({
    'preferences': {
      'theme': 'dark',
      'notifications': {
        'email': false, // Only updates email, preserves other notification settings
      }
    }
  })
);

// Link entities together
final userId = db.id();
final postId = db.id();

await db.transactChunk(
  db.tx['users'][userId]
    .update({'name': 'Alice'})
    .link({'posts': [postId]})
);

await db.transactChunk(
  db.tx['posts'][postId].update({
    'title': 'My first post',
    'content': 'Hello world!',
  })
);
```

### Lookup References

Reference entities by attributes instead of IDs:

```dart
// Reference a user by email instead of ID
await db.transactChunk(
  db.tx['tasks'][taskId].update({
    'title': 'Review document',
    'assignee': lookup('users', 'email', 'alice@company.com'),
    'priority': 'high',
  })
);

// Multiple lookups in complex queries
final tasksQuery = db.subscribeQuery({
  'tasks': {
    'where': {
      'assignee': lookup('users', 'email', 'alice@company.com'),
      'project': lookup('projects', 'name', 'Website Redesign'),
    }
  }
});
```

## Advanced Query Operators

### Comparison Operators

```dart
final advancedQuery = db.subscribeQuery({
  'users': {
    'where': {
      // Numeric comparisons
      'age': {'\$gte': 18, '\$lt': 65},
      'salary': {'\$gt': 50000, '\$lte': 200000},
      'loginCount': {'\$ne': 0},
      
      // Date comparisons
      'createdAt': {
        '\$gte': DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch
      },
    }
  }
});
```

### String Pattern Matching

```dart
final userQuery = db.subscribeQuery({
  'users': {
    'where': {
      // Case-sensitive pattern matching
      'email': {'\$like': '%@company.com'},
      
      // Case-insensitive pattern matching
      'name': {'\$ilike': '%john%'},
      
      // Starts with pattern
      'username': {'\$like': 'admin_%'},
      
      // Multiple patterns
      '\$or': [
        {'email': {'\$like': '%@gmail.com'}},
        {'email': {'\$like': '%@company.com'}},
      ]
    }
  }
});
```

### Array and Collection Operations

```dart
final collectionQuery = db.subscribeQuery({
  'users': {
    'where': {
      // Array contains specific value
      'tags': {'\$contains': 'vip'},
      
      // Array size constraints
      'skills': {'\$size': {'\$gte': 3}},
      
      // Value in array
      'role': {'\$in': ['admin', 'moderator', 'editor']},
      
      // Value not in array
      'status': {'\$nin': ['banned', 'suspended']},
    }
  }
});
```

### Existence and Null Checks

```dart
final existenceQuery = db.subscribeQuery({
  'users': {
    'where': {
      // Field exists (not null or undefined)
      'profilePicture': {'\$exists': true},
      
      // Field is null
      'deletedAt': {'\$isNull': true},
      
      // Field is not null
      'lastLoginAt': {'\$exists': true, '\$isNull': false},
    }
  }
});
```

### Complex Logical Operations

```dart
final complexQuery = db.subscribeQuery({
  'tasks': {
    'where': {
      '\$and': [
        // Must be active and not deleted
        {'status': 'active'},
        {'deletedAt': {'\$isNull': true}},
        
        // Either high priority OR due soon
        {'\$or': [
          {'priority': 'high'},
          {'dueDate': {'\$lt': DateTime.now().add(Duration(days: 3)).millisecondsSinceEpoch}},
        ]},
        
        // Must have assignee
        {'assignee': {'\$exists': true}},
        
        // Must not be in these categories
        {'category': {'\$nin': ['archived', 'template']}},
      ]
    }
  }
});
```

## Room-based Presence System

### Joining Rooms

```dart
// Join a room with initial presence data
final room = db.presence.joinRoom('project-room', initialPresence: {
  'username': 'Alice',
  'status': 'online',
  'role': 'designer',
});

// Multiple rooms for different contexts
final chatRoom = db.presence.joinRoom('chat');
final canvasRoom = db.presence.joinRoom('design-canvas');
```

### Room-scoped Operations

```dart
// All operations are automatically scoped to the room
await room.setPresence({
  'status': 'busy',
  'currentTask': 'reviewing designs',
});

await room.updateCursor(
  x: 150, 
  y: 200,
  userName: 'Alice',
  userColor: '#ff0000',
);

await room.setTyping(true);

await room.sendReaction('👍', metadata: {
  'elementId': 'button-primary',
  'comment': 'Love this design!',
});
```

### Topic-based Messaging

```dart
// Publish messages to specific topics
await room.publishTopic('design-updates', {
  'type': 'element-moved',
  'elementId': 'logo',
  'position': {'x': 100, 'y': 50},
  'userId': 'alice',
});

await room.publishTopic('chat', {
  'message': 'What do you think about the new layout?',
  'userId': 'alice',
  'timestamp': DateTime.now().millisecondsSinceEpoch,
});

// Subscribe to topic updates
room.subscribeTopic('design-updates').listen((data) {
  if (data['type'] == 'element-moved') {
    updateElementPosition(data['elementId'], data['position']);
  }
});

room.subscribeTopic('chat').listen((data) {
  addChatMessage(data['message'], data['userId']);
});
```

### Reactive Room Updates

```dart
Watch((context) {
  // All room data updates reactively
  final presence = room.getPresence().value;
  final cursors = room.getCursors().value;
  final typing = room.getTyping().value;
  final reactions = room.getReactions().value;
  
  return CollaborativeCanvas(
    users: presence.values.toList(),
    cursors: cursors.values.toList(),
    typingUsers: typing.keys.toSet(),
    reactions: reactions,
  );
});
```

### Room Isolation

```dart
// Each room maintains completely separate state
final designRoom = db.presence.joinRoom('design-workspace');
final meetingRoom = db.presence.joinRoom('video-call');

// These operations don't interfere with each other
designRoom.updateCursor(x: 100, y: 200);
meetingRoom.setPresence({'micMuted': true});

// Topics are isolated per room
designRoom.publishTopic('canvas-updates', {...});
meetingRoom.publishTopic('canvas-updates', {...}); // Different topic stream
```

## API Migration Guide

### From Old APIs to New APIs

```dart
// OLD: Direct room ID approach
db.presence.updateCursor('room-1', x: 100, y: 200);
db.presence.setTyping('room-1', true);
final cursors = db.presence.getCursors('room-1').value;

// NEW: Room-scoped approach (recommended)
final room = db.presence.joinRoom('room-1');
room.updateCursor(x: 100, y: 200);
room.setTyping(true);
final cursors = room.getCursors().value;

// OLD: Traditional transactions
await db.transact([
  ...db.create('todos', {'id': db.id(), 'text': 'Learn'}),
]);

// NEW: tx namespace (recommended)
final todoId = db.id();
await db.transactChunk(
  db.tx['todos'][todoId].update({'text': 'Learn'})
);

// OLD: Basic query method
final query = db.query({'users': {}});

// NEW: Explicit subscription method (recommended)
final query = db.subscribeQuery({'users': {}});

// NEW: One-time queries
final result = await db.queryOnce({'users': {}});
```

### Backward Compatibility

All old APIs continue to work alongside the new ones:

```dart
// Mix old and new approaches as needed
final room = db.presence.joinRoom('room-1'); // New
await db.transact([db.delete(oldId)]); // Old
final query = db.subscribeQuery({'users': {}}); // New

// Gradually migrate to new APIs at your own pace
```

## Performance Considerations

### Query Optimization

```dart
// Efficient: Specific queries with limits
final recentPosts = db.subscribeQuery({
  'posts': {
    'where': {'published': true},
    'orderBy': {'createdAt': 'desc'},
    'limit': 20,
  }
});

// Efficient: Use advanced operators to filter data server-side
final activeUsers = db.subscribeQuery({
  'users': {
    'where': {
      'lastSeenAt': {'\$gte': DateTime.now().subtract(Duration(days: 7)).millisecondsSinceEpoch},
      'status': {'\$ne': 'banned'},
    }
  }
});
```

### Room Management

```dart
// Efficient: Join rooms only when needed
class CollaborativeWidget extends StatefulWidget {
  @override
  _CollaborativeWidgetState createState() => _CollaborativeWidgetState();
}

class _CollaborativeWidgetState extends State<CollaborativeWidget> {
  InstantRoom? room;
  
  @override
  void initState() {
    super.initState();
    // Join room when widget is created
    final db = context.read<InstantDB>();
    room = db.presence.joinRoom(widget.roomId);
  }
  
  @override
  void dispose() {
    // Clean up room resources
    final db = context.read<InstantDB>();
    db.presence.leaveRoom(widget.roomId);
    super.dispose();
  }
}
```

### Transaction Batching

```dart
// Efficient: Batch related operations
await db.transactChunk(
  db.tx['projects'][projectId]
    .update({'name': 'Updated Project'})
    .merge({'metadata': {'lastModified': DateTime.now().millisecondsSinceEpoch}})
    .link({'collaborators': [userId1, userId2]})
);

// Less efficient: Multiple separate transactions
await db.transactChunk(db.tx['projects'][projectId].update({'name': 'Updated Project'}));
await db.transactChunk(db.tx['projects'][projectId].merge({'metadata': {...}}));
await db.transactChunk(db.tx['projects'][projectId].link({'collaborators': [...]}));
```

## Error Handling

### Transaction Errors

```dart
try {
  await db.transactChunk(
    db.tx['users'][userId].update({
      'email': 'new-email@example.com',
    })
  );
} catch (e) {
  if (e is ValidationError) {
    // Handle validation errors
    showError('Invalid email format');
  } else if (e is NetworkError) {
    // Handle network errors
    showError('Connection failed, changes saved locally');
  } else {
    // Handle other errors
    showError('Update failed: $e');
  }
}
```

### Query Errors

```dart
final querySignal = db.subscribeQuery({
  'users': {
    'where': {'invalid_field': 'value'}
  }
});

Watch((context) {
  final result = querySignal.value;
  
  if (result.isLoading) {
    return CircularProgressIndicator();
  }
  
  if (result.hasError) {
    return Text('Query error: ${result.error}');
  }
  
  // Handle data
  final users = result.data!['users'];
  return UserList(users: users);
});
```

### Presence System Errors

```dart
try {
  final room = db.presence.joinRoom('room-id');
  await room.setPresence({'status': 'online'});
} catch (e) {
  // Presence operations are non-critical
  // Log error but don't block UI
  print('Presence update failed: $e');
}
```

## Testing Advanced Features

### Testing Transactions

```dart
test('should create and link entities with tx API', () async {
  final db = await InstantDB.init(appId: 'test');
  
  final userId = db.id();
  final postId = db.id();
  
  await db.transactChunk(
    db.tx['users'][userId].update({'name': 'Alice'})
  );
  
  await db.transactChunk(
    db.tx['posts'][postId]
      .update({'title': 'Hello World'})
      .link({'author': userId})
  );
  
  final result = await db.queryOnce({
    'posts': {
      'include': {'author': {}}
    }
  });
  
  expect(result.data!['posts'][0]['author']['name'], equals('Alice'));
});
```

### Testing Advanced Queries

```dart
test('should filter with advanced operators', () async {
  final db = await InstantDB.init(appId: 'test');
  
  // Create test data
  await db.transact([
    ...db.create('users', {'id': db.id(), 'age': 25, 'email': 'john@company.com'}),
    ...db.create('users', {'id': db.id(), 'age': 30, 'email': 'alice@gmail.com'}),
    ...db.create('users', {'id': db.id(), 'age': 17, 'email': 'bob@company.com'}),
  ]);
  
  final result = await db.queryOnce({
    'users': {
      'where': {
        'age': {'\$gte': 18},
        'email': {'\$like': '%@company.com'},
      }
    }
  });
  
  expect(result.data!['users'], hasLength(2));
});
```

### Testing Room-based Presence

```dart
test('should isolate presence between rooms', () async {
  final db = await InstantDB.init(appId: 'test');
  
  final room1 = db.presence.joinRoom('room-1');
  final room2 = db.presence.joinRoom('room-2');
  
  await room1.setPresence({'status': 'room1-status'});
  await room2.setPresence({'status': 'room2-status'});
  
  final presence1 = room1.getPresence().value;
  final presence2 = room2.getPresence().value;
  
  expect(presence1, isNot(equals(presence2)));
});
```