// Web implementation using sqflite_common_ffi_web
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

bool _initialized = false;

Future<void> initializePlatformDatabaseFactory() async {
  if (!_initialized) {
    // Set the web database factory
    databaseFactory = databaseFactoryFfiWeb;
    _initialized = true;
  }
}

DatabaseFactory getPlatformDatabaseFactory() {
  if (!_initialized) {
    // Ensure initialization
    databaseFactory = databaseFactoryFfiWeb;
    _initialized = true;
  }
  return databaseFactoryFfiWeb;
}

Future<String> getPlatformDatabasePath(
  String appId, {
  String? persistenceDir,
}) async {
  // On web, we just use the app ID as the database name
  // The actual storage happens in IndexedDB
  if (persistenceDir != null) {
    return '${persistenceDir}_$appId.db';
  }
  return '$appId.db';
}
