// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'types.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Triple _$TripleFromJson(Map<String, dynamic> json) => Triple(
  entityId: json['entityId'] as String,
  attribute: json['attribute'] as String,
  value: json['value'],
  txId: json['txId'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  retracted: json['retracted'] as bool? ?? false,
);

Map<String, dynamic> _$TripleToJson(Triple instance) => <String, dynamic>{
  'entityId': instance.entityId,
  'attribute': instance.attribute,
  'value': instance.value,
  'txId': instance.txId,
  'createdAt': instance.createdAt.toIso8601String(),
  'retracted': instance.retracted,
};

TripleChange _$TripleChangeFromJson(Map<String, dynamic> json) => TripleChange(
  type: $enumDecode(_$ChangeTypeEnumMap, json['type']),
  triple: Triple.fromJson(json['triple'] as Map<String, dynamic>),
);

Map<String, dynamic> _$TripleChangeToJson(TripleChange instance) =>
    <String, dynamic>{
      'type': _$ChangeTypeEnumMap[instance.type]!,
      'triple': instance.triple,
    };

const _$ChangeTypeEnumMap = {
  ChangeType.add: 'add',
  ChangeType.retract: 'retract',
};

QueryResult _$QueryResultFromJson(Map<String, dynamic> json) => QueryResult(
  isLoading: json['isLoading'] as bool,
  data: json['data'] as Map<String, dynamic>?,
  error: json['error'] as String?,
);

Map<String, dynamic> _$QueryResultToJson(QueryResult instance) =>
    <String, dynamic>{
      'isLoading': instance.isLoading,
      'data': instance.data,
      'error': instance.error,
    };

InstantConfig _$InstantConfigFromJson(Map<String, dynamic> json) =>
    InstantConfig(
      persistenceDir: json['persistenceDir'] as String?,
      syncEnabled: json['syncEnabled'] as bool? ?? true,
      baseUrl: json['baseUrl'] as String? ?? 'https://api.instantdb.com',
      maxCacheSize: (json['maxCacheSize'] as num?)?.toInt() ?? 50 * 1024 * 1024,
      maxCachedQueries: (json['maxCachedQueries'] as num?)?.toInt() ?? 100,
      reconnectDelay: json['reconnectDelay'] == null
          ? const Duration(seconds: 1)
          : Duration(microseconds: (json['reconnectDelay'] as num).toInt()),
      verboseLogging: json['verboseLogging'] as bool? ?? false,
    );

Map<String, dynamic> _$InstantConfigToJson(InstantConfig instance) =>
    <String, dynamic>{
      'persistenceDir': instance.persistenceDir,
      'syncEnabled': instance.syncEnabled,
      'baseUrl': instance.baseUrl,
      'maxCacheSize': instance.maxCacheSize,
      'maxCachedQueries': instance.maxCachedQueries,
      'reconnectDelay': instance.reconnectDelay.inMicroseconds,
      'verboseLogging': instance.verboseLogging,
    };

Operation _$OperationFromJson(Map<String, dynamic> json) => Operation(
  type: $enumDecode(_$OperationTypeEnumMap, json['type']),
  entityType: json['entityType'] as String,
  entityId: json['entityId'] as String,
  data: json['data'] as Map<String, dynamic>?,
  options: json['options'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$OperationToJson(Operation instance) => <String, dynamic>{
  'type': _$OperationTypeEnumMap[instance.type]!,
  'entityType': instance.entityType,
  'entityId': instance.entityId,
  'data': instance.data,
  'options': instance.options,
};

const _$OperationTypeEnumMap = {
  OperationType.add: 'add',
  OperationType.update: 'update',
  OperationType.delete: 'delete',
  OperationType.retract: 'retract',
  OperationType.link: 'link',
  OperationType.unlink: 'unlink',
  OperationType.merge: 'merge',
};

Transaction _$TransactionFromJson(Map<String, dynamic> json) => Transaction(
  id: json['id'] as String,
  operations: (json['operations'] as List<dynamic>)
      .map((e) => Operation.fromJson(e as Map<String, dynamic>))
      .toList(),
  timestamp: DateTime.parse(json['timestamp'] as String),
  status:
      $enumDecodeNullable(_$TransactionStatusEnumMap, json['status']) ??
      TransactionStatus.pending,
);

Map<String, dynamic> _$TransactionToJson(Transaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'operations': instance.operations,
      'timestamp': instance.timestamp.toIso8601String(),
      'status': _$TransactionStatusEnumMap[instance.status]!,
    };

const _$TransactionStatusEnumMap = {
  TransactionStatus.pending: 'pending',
  TransactionStatus.committed: 'committed',
  TransactionStatus.failed: 'failed',
  TransactionStatus.synced: 'synced',
};

TransactionResult _$TransactionResultFromJson(Map<String, dynamic> json) =>
    TransactionResult(
      txId: json['txId'] as String,
      status: $enumDecode(_$TransactionStatusEnumMap, json['status']),
      error: json['error'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$TransactionResultToJson(TransactionResult instance) =>
    <String, dynamic>{
      'txId': instance.txId,
      'status': _$TransactionStatusEnumMap[instance.status]!,
      'error': instance.error,
      'timestamp': instance.timestamp.toIso8601String(),
    };

AuthUser _$AuthUserFromJson(Map<String, dynamic> json) => AuthUser(
  id: json['id'] as String,
  email: json['email'] as String,
  refreshToken: json['refreshToken'] as String?,
  metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
);

Map<String, dynamic> _$AuthUserToJson(AuthUser instance) => <String, dynamic>{
  'id': instance.id,
  'email': instance.email,
  'refreshToken': instance.refreshToken,
  'metadata': instance.metadata,
};

LookupRef _$LookupRefFromJson(Map<String, dynamic> json) => LookupRef(
  entityType: json['entityType'] as String,
  attribute: json['attribute'] as String,
  value: json['value'],
);

Map<String, dynamic> _$LookupRefToJson(LookupRef instance) => <String, dynamic>{
  'entityType': instance.entityType,
  'attribute': instance.attribute,
  'value': instance.value,
};
