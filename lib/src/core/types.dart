import 'package:json_annotation/json_annotation.dart';

part 'types.g.dart';

/// A unique identifier type for entities
typedef EntityId = String;

/// A transaction ID for tracking changes
typedef TxId = String;

/// Represents a triple in the database (entity, attribute, value)
@JsonSerializable()
class Triple {
  final EntityId entityId;
  final String attribute;
  final dynamic value;
  final TxId txId;
  final DateTime createdAt;
  final bool retracted;

  const Triple({
    required this.entityId,
    required this.attribute,
    required this.value,
    required this.txId,
    required this.createdAt,
    this.retracted = false,
  });

  factory Triple.fromJson(Map<String, dynamic> json) => _$TripleFromJson(json);
  Map<String, dynamic> toJson() => _$TripleToJson(this);

  Triple copyWith({
    EntityId? entityId,
    String? attribute,
    dynamic value,
    TxId? txId,
    DateTime? createdAt,
    bool? retracted,
  }) {
    return Triple(
      entityId: entityId ?? this.entityId,
      attribute: attribute ?? this.attribute,
      value: value ?? this.value,
      txId: txId ?? this.txId,
      createdAt: createdAt ?? this.createdAt,
      retracted: retracted ?? this.retracted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Triple &&
          runtimeType == other.runtimeType &&
          entityId == other.entityId &&
          attribute == other.attribute &&
          value == other.value;

  @override
  int get hashCode => entityId.hashCode ^ attribute.hashCode ^ value.hashCode;
}

/// Represents a change in the triple store
@JsonSerializable()
class TripleChange {
  final ChangeType type;
  final Triple triple;

  const TripleChange({
    required this.type,
    required this.triple,
  });

  factory TripleChange.fromJson(Map<String, dynamic> json) => _$TripleChangeFromJson(json);
  Map<String, dynamic> toJson() => _$TripleChangeToJson(this);
}

/// Type of change that occurred
enum ChangeType {
  @JsonValue('add')
  add,
  @JsonValue('retract')
  retract,
}

/// Result of a query operation
@JsonSerializable()
class QueryResult {
  final bool isLoading;
  final Map<String, dynamic>? data;
  final String? error;

  const QueryResult({
    required this.isLoading,
    this.data,
    this.error,
  });

  factory QueryResult.loading() => const QueryResult(isLoading: true);
  
  factory QueryResult.success(Map<String, dynamic> data) => QueryResult(
        isLoading: false,
        data: data,
      );
  
  factory QueryResult.error(String error) => QueryResult(
        isLoading: false,
        error: error,
      );

  factory QueryResult.fromJson(Map<String, dynamic> json) => _$QueryResultFromJson(json);
  Map<String, dynamic> toJson() => _$QueryResultToJson(this);

  bool get hasData => data != null;
  bool get hasError => error != null;
}

/// Configuration for InstantDB client
@JsonSerializable()
class InstantConfig {
  final String? persistenceDir;
  final bool syncEnabled;
  final String? baseUrl;
  final int maxCacheSize;
  final int maxCachedQueries;
  final Duration reconnectDelay;
  final bool verboseLogging;

  const InstantConfig({
    this.persistenceDir,
    this.syncEnabled = true,
    this.baseUrl = 'https://api.instantdb.com',
    this.maxCacheSize = 50 * 1024 * 1024, // 50MB
    this.maxCachedQueries = 100,
    this.reconnectDelay = const Duration(seconds: 1),
    this.verboseLogging = false,
  });

  factory InstantConfig.fromJson(Map<String, dynamic> json) => _$InstantConfigFromJson(json);
  Map<String, dynamic> toJson() => _$InstantConfigToJson(this);
}

/// Transaction operation types (aligned with InstantDB core)
enum OperationType {
  @JsonValue('add')
  add,
  @JsonValue('update')
  update,
  @JsonValue('delete')
  delete,
  @JsonValue('retract')
  retract,
  @JsonValue('link')
  link,
  @JsonValue('unlink')
  unlink,
  @JsonValue('merge')
  merge,
}

/// A single operation in a transaction (aligned with InstantDB core format)
@JsonSerializable()
class Operation {
  final OperationType type;
  final String entityType;
  final EntityId entityId;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? options;

  const Operation({
    required this.type,
    required this.entityType,
    required this.entityId,
    this.data,
    this.options,
  });

  factory Operation.fromJson(Map<String, dynamic> json) => _$OperationFromJson(json);
  Map<String, dynamic> toJson() => _$OperationToJson(this);

  // Legacy constructor for backward compatibility
  factory Operation.legacy({
    required OperationType type,
    required EntityId entityId,
    String? attribute,
    dynamic value,
    dynamic oldValue,
  }) {
    final data = <String, dynamic>{};
    if (attribute != null && value != null) {
      data[attribute] = value;
    }
    return Operation(
      type: type,
      entityType: 'unknown', // Will be set properly by transaction builder
      entityId: entityId,
      data: data.isEmpty ? null : data,
    );
  }

  // Legacy getters for backward compatibility
  String? get attribute {
    if (data != null && data!.length == 1) {
      return data!.keys.first;
    }
    return null;
  }

  dynamic get value {
    if (data != null && data!.length == 1) {
      return data!.values.first;
    }
    return null;
  }
}

/// A transaction containing multiple operations
@JsonSerializable()
class Transaction {
  final TxId id;
  final List<Operation> operations;
  final DateTime timestamp;
  final TransactionStatus status;

  const Transaction({
    required this.id,
    required this.operations,
    required this.timestamp,
    this.status = TransactionStatus.pending,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) => _$TransactionFromJson(json);
  Map<String, dynamic> toJson() => _$TransactionToJson(this);
}

/// Status of a transaction
enum TransactionStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('committed')
  committed,
  @JsonValue('failed')
  failed,
  @JsonValue('synced')
  synced,
}

/// Result of a transaction
@JsonSerializable()
class TransactionResult {
  final TxId txId;
  final TransactionStatus status;
  final String? error;
  final DateTime timestamp;

  const TransactionResult({
    required this.txId,
    required this.status,
    this.error,
    required this.timestamp,
  });

  factory TransactionResult.fromJson(Map<String, dynamic> json) => _$TransactionResultFromJson(json);
  Map<String, dynamic> toJson() => _$TransactionResultToJson(this);
}

/// Authentication state
@JsonSerializable()
class AuthUser {
  final String id;
  final String email;
  final String? refreshToken;
  final Map<String, dynamic> metadata;

  const AuthUser({
    required this.id,
    required this.email,
    this.refreshToken,
    this.metadata = const {},
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => _$AuthUserFromJson(json);
  Map<String, dynamic> toJson() => _$AuthUserToJson(this);
}

/// Lookup reference for transactions (find entity by attribute value)
@JsonSerializable()
class LookupRef {
  final String entityType;
  final String attribute;
  final dynamic value;

  const LookupRef({
    required this.entityType,
    required this.attribute,
    required this.value,
  });

  factory LookupRef.fromJson(Map<String, dynamic> json) => _$LookupRefFromJson(json);
  Map<String, dynamic> toJson() => _$LookupRefToJson(this);
}

/// Transaction chunk - represents a chainable transaction operation
class TransactionChunk {
  final List<Operation> operations;

  const TransactionChunk(this.operations);

  /// Merge with another transaction chunk
  TransactionChunk merge(TransactionChunk other) {
    return TransactionChunk([...operations, ...other.operations]);
  }
}

/// Exception thrown by InstantDB operations
class InstantException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const InstantException({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'InstantException: $message${code != null ? ' ($code)' : ''}';
}