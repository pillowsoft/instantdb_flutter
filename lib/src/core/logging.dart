import 'package:logging/logging.dart';
import 'logging_config.dart';

/// Simple logging utility for InstantDB
/// This is a legacy wrapper - prefer using InstantDBLogging directly
class InstantLogger {
  static bool _verbose = false;
  static final Logger _logger = InstantDBLogging.root;

  /// Enable verbose logging (for debugging)
  static void enableVerbose() {
    _verbose = true;
    InstantDBLogging.updateLogLevel(Level.FINE);
  }

  /// Disable verbose logging (default)
  static void disableVerbose() {
    _verbose = false;
    InstantDBLogging.updateLogLevel(Level.INFO);
  }

  /// Log a debug message (only shown in verbose mode)
  static void debug(String message) {
    if (_verbose) {
      _logger.fine(message);
    }
  }

  /// Log an info message (only shown in verbose mode)
  static void info(String message) {
    if (_verbose) {
      _logger.info(message);
    }
  }

  /// Log a warning message (always shown)
  static void warn(String message) {
    _logger.warning(message);
  }

  /// Log an error message (always shown)
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.severe(message, error, stackTrace);
  }
}
