/// Simple logging utility for InstantDB
class InstantLogger {
  static bool _verbose = false;
  static final bool _logErrors = true;

  /// Enable verbose logging (for debugging)
  static void enableVerbose() {
    _verbose = true;
  }

  /// Disable verbose logging (default)
  static void disableVerbose() {
    _verbose = false;
  }

  /// Log a debug message (only shown in verbose mode)
  static void debug(String message) {
    if (_verbose) {
      print('InstantDB: $message');
    }
  }

  /// Log an info message (only shown in verbose mode)
  static void info(String message) {
    if (_verbose) {
      print('InstantDB: $message');
    }
  }

  /// Log a warning message (always shown)
  static void warn(String message) {
    print('InstantDB [WARN]: $message');
  }

  /// Log an error message (always shown)
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (_logErrors) {
      print('InstantDB [ERROR]: $message');
      if (error != null) {
        print('InstantDB [ERROR]: $error');
      }
      if (stackTrace != null && _verbose) {
        print('InstantDB [ERROR]: $stackTrace');
      }
    }
  }
}
