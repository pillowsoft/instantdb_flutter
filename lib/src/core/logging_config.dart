import 'dart:io';
import 'package:logging/logging.dart';

/// Logging configuration for InstantDB with hierarchical loggers
class InstantDBLogging {
  static bool _isConfigured = false;
  static String _instanceId =
      'Instance-${DateTime.now().millisecondsSinceEpoch % 10000}';

  // Hierarchical loggers for different components
  static final Logger root = Logger('InstantDB');
  static final Logger syncEngine = Logger('InstantDB.SyncEngine');
  static final Logger reaxStore = Logger('InstantDB.ReaxStore');
  static final Logger queryEngine = Logger('InstantDB.QueryEngine');
  static final Logger webSocket = Logger('InstantDB.WebSocket');
  static final Logger transaction = Logger('InstantDB.Transaction');
  static final Logger auth = Logger('InstantDB.Auth');

  /// Configure logging for the entire InstantDB library
  static void configure({
    Level level = Level.INFO,
    bool enableHierarchical = true,
    String? instanceId,
  }) {
    if (_isConfigured) return;

    if (instanceId != null) {
      _instanceId = instanceId;
    }

    // Enable hierarchical logging to allow per-component configuration
    if (enableHierarchical) {
      hierarchicalLoggingEnabled = true;
    }

    // Set default log level for the root logger
    Logger.root.level = level;

    // Set up the log record listener with formatted output
    Logger.root.onRecord.listen(_logHandler);

    // Set individual component levels (can be overridden)
    root.level = level;
    syncEngine.level = level;
    reaxStore.level = level;
    queryEngine.level = level;
    webSocket.level = level;
    transaction.level = level;
    auth.level = level;

    _isConfigured = true;

    root.info('InstantDB logging configured for $_instanceId');
    root.info('Log level: ${level.name}, Hierarchical: $enableHierarchical');
  }

  /// Set log level for a specific component
  static void setLevel(String component, Level level) {
    switch (component.toLowerCase()) {
      case 'sync':
      case 'syncengine':
        syncEngine.level = level;
        break;
      case 'store':
      case 'reaxstore':
        reaxStore.level = level;
        break;
      case 'query':
      case 'queryengine':
        queryEngine.level = level;
        break;
      case 'websocket':
      case 'ws':
        webSocket.level = level;
        break;
      case 'transaction':
      case 'tx':
        transaction.level = level;
        break;
      case 'auth':
      case 'authentication':
        auth.level = level;
        break;
      case 'root':
      case 'all':
        Logger.root.level = level;
        break;
      default:
        root.warning('Unknown component: $component');
    }
  }

  /// Get the instance identifier
  static String get instanceId => _instanceId;

  /// Set a custom instance identifier
  static void setInstanceId(String id) {
    _instanceId = id;
  }

  /// Update log level for all loggers dynamically
  static void updateLogLevel(Level newLevel) {
    Logger.root.level = newLevel;
    root.level = newLevel;
    syncEngine.level = newLevel;
    queryEngine.level = newLevel;
    webSocket.level = newLevel;
    transaction.level = newLevel;
    auth.level = newLevel;

    root.info('Log level updated to: ${newLevel.name}');
  }

  /// Internal log handler with formatting
  static void _logHandler(LogRecord record) {
    final timestamp = _formatTimestamp(record.time);
    final level = _formatLevel(record.level);
    final logger = _formatLogger(record.loggerName);
    final message = record.message;
    final error = record.error != null ? ' | Error: ${record.error}' : '';
    final stackTrace = record.stackTrace != null
        ? '\n${record.stackTrace}'
        : '';

    final formattedMessage =
        '[$timestamp] [$_instanceId] [$logger] [$level] $message$error$stackTrace';

    // Use different output streams based on log level
    if (record.level >= Level.SEVERE) {
      stderr.writeln(formattedMessage);
    } else {
      print(formattedMessage);
    }
  }

  /// Format timestamp in HH:MM:SS.mmm format
  static String _formatTimestamp(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }

  /// Format log level with consistent width
  static String _formatLevel(Level level) {
    return level.name.padRight(7);
  }

  /// Format logger name with consistent width
  static String _formatLogger(String loggerName) {
    // Shorten common logger names for readability
    final shortName = loggerName
        .replaceAll('InstantDB.', '')
        .replaceAll('InstantDB', 'Root');

    return shortName.padRight(12);
  }

  /// Create structured log data for correlation
  static Map<String, dynamic> correlationData({
    String? txId,
    String? entityId,
    String? entityType,
    String? operation,
    int? operationCount,
    Map<String, dynamic>? extra,
  }) {
    final data = <String, dynamic>{
      'instance': _instanceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    if (txId != null) data['txId'] = txId;
    if (entityId != null) data['entityId'] = entityId;
    if (entityType != null) data['entityType'] = entityType;
    if (operation != null) data['operation'] = operation;
    if (operationCount != null) data['operationCount'] = operationCount;
    if (extra != null) data.addAll(extra);

    return data;
  }

  /// Helper to log with correlation data
  static void logWithCorrelation(
    Logger logger,
    Level level,
    String message,
    Map<String, dynamic> correlationData,
  ) {
    final formattedData = correlationData.entries
        .map((e) => '${e.key}=${e.value}')
        .join(', ');

    logger.log(level, '$message | {$formattedData}');
  }

  /// Convenience methods for common logging patterns
  static void logTransaction(
    String phase,
    String txId, {
    int? operationCount,
    String? entityType,
    String? status,
    int? duration,
  }) {
    final data = correlationData(
      txId: txId,
      operation: phase,
      operationCount: operationCount,
      entityType: entityType,
      extra: {
        if (status != null) 'status': status,
        if (duration != null) 'duration': '${duration}ms',
      },
    );

    logWithCorrelation(transaction, Level.INFO, 'TX_$phase', data);
  }

  static void logWebSocketMessage(
    String direction,
    String messageType, {
    String? eventId,
    int? messageSize,
  }) {
    final data = correlationData(
      operation: '$direction$messageType',
      extra: {
        if (eventId != null) 'eventId': eventId,
        if (messageSize != null) 'size': '${messageSize}b',
      },
    );

    logWithCorrelation(
      webSocket,
      Level.FINE,
      'WS_$direction$messageType',
      data,
    );
  }

  static void logQueryEvent(
    String event,
    String queryKey, {
    String? reason,
    int? resultCount,
  }) {
    final data = correlationData(
      operation: event,
      extra: {
        'queryKey': queryKey.hashCode.toString(),
        if (reason != null) 'reason': reason,
        if (resultCount != null) 'resultCount': resultCount,
      },
    );

    logWithCorrelation(queryEngine, Level.FINE, 'QUERY_$event', data);
  }
}

/// Extension to make logging more convenient
extension InstantDBLoggerExtension on Logger {
  void trace(String message, [Object? error, StackTrace? stackTrace]) {
    log(Level.FINEST, message, error, stackTrace);
  }

  void debug(String message, [Object? error, StackTrace? stackTrace]) {
    log(Level.FINE, message, error, stackTrace);
  }
}
