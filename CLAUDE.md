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

This is currently a new Flutter package project with basic scaffolding. The main implementation needs to be built according to the detailed specification in `IMPLEMENTATION_SPEC.md`.

The current structure contains:
- Basic Flutter package setup
- Placeholder Calculator class in `lib/instantdb_flutter.dart`
- Standard test setup with flutter_test and flutter_lints

## File Structure

```
lib/
├── instantdb_flutter.dart          # Main entry point (currently placeholder)
└── src/                            # Future implementation modules
    ├── core/                       # Core InstantDB client
    ├── schema/                     # Schema definition and validation
    ├── query/                      # Query engine and parser
    ├── storage/                    # Local storage (triple store)
    ├── sync/                       # Synchronization engine
    ├── reactive/                   # Flutter reactive widgets
    └── auth/                       # Authentication management
```

## Development Notes

- This package targets Flutter SDK >=1.17.0 and Dart SDK ^3.8.0
- Uses flutter_lints for code quality enforcement
- Implementation should follow the detailed specification in IMPLEMENTATION_SPEC.md
- The project is in early development phase - core functionality needs to be implemented