# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter package for implementing InstantDB - a real-time, offline-first database with reactive bindings. The project aims to port InstantDB's React SDK functionality to Flutter, providing local-first data synchronization with type-safe queries and reactive widgets.

## Development Commands

### Testing
```bash
flutter test                    # Run all tests
flutter test --coverage        # Run tests with coverage
```

### Code Quality
```bash
flutter analyze                 # Run static analysis
dart format lib/ test/          # Format code
```

### Package Development
```bash
flutter pub get                 # Install dependencies
flutter pub deps               # Show dependency tree
flutter pub publish --dry-run  # Validate package for publishing
```

## Architecture

The package follows a modular architecture with these core components:

- **Schema System**: Uses Acanthis for type-safe schema validation and code generation
- **Triple Store**: SQLite-based local storage implementing a triple-based data model
- **Query Engine**: InstaQL query processor with reactive bindings using Signals
- **Sync Engine**: Real-time synchronization via WebSocket with conflict resolution
- **Reactive Widgets**: Flutter widgets that automatically update when data changes

Key dependencies:
- `acanthis` - Schema validation and type generation
- `signals` - Reactive state management
- `sqflite` - Local SQLite persistence
- `dio` - HTTP client for REST communication
- `web_socket_channel` - WebSocket client for real-time sync

## Implementation Status

This is a fully functional InstantDB Flutter implementation with feature parity to the React SDK. The package includes:

- ✅ **Complete Core Implementation**: Full InstantDB client with initialization and configuration
- ✅ **SQLite Triple Store**: Robust local storage with full pattern query support 
- ✅ **Real-time Sync Engine**: WebSocket-based synchronization with conflict resolution
- ✅ **Reactive Query System**: Signal-based reactive queries with Flutter widget integration
- ✅ **Transaction System**: Full CRUD operations with optimistic updates and rollback
- ✅ **Authentication**: User authentication and session management
- ✅ **Presence System**: Real-time collaboration features (cursors, typing, reactions, avatars) with full multi-instance synchronization
- ✅ **Multi-Entity Type Support**: Complete synchronization support for todos, tiles, messages, and all custom entity types
- ✅ **Advanced Logging System**: Hierarchical logging with dynamic level control and debug toggle UI
- ✅ **Platform Support**: Works on iOS, Android, Web, macOS, Windows, and Linux

## File Structure

```
lib/
├── instantdb_flutter.dart          # Main entry point and public API
└── src/                            # Implementation modules
    ├── core/                       # Core InstantDB client and types
    │   ├── instant_db.dart         # Main InstantDB class
    │   ├── types.dart              # Core type definitions
    │   └── transaction_builder.dart # Fluent transaction API
    ├── storage/                    # Local storage implementation
    │   ├── triple_store.dart       # SQLite-based triple store
    │   ├── storage_interface.dart  # Storage abstraction
    │   └── database_factory.dart   # Platform-specific DB factory
    ├── query/                      # Query engine implementation
    │   └── query_engine.dart       # Reactive query processor
    ├── sync/                       # Real-time synchronization
    │   ├── sync_engine.dart        # WebSocket sync engine
    │   └── web_socket_*.dart       # Platform-specific WebSocket
    ├── reactive/                   # Flutter reactive widgets
    │   ├── instant_builder.dart    # Query result widgets
    │   └── presence.dart           # Collaboration features
    └── auth/                       # Authentication management
        └── auth_manager.dart       # User auth and sessions
```

## Development Notes

- This package targets Flutter SDK >=1.17.0 and Dart SDK ^3.8.0
- Uses flutter_lints for code quality enforcement
- **Storage Backend**: Uses SQLite for local persistence across all platforms
- **Real-time Sync**: WebSocket connection to InstantDB cloud for data synchronization
- **Reactive Architecture**: Built on signals_flutter for efficient UI updates
- **Platform Support**: Conditional imports handle platform-specific implementations
- **Logging System**: Uses standard Dart `logging` package with hierarchical loggers for each component
- **Debug Tools**: Example app includes debug toggle for runtime log level control
- **Testing**: Comprehensive test suite with example applications demonstrating all features

### Debugging and Development

The package includes comprehensive debugging tools:

- **Hierarchical Logging**: Component-specific loggers (sync, query, websocket, transaction, auth)
- **Dynamic Log Levels**: Change verbosity at runtime without restart
- **Debug Toggle UI**: Example app demonstrates user-friendly debug control
- **Structured Logging**: Correlation IDs and metadata for easier troubleshooting
- **Production Ready**: WARNING level default for clean console output