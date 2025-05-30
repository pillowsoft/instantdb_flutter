# InstantDB Flutter Port - Implementation Guide

## Table of Contents
1. [Overview](#overview)
2. [Architecture Design](#architecture-design)
3. [Core Components](#core-components)
4. [Implementation Steps](#implementation-steps)
5. [API Design](#api-design)
6. [Code Examples](#code-examples)
7. [Testing Strategy](#testing-strategy)
8. [Migration Guide](#migration-guide)

## Overview

This guide details how to port InstantDB's React SDK to Flutter, creating a real-time, offline-first database with reactive bindings. The implementation leverages:

- **Acanthis** for schema validation and code generation
- **Signals** for reactive state management
- **Dio** for HTTP/REST communication
- **SQLite** (via sqflite) for local persistence
- **WebSocket** for real-time synchronization

### Key Features to Implement
- Local-first triple store database
- Real-time synchronization
- Optimistic updates with automatic rollback
- Offline support with conflict resolution
- Type-safe queries via code generation
- Reactive Flutter widgets

## Architecture Design

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App                           │
├─────────────────────────────────────────────────────────┤
│                 InstantDB Flutter SDK                    │
├─────────────┬─────────────┬─────────────┬──────────────┤
│   Reactive  │   Query     │    Sync     │   Storage    │
│    Layer    │   Engine    │   Engine    │    Layer     │
│  (Signals)  │ (InstaQL)   │(WebSocket)  │  (SQLite)    │
└─────────────┴─────────────┴─────────────┴──────────────┘
```

### Core Module Structure

```
instant_flutter/
├── lib/
│   ├── src/
│   │   ├── core/
│   │   │   ├── instant_db.dart
│   │   │   ├── config.dart
│   │   │   └── types.dart
│   │   ├── schema/
│   │   │   ├── schema.dart
│   │   │   ├── validation.dart
│   │   │   └── builder.dart
│   │   ├── query/
│   │   │   ├── engine.dart
│   │   │   ├── parser.dart
│   │   │   └── builder.dart
│   │   ├── storage/
│   │   │   ├── triple_store.dart
│   │   │   ├── sqlite_adapter.dart
│   │   │   └── cache_manager.dart
│   │   ├── sync/
│   │   │   ├── sync_engine.dart
│   │   │   ├── websocket_client.dart
│   │   │   └── conflict_resolver.dart
│   │   ├── reactive/
│   │   │   ├── instant_query.dart
│   │   │   ├── instant_builder.dart
│   │   │   └── hooks.dart
│   │   └── auth/
│   │       ├── auth_manager.dart
│   │       └── token_storage.dart
│   ├── instant_flutter.dart
│   └── instant_flutter_widgets.dart
├── test/
├── example/
└── pubspec.yaml
```

## Core Components

### 1. Schema Definition with Acanthis

```dart
// lib/src/schema/schema.dart
import 'package:acanthis/acanthis.dart';

/// Base class for all InstantDB entities
abstract class InstantEntity {
  String get id;
  int get createdAt;
  int get updatedAt;
}

/// Schema builder for InstantDB
class InstantSchemaBuilder {
  final Map<String, ZodSchema> entities = {};
  final Map<String, Link> links = {};

  InstantSchemaBuilder addEntity(String name, ZodSchema schema) {
    // Ensure required fields
    final enhancedSchema = schema.merge(z.object({
      'id': z.string(),
      'createdAt': z.number(),
      'updatedAt': z.number(),
    }));

    entities[name] = enhancedSchema;
    return this;
  }

  InstantSchemaBuilder addLink(String name, Link link) {
    links[name] = link;
    return this;
  }

  InstantSchema build() {
    return InstantSchema(entities: entities, links: links);
  }
}

/// Represents a relationship between entities
class Link {
  final EntityRef from;
  final EntityRef to;
  final LinkType type;

  Link({
    required this.from,
    required this.to,
    this.type = LinkType.oneToMany,
  });
}

enum LinkType { oneToOne, oneToMany, manyToMany }

class EntityRef {
  final String entity;
  final String field;

  EntityRef(this.entity, this.field);
}
```

### 2. Triple Store Implementation

```dart
// lib/src/storage/triple_store.dart
import 'package:sqflite/sqflite.dart';

/// Core triple store that holds all data
class TripleStore {
  final Database _db;
  final _changeController = StreamController<TripleChange>.broadcast();

  Stream<TripleChange> get changes => _changeController.stream;

  TripleStore(this._db);

  /// Initialize the triple store schema
  static Future<TripleStore> init(String dbPath) async {
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE triples (
            entity_id TEXT NOT NULL,
            attribute TEXT NOT NULL,
            value TEXT NOT NULL,
            tx_id INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            retracted BOOLEAN DEFAULT FALSE,
            PRIMARY KEY (entity_id, attribute, value, tx_id)
          )
        ''');

        await db.execute('''
          CREATE INDEX idx_entity ON triples(entity_id);
        ''');

        await db.execute('''
          CREATE INDEX idx_attribute ON triples(attribute);
        ''');

        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            status TEXT NOT NULL,
            synced BOOLEAN DEFAULT FALSE
          )
        ''');
      },
    );

    return TripleStore(db);
  }

  /// Add a triple to the store
  Future<void> addTriple(Triple triple, int txId) async {
    await _db.insert('triples', {
      'entity_id': triple.entityId,
      'attribute': triple.attribute,
      'value': triple.value,
      'tx_id': txId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'retracted': false,
    });

    _changeController.add(TripleChange(
      type: ChangeType.add,
      triple: triple,
      txId: txId,
    ));
  }

  /// Retract a triple (soft delete)
  Future<void> retractTriple(Triple triple, int txId) async {
    await _db.update(
      'triples',
      {'retracted': true},
      where: 'entity_id = ? AND attribute = ? AND value = ?',
      whereArgs: [triple.entityId, triple.attribute, triple.value],
    );

    _changeController.add(TripleChange(
      type: ChangeType.retract,
      triple: triple,
      txId: txId,
    ));
  }

  /// Query triples by entity ID
  Future<List<Triple>> queryByEntity(String entityId) async {
    final results = await _db.query(
      'triples',
      where: 'entity_id = ? AND retracted = FALSE',
      whereArgs: [entityId],
    );

    return results.map((row) => Triple.fromMap(row)).toList();
  }
}

class Triple {
  final String entityId;
  final String attribute;
  final dynamic value;

  Triple({
    required this.entityId,
    required this.attribute,
    required this.value,
  });

  factory Triple.fromMap(Map<String, dynamic> map) {
    return Triple(
      entityId: map['entity_id'],
      attribute: map['attribute'],
      value: jsonDecode(map['value']),
    );
  }
}
```

### 3. Query Engine

```dart
// lib/src/query/engine.dart
import 'package:signals/signals.dart';

/// InstaQL query engine
class QueryEngine {
  final TripleStore _store;
  final Map<String, Signal<QueryResult>> _queryCache = {};

  QueryEngine(this._store) {
    // Listen to store changes and update queries
    _store.changes.listen(_handleStoreChange);
  }

  /// Execute an InstaQL query
  Signal<QueryResult> query(Map<String, dynamic> query) {
    final queryKey = _generateQueryKey(query);

    // Return cached query if exists
    if (_queryCache.containsKey(queryKey)) {
      return _queryCache[queryKey]!;
    }

    // Create new reactive query
    final resultSignal = signal(QueryResult.loading());
    _queryCache[queryKey] = resultSignal;

    // Execute query
    _executeQuery(query, resultSignal);

    return resultSignal;
  }

  Future<void> _executeQuery(
    Map<String, dynamic> query,
    Signal<QueryResult> resultSignal,
  ) async {
    try {
      final result = await _processQuery(query);
      resultSignal.value = QueryResult.success(result);
    } catch (e) {
      resultSignal.value = QueryResult.error(e.toString());
    }
  }

  Future<Map<String, dynamic>> _processQuery(Map<String, dynamic> query) async {
    final results = <String, dynamic>{};

    for (final entry in query.entries) {
      final entityType = entry.key;
      final entityQuery = entry.value as Map<String, dynamic>;

      // Get all entities of this type
      final entities = await _queryEntities(entityType, entityQuery);
      results[entityType] = entities;
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> _queryEntities(
    String entityType,
    Map<String, dynamic> query,
  ) async {
    // This is simplified - real implementation would:
    // 1. Parse where clauses
    // 2. Handle nested queries
    // 3. Apply filters and sorting

    final entities = <Map<String, dynamic>>[];

    // Get all entity IDs for this type
    final entityIds = await _store.queryEntityIdsByType(entityType);

    for (final entityId in entityIds) {
      final triples = await _store.queryByEntity(entityId);
      final entity = _triplestoEntity(triples);

      // Process nested queries
      for (final nestedEntry in query.entries) {
        if (nestedEntry.value is Map) {
          // Recursively process nested queries
          final nestedResults = await _queryEntities(
            nestedEntry.key,
            nestedEntry.value as Map<String, dynamic>,
          );
          entity[nestedEntry.key] = nestedResults;
        }
      }

      entities.add(entity);
    }

    return entities;
  }

  void _handleStoreChange(TripleChange change) {
    // Invalidate affected queries
    for (final entry in _queryCache.entries) {
      if (_queryAffectedByChange(entry.key, change)) {
        // Re-execute query
        _executeQuery(
          _parseQueryKey(entry.key),
          entry.value,
        );
      }
    }
  }
}

class QueryResult {
  final bool isLoading;
  final Map<String, dynamic>? data;
  final String? error;

  QueryResult._({
    required this.isLoading,
    this.data,
    this.error,
  });

  factory QueryResult.loading() => QueryResult._(isLoading: true);
  factory QueryResult.success(Map<String, dynamic> data) => QueryResult._(
    isLoading: false,
    data: data,
  );
  factory QueryResult.error(String error) => QueryResult._(
    isLoading: false,
    error: error,
  );
}
```

### 4. Sync Engine

```dart
// lib/src/sync/sync_engine.dart
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:dio/dio.dart';

class SyncEngine {
  final String appId;
  final String? authToken;
  final TripleStore _store;
  final Dio _dio;

  WebSocketChannel? _channel;
  StreamSubscription? _storeSubscription;
  final _syncQueue = Queue<Transaction>();
  bool _isOnline = true;

  SyncEngine({
    required this.appId,
    required TripleStore store,
    this.authToken,
  }) : _store = store,
       _dio = Dio(BaseOptions(
         baseUrl: 'https://api.instantdb.com',
         headers: {'X-App-ID': appId},
       ));

  /// Initialize sync engine and establish connection
  Future<void> init() async {
    // Check connectivity
    await _checkConnectivity();

    if (_isOnline) {
      await _connectWebSocket();
    }

    // Listen to store changes
    _storeSubscription = _store.changes.listen(_handleLocalChange);

    // Process any pending transactions
    await _processPendingTransactions();
  }

  Future<void> _connectWebSocket() async {
    final uri = Uri.parse('wss://sync.instantdb.com/v1/sync');
    _channel = WebSocketChannel.connect(uri);

    // Send auth
    _channel!.sink.add(jsonEncode({
      'type': 'auth',
      'appId': appId,
      'token': authToken,
    }));

    // Listen for messages
    _channel!.stream.listen(
      _handleRemoteMessage,
      onError: _handleWebSocketError,
      onDone: _handleWebSocketClose,
    );
  }

  /// Send a transaction to the server
  Future<TransactionResult> sendTransaction(Transaction tx) async {
    if (!_isOnline) {
      // Queue for later
      _syncQueue.add(tx);
      return TransactionResult(
        txId: tx.id,
        status: TransactionStatus.pending,
      );
    }

    try {
      // Send via WebSocket for real-time sync
      _channel?.sink.add(jsonEncode({
        'type': 'transaction',
        'data': tx.toJson(),
      }));

      // Also send via HTTP for reliability
      final response = await _dio.post('/v1/transact', data: tx.toJson());

      return TransactionResult.fromJson(response.data);
    } catch (e) {
      // Queue for retry
      _syncQueue.add(tx);
      return TransactionResult(
        txId: tx.id,
        status: TransactionStatus.error,
        error: e.toString(),
      );
    }
  }

  void _handleRemoteMessage(dynamic message) {
    final data = jsonDecode(message);

    switch (data['type']) {
      case 'transaction':
        _applyRemoteTransaction(Transaction.fromJson(data['data']));
        break;
      case 'query_update':
        _handleQueryUpdate(data['query'], data['result']);
        break;
      case 'error':
        _handleRemoteError(data['error']);
        break;
    }
  }

  Future<void> _applyRemoteTransaction(Transaction tx) async {
    // Apply changes to local store
    for (final operation in tx.operations) {
      switch (operation.type) {
        case OperationType.add:
          await _store.addTriple(operation.triple, tx.id);
          break;
        case OperationType.retract:
          await _store.retractTriple(operation.triple, tx.id);
          break;
      }
    }
  }
}

class Transaction {
  final String id;
  final List<Operation> operations;
  final DateTime timestamp;

  Transaction({
    String? id,
    required this.operations,
    DateTime? timestamp,
  }) : id = id ?? _generateId(),
       timestamp = timestamp ?? DateTime.now();

  static String _generateId() => Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'operations': operations.map((op) => op.toJson()).toList(),
    'timestamp': timestamp.millisecondsSinceEpoch,
  };
}
```

### 5. Reactive Flutter Widgets

```dart
// lib/src/reactive/instant_builder.dart
import 'package:flutter/widgets.dart';
import 'package:signals/signals_flutter.dart';

/// Main reactive widget for InstantDB queries
class InstantBuilder<T> extends StatefulWidget {
  final Map<String, dynamic> query;
  final ZodSchema<T>? schema;
  final Widget Function(BuildContext, T data) builder;
  final Widget Function(BuildContext, String error)? errorBuilder;
  final Widget Function(BuildContext)? loadingBuilder;

  const InstantBuilder({
    Key? key,
    required this.query,
    required this.builder,
    this.schema,
    this.errorBuilder,
    this.loadingBuilder,
  }) : super(key: key);

  @override
  State<InstantBuilder<T>> createState() => _InstantBuilderState<T>();
}

class _InstantBuilderState<T> extends State<InstantBuilder<T>> {
  late final Signal<QueryResult> _querySignal;

  @override
  void initState() {
    super.initState();
    final db = InstantDB.of(context);
    _querySignal = db._queryEngine.query(widget.query);
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final result = _querySignal.value;

      if (result.isLoading) {
        return widget.loadingBuilder?.call(context) ??
            const CircularProgressIndicator();
      }

      if (result.error != null) {
        return widget.errorBuilder?.call(context, result.error!) ??
            Text('Error: ${result.error}');
      }

      // Validate with schema if provided
      final data = widget.schema != null
          ? widget.schema!.parse(result.data)
          : result.data as T;

      return widget.builder(context, data);
    });
  }
}

/// Hook-style API for queries
Signal<QueryResult> useInstantQuery(
  BuildContext context,
  Map<String, dynamic> query,
) {
  final db = InstantDB.of(context);
  return db._queryEngine.query(query);
}

/// Provider widget for InstantDB instance
class InstantProvider extends InheritedWidget {
  final InstantDB db;

  const InstantProvider({
    Key? key,
    required this.db,
    required Widget child,
  }) : super(key: key, child: child);

  static InstantDB of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<InstantProvider>();
    if (provider == null) {
      throw Exception('InstantProvider not found in widget tree');
    }
    return provider.db;
  }

  @override
  bool updateShouldNotify(InstantProvider oldWidget) => db != oldWidget.db;
}
```

## Implementation Steps

### Phase 1: Core Infrastructure (Week 1)

1. **Set up project structure**
   ```bash
   flutter create instant_flutter --template=package
   cd instant_flutter
   flutter pub add acanthis signals sqflite dio web_socket_channel
   ```

2. **Implement Triple Store**
   - SQLite schema
   - Basic CRUD operations
   - Change notifications

3. **Create Schema System**
   - Acanthis integration
   - Schema builder API
   - Validation logic

### Phase 2: Query Engine (Week 2)

1. **InstaQL Parser**
   - Query syntax parser
   - Query plan generation
   - Optimization passes

2. **Query Execution**
   - Triple lookups
   - Join operations
   - Nested query support

3. **Reactive Queries**
   - Signal-based reactivity
   - Automatic invalidation
   - Query caching

### Phase 3: Synchronization (Week 3)

1. **WebSocket Client**
   - Connection management
   - Message protocol
   - Reconnection logic

2. **Transaction System**
   - Optimistic updates
   - Conflict resolution
   - Rollback support

3. **Offline Queue**
   - Transaction persistence
   - Retry logic
   - Sync status tracking

### Phase 4: Flutter Integration (Week 4)

1. **Reactive Widgets**
   - InstantBuilder widget
   - Hook APIs
   - Provider pattern

2. **Developer Experience**
   - Code generation
   - Type safety
   - Error handling

3. **Performance Optimization**
   - Query batching
   - Lazy loading
   - Memory management

## API Design

### Initialization

```dart
// Initialize InstantDB
final db = InstantDB.init(
  appId: 'your-app-id',
  schema: schema,
  config: InstantConfig(
    persistenceDir: 'instant_db',
    syncEnabled: true,
    conflictResolver: LastWriteWinsResolver(),
  ),
);

// Provide to widget tree
runApp(
  InstantProvider(
    db: db,
    child: MyApp(),
  ),
);
```

### Schema Definition

```dart
// Define schemas with Acanthis
final userSchema = z.object({
  'id': z.string(),
  'email': z.string().email(),
  'name': z.string(),
  'posts': z.array(z.lazy(() => postSchema)).optional(),
});

final postSchema = z.object({
  'id': z.string(),
  'title': z.string(),
  'content': z.string(),
  'authorId': z.string(),
  'author': z.lazy(() => userSchema).optional(),
});

// Build InstantDB schema
final schema = InstantSchemaBuilder()
  .addEntity('users', userSchema)
  .addEntity('posts', postSchema)
  .addLink('postAuthor', Link(
    from: EntityRef('posts', 'authorId'),
    to: EntityRef('users', 'id'),
  ))
  .build();
```

### Queries

```dart
// Using InstantBuilder widget
InstantBuilder<List<User>>(
  query: {
    'users': {
      'posts': {
        'where': {'published': true},
        'orderBy': {'createdAt': 'desc'},
      },
    },
  },
  schema: z.array(userSchema),
  builder: (context, users) {
    return ListView.builder(
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return UserCard(user: user);
      },
    );
  },
);

// Using hooks
Widget build(BuildContext context) {
  final queryResult = useInstantQuery(context, {
    'posts': {
      'where': {'authorId': currentUserId},
      'include': {'author': {}},
    },
  });

  return Watch((context) {
    if (queryResult.value.isLoading) {
      return CircularProgressIndicator();
    }
    // ... render posts
  });
}
```

### Mutations

```dart
// Create a new entity
await db.transact([
  db.tx.posts.create({
    'id': db.id(),
    'title': 'My First Post',
    'content': 'Hello, InstantDB!',
    'authorId': currentUser.id,
  }),
]);

// Update an entity
await db.transact([
  db.tx.posts[postId].update({
    'title': 'Updated Title',
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  }),
]);

// Delete an entity
await db.transact([
  db.tx.posts[postId].delete(),
]);

// Batch operations
await db.transact([
  db.tx.users[userId].update({'name': 'New Name'}),
  db.tx.posts.create({'title': 'New Post', 'authorId': userId}),
  db.tx.notifications[notifId].delete(),
]);
```

### Authentication

```dart
// Sign in with email/password
final auth = await db.auth.signIn(
  email: 'user@example.com',
  password: 'password',
);

// Sign in with token
await db.auth.signInWithToken(token);

// Sign out
await db.auth.signOut();

// Listen to auth state
db.auth.onAuthStateChange.listen((user) {
  if (user != null) {
    // User is signed in
  } else {
    // User is signed out
  }
});
```

### Presence & Cursors

```dart
// Share presence
db.presence.set({
  'status': 'online',
  'cursor': {'x': 100, 'y': 200},
});

// Listen to others' presence
InstantPresence(
  channelId: 'document-123',
  builder: (context, presence) {
    return Stack(
      children: presence.entries.map((entry) {
        return Positioned(
          left: entry.data['cursor']['x'],
          top: entry.data['cursor']['y'],
          child: Cursor(user: entry.user),
        );
      }).toList(),
    );
  },
);
```

## Code Examples

### Complete Chat App Example

```dart
import 'package:flutter/material.dart';
import 'package:instant_flutter/instant_flutter.dart';

// Define schemas
final messageSchema = z.object({
  'id': z.string(),
  'text': z.string(),
  'authorId': z.string(),
  'author': z.object({
    'id': z.string(),
    'name': z.string(),
    'avatar': z.string().optional(),
  }).optional(),
  'createdAt': z.number(),
});

final schema = InstantSchemaBuilder()
  .addEntity('messages', messageSchema)
  .addEntity('users', userSchema)
  .addLink('messageAuthor', Link(
    from: EntityRef('messages', 'authorId'),
    to: EntityRef('users', 'id'),
  ))
  .build();

// Chat app
class ChatApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final db = InstantDB.init(
      appId: 'your-app-id',
      schema: schema,
    );

    return InstantProvider(
      db: db,
      child: MaterialApp(
        home: ChatScreen(),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final db = InstantDB.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('InstantDB Chat')),
      body: Column(
        children: [
          Expanded(
            child: InstantBuilder<List<Message>>(
              query: {
                'messages': {
                  'include': {'author': {}},
                  'orderBy': {'createdAt': 'desc'},
                },
              },
              schema: z.object({
                'messages': z.array(messageSchema),
              }).transform((data) => data['messages']),
              builder: (context, messages) {
                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return MessageBubble(message: message);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () async {
                    final text = _controller.text.trim();
                    if (text.isEmpty) return;

                    await db.transact([
                      db.tx.messages.create({
                        'id': db.id(),
                        'text': text,
                        'authorId': db.auth.currentUser!.id,
                        'createdAt': DateTime.now().millisecondsSinceEpoch,
                      }),
                    ]);

                    _controller.clear();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

### Collaborative Todo App

```dart
class TodoApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InstantBuilder<TodoList>(
      query: {
        'todoLists': {
          'where': {'id': listId},
          'include': {
            'todos': {
              'orderBy': {'position': 'asc'},
              'include': {'assignee': {}},
            },
            'collaborators': {},
          },
        },
      },
      builder: (context, list) {
        return Scaffold(
          appBar: AppBar(
            title: Text(list.title),
            actions: [
              // Show active collaborators
              InstantPresence(
                channelId: 'list-${list.id}',
                builder: (context, presence) {
                  return Row(
                    children: presence.entries.map((entry) {
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: CircleAvatar(
                          backgroundImage: NetworkImage(entry.user.avatar),
                          radius: 16,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
          body: ReorderableListView(
            onReorder: (oldIndex, newIndex) async {
              await _reorderTodos(list.todos, oldIndex, newIndex);
            },
            children: list.todos.map((todo) {
              return TodoTile(
                key: ValueKey(todo.id),
                todo: todo,
                onToggle: () => _toggleTodo(todo),
                onAssign: (userId) => _assignTodo(todo, userId),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
```

## Testing Strategy

### Unit Tests

```dart
// Test schema validation
test('validates user schema', () {
  final schema = userSchema;

  expect(
    () => schema.parse({
      'id': '123',
      'email': 'invalid-email',
      'name': 'Test User',
    }),
    throwsA(isA<ValidationError>()),
  );
});

// Test query engine
test('executes nested queries', () async {
  final engine = QueryEngine(mockStore);

  final result = await engine.query({
    'users': {
      'where': {'active': true},
      'include': {'posts': {}},
    },
  }).value;

  expect(result.data['users'], hasLength(2));
  expect(result.data['users'][0]['posts'], isNotEmpty);
});

// Test optimistic updates
test('applies optimistic updates', () async {
  final db = InstantDB.init(appId: 'test', schema: schema);

  final future = db.transact([
    db.tx.posts.create({'title': 'Test Post'}),
  ]);

  // Should update immediately
  final query = db.query({'posts': {}});
  expect(query.value.data['posts'], hasLength(1));

  // Should rollback on error
  mockSyncEngine.failNext();
  await expectLater(future, throwsException);
  expect(query.value.data['posts'], isEmpty);
});
```

### Integration Tests

```dart
testWidgets('InstantBuilder updates on data change', (tester) async {
  final db = MockInstantDB();

  await tester.pumpWidget(
    InstantProvider(
      db: db,
      child: MaterialApp(
        home: InstantBuilder<List<String>>(
          query: {'messages': {}},
          builder: (context, messages) {
            return Column(
              children: messages.map((m) => Text(m)).toList(),
            );
          },
        ),
      ),
    ),
  );

  // Initial state
  expect(find.text('Loading...'), findsOneWidget);

  // Update data
  db.emitData({'messages': ['Hello', 'World']});
  await tester.pump();

  expect(find.text('Hello'), findsOneWidget);
  expect(find.text('World'), findsOneWidget);
});
```

## Migration Guide

### From React to Flutter

#### React Code:
```javascript
const { data, isLoading, error } = db.useQuery({
  users: {
    posts: {
      comments: {}
    }
  }
});

const addPost = (title) => {
  db.transact(tx.posts[id()].update({ title }));
};
```

#### Flutter Equivalent:
```dart
// Using InstantBuilder
InstantBuilder(
  query: {
    'users': {
      'posts': {
        'comments': {},
      },
    },
  },
  builder: (context, data) {
    // Use data here
  },
);

// Using hooks
final query = useInstantQuery(context, {
  'users': {'posts': {'comments': {}}}
});

// Mutations
final addPost = (String title) async {
  await db.transact([
    db.tx.posts[db.id()].update({'title': title}),
  ]);
};
```

### Schema Migration

#### JavaScript Schema:
```javascript
const schema = {
  entities: {
    users: {
      email: { type: 'string' },
      name: { type: 'string' }
    }
  }
};
```

#### Dart Schema:
```dart
final schema = InstantSchemaBuilder()
  .addEntity('users', z.object({
    'email': z.string().email(),
    'name': z.string(),
  }))
  .build();
```

## Performance Considerations

### Query Optimization

1. **Index frequently queried fields**
   ```dart
   await db.createIndex('posts', ['authorId', 'createdAt']);
   ```

2. **Use query fragments for reusable parts**
   ```dart
   final userFragment = {
     'id': true,
     'name': true,
     'avatar': true,
   };

   final query = {
     'posts': {
       'author': userFragment,
       'comments': {
         'author': userFragment,
       },
     },
   };
   ```

3. **Implement pagination**
   ```dart
   InstantPaginatedBuilder<Post>(
     query: {
       'posts': {
         'orderBy': {'createdAt': 'desc'},
       },
     },
     pageSize: 20,
     builder: (context, posts, loadMore) {
       return ListView.builder(
         itemCount: posts.length + 1,
         itemBuilder: (context, index) {
           if (index == posts.length) {
             return LoadMoreButton(onTap: loadMore);
           }
           return PostCard(post: posts[index]);
         },
       );
     },
   );
   ```

### Memory Management

1. **Dispose of unused queries**
   ```dart
   @override
   void dispose() {
     db.disposeQuery(queryKey);
     super.dispose();
   }
   ```

2. **Configure cache limits**
   ```dart
   final db = InstantDB.init(
     appId: 'app-id',
     config: InstantConfig(
       maxCacheSize: 50 * 1024 * 1024, // 50MB
       maxCachedQueries: 100,
     ),
   );
   ```

## Deployment Checklist

- [ ] Configure production API endpoints
- [ ] Set up authentication providers
- [ ] Enable ProGuard rules for Android
- [ ] Configure iOS App Transport Security
- [ ] Test offline scenarios
- [ ] Implement error reporting
- [ ] Set up monitoring and analytics
- [ ] Configure backup and restore
- [ ] Test conflict resolution
- [ ] Verify schema migrations work

## Resources

- [InstantDB Documentation](https://instantdb.com/docs)
- [Acanthis Documentation](https://acanthis.avesbox.com)
- [Signals Package](https://pub.dev/packages/signals)
- [Flutter Database Comparison](https://flutter.dev/docs/cookbook/persistence)

This guide provides a comprehensive roadmap for porting InstantDB to Flutter. The architecture leverages Dart's strengths while maintaining compatibility with InstantDB's core concepts and developer experience.