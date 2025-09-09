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
- ✅ **Enhanced Datalog Processing**: Robust datalog-result format handling with comprehensive edge case coverage
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
- **Enhanced Datalog Processing**: Robust handling of multiple datalog-result format variations with comprehensive edge case coverage
- **Reactive Architecture**: Built on signals_flutter for efficient UI updates
- **Platform Support**: Conditional imports handle platform-specific implementations
- **Logging System**: Uses standard Dart `logging` package with hierarchical loggers for each component
- **Debug Tools**: Example app includes debug toggle for runtime log level control
- **Testing**: Comprehensive test suite with example applications demonstrating all features

### Recent Improvements

#### v0.2.4 - Fixed Entity Type Resolution in Datalog Conversion
- **Entity type resolution**: Fixed critical bug where entities were cached under wrong collection name
- **Query type extraction**: Extract entity type from response `data['q']` field to determine correct collection
- **Type propagation**: Pass entity type through entire datalog conversion pipeline
- **Smart grouping**: Use query type when grouping entities, with proper fallback chain
- **Cache alignment**: Entities now cached under correct collection name matching the query

#### v0.2.3 - Fixed Race Condition in Query Execution
- **Eliminated race condition**: Fixed critical issue where queries returned empty results before cache was populated
- **Synchronous cache checking**: Queries now check cache synchronously before returning Signal
- **Immediate data initialization**: Query Signals are initialized with cached data if available
- **Enhanced logging pipeline**: Added "Reconstructed X entities" log and comprehensive datalog conversion logging
- **Complete datalog fix**: The package now properly converts datalog, caches it, AND returns it immediately to applications

#### v0.2.2 - Query Result Caching System
- **Fixed datalog to collection format conversion**: Applications now receive properly formatted collection data instead of raw datalog
- **Query result caching**: Converted datalog results are cached for immediate access, solving the "0 documents" issue
- **Cache-first query strategy**: Queries check cache before storage for instant data availability
- **Smart cache invalidation**: Cache automatically clears when transactions affect collections

#### v0.2.1 - Enhanced Datalog Processing
- **Robust Format Detection**: Handles multiple datalog-result format variations including nested structures
- **Comprehensive Edge Case Coverage**: Addresses scenarios where malformed join-rows or unexpected data structures could cause silent failures
- **Enhanced Error Logging**: Detailed logging for unrecognized query response formats to aid debugging
- **Multiple Fallback Paths**: Tries various datalog extraction methods before falling back to simple collection format
- **Improved Delete Detection**: Better handling of entity deletions across different data formats

#### Bug Fixes
- Fixed critical issue where datalog format wasn't converted to collection format for applications
- Fixed edge cases where datalog-result format could bypass conversion, leading to empty query results
- Resolved timing-dependent format detection failures during connection initialization
- Enhanced handling of different message types with varying data structure expectations
- Added explicit warnings for unhandled data formats instead of silent failures

### Debugging and Development

The package includes comprehensive debugging tools:

- **Hierarchical Logging**: Component-specific loggers (sync, query, websocket, transaction, auth)
- **Dynamic Log Levels**: Change verbosity at runtime without restart
- **Debug Toggle UI**: Example app demonstrates user-friendly debug control
- **Structured Logging**: Correlation IDs and metadata for easier troubleshooting
- **Production Ready**: WARNING level default for clean console output