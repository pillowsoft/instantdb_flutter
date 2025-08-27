// Stub implementation for unsupported platforms
import 'package:sqflite/sqflite.dart';

Future<void> initializePlatformDatabaseFactory() async {
  throw UnsupportedError('Database factory not supported on this platform');
}

DatabaseFactory getPlatformDatabaseFactory() {
  throw UnsupportedError('Database factory not supported on this platform');
}

Future<String> getPlatformDatabasePath(String appId, {String? persistenceDir}) async {
  throw UnsupportedError('Database path not supported on this platform');
}