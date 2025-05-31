# InstantDB Flutter Todo Example

This example demonstrates how to build a real-time, collaborative todo app using InstantDB Flutter.

## Features

- ✅ Real-time synchronization between multiple app instances
- ✅ Works without user authentication (anonymous mode)
- ✅ Offline-first with local persistence
- ✅ Reactive UI that updates automatically when data changes
- ✅ Add, complete, and delete todos
- ✅ Connection status indicator
- ✅ Clean Material Design UI
- ✅ Optional authentication example included

## Getting Started

1. **Set up InstantDB Project**
   - Go to [instantdb.com](https://instantdb.com) and create an account
   - Create a new project and copy your App ID

2. **Configure Environment**
   - Create a `.env` file in the example directory
   - Add your InstantDB App ID:
     ```
     INSTANTDB_API_ID=your-app-id-here
     ```

3. **Install Dependencies**
   ```bash
   flutter pub get
   ```

4. **Run the App**
   ```bash
   flutter run
   ```

## Testing Real-time Sync

To see the real-time synchronization in action:

1. Run the app on multiple devices/emulators simultaneously
2. Add, complete, or delete todos on one device
3. Watch as the changes appear instantly on all other devices!

You can also:
- Run multiple instances in different browser tabs (with `flutter run -d chrome`)
- Use physical devices and emulators side by side
- Open the app while someone else has it open to see collaborative editing

## How It Works

### Anonymous Mode (Default)

The todo app works immediately without any login:
- InstantDB automatically creates an anonymous session
- Todos sync across all devices/browsers using the same app ID
- No user accounts needed - perfect for demos and simple apps

### Optional Authentication

If you want user-specific todos, you can add authentication:
- See `auth_example.dart` for a complete implementation
- Users can sign up/sign in with email and password
- Each user gets their own private todo list
- The app gracefully handles both anonymous and authenticated states

## Key Code Concepts

### InstantDB Initialization

```dart
final db = await InstantDB.init(
  appId: 'your-app-id',
  config: const InstantConfig(
    syncEnabled: true, // Enable real-time sync
  ),
);
```

### Reactive Queries with InstantBuilder

```dart
InstantBuilderTyped<List<Map<String, dynamic>>>(
  query: {
    'todos': {
      'orderBy': {'createdAt': 'desc'},
    },
  },
  transformer: (data) => (data['todos'] as List).cast<Map<String, dynamic>>(),
  builder: (context, todos) {
    // UI automatically updates when todos change
    return ListView.builder(
      itemCount: todos.length,
      itemBuilder: (context, index) => TodoTile(todo: todos[index]),
    );
  },
)
```

### Creating Data

```dart
await db.transact([
  ...db.create('todos', {
    'id': db.id(),
    'text': 'My new todo',
    'completed': false,
    'createdAt': DateTime.now().millisecondsSinceEpoch,
  }),
]);
```

### Updating Data

```dart
await db.transact([
  db.update(todoId, {
    'completed': !currentCompleted,
  }),
]);
```

### Deleting Data

```dart
await db.transact([
  db.delete(todoId),
]);
```

### Connection Status

```dart
ConnectionStatusBuilder(
  builder: (context, isOnline) {
    return Icon(
      isOnline ? Icons.cloud_done : Icons.cloud_off,
      color: isOnline ? Colors.green : Colors.red,
    );
  },
)
```

## Architecture

The app demonstrates several key InstantDB Flutter patterns:

- **InstantProvider**: Provides InstantDB instance to the widget tree
- **InstantBuilderTyped**: Reactive widget that rebuilds when query results change  
- **Signals**: Underlying reactivity system that powers real-time updates
- **Transactions**: Atomic operations that ensure data consistency
- **Local-first**: Data is stored locally and synced to the cloud

## Troubleshooting

**App won't connect to InstantDB:**
- Verify your App ID is correct in the `.env` file
- Check your internet connection
- Make sure you have the latest version of the package

**Changes not syncing between devices:**
- Ensure both devices are online (check the connection indicator)
- Verify both devices are using the same App ID
- Try refreshing/restarting the app

**Build errors:**
- Run `flutter clean && flutter pub get`
- Make sure you're using Flutter 3.27.0 or later
- Check that all dependencies are properly installed

## Learn More

- [InstantDB Documentation](https://instantdb.com/docs)
- [InstantDB Flutter Package](../README.md)
- [Flutter Documentation](https://flutter.dev)

## Next Steps

Try customizing the app:
- Add user authentication
- Include todo categories or tags
- Add due dates and reminders
- Implement todo sharing between users
- Add rich text or markdown support