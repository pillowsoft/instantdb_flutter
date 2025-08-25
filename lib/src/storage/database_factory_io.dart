// Mobile/Desktop implementation using default sqflite
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

Future<void> initializePlatformDatabaseFactory() async {
  // No initialization needed for mobile/desktop - sqflite handles this
}

DatabaseFactory getPlatformDatabaseFactory() {
  return databaseFactory;
}

Future<String> getPlatformDatabasePath(String appId, {String? persistenceDir}) async {
  if (persistenceDir != null) {
    return join(persistenceDir, '$appId.db');
  }
  return join(await getDatabasesPath(), '$appId.db');
}