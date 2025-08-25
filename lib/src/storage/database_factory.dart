// Platform-specific database factory initialization
// This file provides different implementations for web and mobile/desktop platforms

import 'package:sqflite/sqflite.dart';

// Conditional imports based on platform
import 'database_factory_stub.dart'
  if (dart.library.html) 'database_factory_web.dart'
  if (dart.library.ffi) 'database_factory_io.dart';

/// Initializes the appropriate database factory for the current platform
/// - Web: Uses sqflite_common_ffi_web
/// - Mobile/Desktop: Uses default sqflite factory
Future<void> initializeDatabaseFactory() async {
  await initializePlatformDatabaseFactory();
}

/// Returns the appropriate database factory for the current platform
DatabaseFactory getDatabaseFactory() {
  return getPlatformDatabaseFactory();
}

/// Returns the appropriate database path for the platform
/// - Web: Uses simple database name (stored in IndexedDB)
/// - Mobile/Desktop: Uses standard database path
Future<String> getDatabasePath(String appId, {String? persistenceDir}) async {
  return await getPlatformDatabasePath(appId, persistenceDir: persistenceDir);
}