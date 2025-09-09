import 'dart:async';
import 'dart:convert';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/types.dart';
import '../core/logging_config.dart';
import '../storage/storage_interface.dart';
import '../sync/sync_engine.dart';

/// Query engine that executes InstaQL queries reactively
class QueryEngine {
  final StorageInterface _store;
  SyncEngine? _syncEngine;
  final Map<String, Signal<QueryResult>> _queryCache = {};
  late final StreamSubscription _storeSubscription;
  Timer? _batchTimer;
  final Set<String> _pendingQueryUpdates = {};
  final Set<String> _subscribedQueries = {};

  // Logger for query engine
  static final _logger = InstantDBLogging.queryEngine;

  QueryEngine(this._store, [this._syncEngine]) {
    // Listen to store changes and invalidate affected queries
    _logger.debug(
      'Setting up store change listener - StoreType: ${_store.runtimeType}',
    );
    _storeSubscription = _store.changes.listen((change) {
      InstantDBLogging.logQueryEvent(
        'CHANGE_RECEIVED',
        'store',
        reason: '${change.type}:${change.triple.entityId}',
      );
      _handleStoreChange(change);
    });
  }

  /// Set the sync engine (called after initialization)
  void setSyncEngine(SyncEngine syncEngine) {
    _syncEngine = syncEngine;

    // When sync engine is connected, send all queries to establish subscriptions
    if (syncEngine.connectionStatus.value) {
      InstantDBLogging.root.debug(
        'QueryEngine: Already connected, sending ${_queryCache.length} queries to establish subscriptions',
      );
      for (final queryKey in _queryCache.keys) {
        final query = _parseQueryKey(queryKey);
        syncEngine.sendQuery(query);
        _subscribedQueries.add(queryKey);
      }
    }

    // Use effect to react to connection status changes
    effect(() {
      final isConnected = syncEngine.connectionStatus.value;
      if (isConnected) {
        InstantDBLogging.root.debug(
          'QueryEngine: Connection established, checking for unsubscribed queries',
        );
        // When connected, send any queries that haven't been subscribed yet
        for (final queryKey in _queryCache.keys) {
          if (!_subscribedQueries.contains(queryKey)) {
            InstantDBLogging.root.debug(
              'QueryEngine: Sending unsubscribed query: $queryKey',
            );
            final query = _parseQueryKey(queryKey);
            syncEngine.sendQuery(query);
            _subscribedQueries.add(queryKey);
          }
        }
      }
    });
  }

  /// Execute a query and return a reactive signal
  Signal<QueryResult> query(Map<String, dynamic> query) {
    final queryKey = _generateQueryKey(query);

    // Return cached query if exists
    if (_queryCache.containsKey(queryKey)) {
      InstantDBLogging.logQueryEvent('CACHE_HIT', queryKey);
      return _queryCache[queryKey]!;
    }

    InstantDBLogging.logQueryEvent('NEW_QUERY', queryKey);

    // Check sync engine cache SYNCHRONOUSLY for immediate data availability
    QueryResult initialResult = QueryResult.loading();
    if (_syncEngine != null) {
      // Try to get initial data from cache synchronously
      final cachedResults = <String, dynamic>{};
      bool hasAnyData = false;
      
      for (final entry in query.entries) {
        final entityType = entry.key;
        final cachedData = _syncEngine!.getCachedQueryResult(entityType);
        
        if (cachedData != null && cachedData.isNotEmpty) {
          InstantDBLogging.root.info(
            'QueryEngine: Found cached data for $entityType: ${cachedData.length} documents (sync check)',
          );
          
          // Apply filters if query has conditions
          Map<String, dynamic> entityQuery = {};
          if (entry.value is Map) {
            final queryValue = entry.value as Map;
            if (queryValue.containsKey('\$')) {
              final dollarClause = queryValue['\$'];
              if (dollarClause is Map) {
                entityQuery = Map<String, dynamic>.from(dollarClause);
              }
            } else {
              entityQuery = Map<String, dynamic>.from(queryValue);
            }
          }
          
          final filteredData = _applyQueryFilters(cachedData, entityQuery);
          cachedResults[entityType] = filteredData;
          hasAnyData = true;
        } else {
          // Even if no cached data, include empty array to match expected format
          cachedResults[entityType] = [];
        }
      }
      
      if (hasAnyData) {
        InstantDBLogging.root.info(
          'QueryEngine: Initializing query with cached data for immediate availability',
        );
        initialResult = QueryResult.success(cachedResults);
      }
    }

    // Create new reactive query with initial cached data if available
    final resultSignal = signal(initialResult);
    _queryCache[queryKey] = resultSignal;

    // Send query to InstantDB to establish subscription
    if (_syncEngine != null && !_subscribedQueries.contains(queryKey)) {
      InstantDBLogging.root.debug(
        'QueryEngine: Sending query to sync engine for subscription',
      );
      _syncEngine!.sendQuery(query);
      _subscribedQueries.add(queryKey);
    } else {
      InstantDBLogging.root.debug(
        'QueryEngine: Not sending query - syncEngine: ${_syncEngine != null}, already subscribed: ${_subscribedQueries.contains(queryKey)}',
      );
    }

    // Execute query asynchronously
    _executeQuery(query, resultSignal);

    return resultSignal;
  }

  Future<void> _executeQuery(
    Map<String, dynamic> query,
    Signal<QueryResult> resultSignal,
  ) async {
    try {
      final result = await _processQuery(query);
      resultSignal.value = QueryResult.success(result);
    } catch (e, stackTrace) {
      InstantDBLogging.root.severe('Query execution error', e, stackTrace);
      resultSignal.value = QueryResult.error(e.toString());
    }
  }

  Future<Map<String, dynamic>> _processQuery(Map<String, dynamic> query) async {
    final results = <String, dynamic>{};

    for (final entry in query.entries) {
      final entityType = entry.key;

      // Handle different types of query values
      Map<String, dynamic> entityQuery = {};
      if (entry.value is Map) {
        final queryValue = entry.value as Map;

        // Check for React-style $ syntax
        if (queryValue.containsKey('\$')) {
          // Extract query from $ clause (React API compatibility)
          final dollarClause = queryValue['\$'];
          if (dollarClause is Map) {
            entityQuery = Map<String, dynamic>.from(dollarClause);
          }
        } else {
          // Direct query format (backward compatibility)
          entityQuery = Map<String, dynamic>.from(queryValue);
        }
      }

      // Execute entity query
      final entities = await _queryEntities(entityType, entityQuery);
      results[entityType] = entities;
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> _queryEntities(
    String entityType,
    Map<String, dynamic> query,
  ) async {
    // Check sync engine cache first for immediate data availability
    if (_syncEngine != null) {
      final cachedData = _syncEngine!.getCachedQueryResult(entityType);
      if (cachedData != null && cachedData.isNotEmpty) {
        InstantDBLogging.root.debug(
          'Using cached query result for $entityType: ${cachedData.length} documents',
        );
        // Apply query filters to cached data if needed
        return _applyQueryFilters(cachedData, query);
      }
    }

    // Extract query parameters
    final where = query['where'] as Map<String, dynamic>?;

    // Support both 'order' (React/server style) and 'orderBy' (Flutter style)
    final orderByInput = query['order'] ?? query['orderBy'];

    // Convert orderBy to expected List<String> format if it's a Map
    List<String>? orderBy;
    if (orderByInput is Map) {
      // Convert {'field': 'direction'} to ['field direction'] format
      orderBy = orderByInput.entries.map((e) => '${e.key} ${e.value}').toList();
    } else if (orderByInput is List) {
      // Handle List<Map> format like [{'createdAt': 'desc'}]
      final listItems = orderByInput;
      orderBy = listItems.map((item) {
        if (item is Map) {
          // Convert {'field': 'direction'} to 'field direction'
          return item.entries.map((e) => '${e.key} ${e.value}').join(' ');
        } else {
          return item.toString();
        }
      }).toList();
    } else if (orderByInput is String) {
      orderBy = [orderByInput];
    }

    final limit = query['limit'] as int?;
    final offset = query['offset'] as int?;
    final include = query['include'] as Map<String, dynamic>?;
    final aggregate = query['\$aggregate'] as Map<String, dynamic>?;
    final groupBy = query['\$groupBy'] as List<String>?;

    // Query entities from store
    var entities = await _store.queryEntities(
      entityType: entityType,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      aggregate: aggregate,
      groupBy: groupBy,
    );

    // Process includes (nested queries)
    if (include != null) {
      entities = await _processIncludes(entities, include);
    }

    return entities;
  }

  Future<List<Map<String, dynamic>>> _processIncludes(
    List<Map<String, dynamic>> entities,
    Map<String, dynamic> includes,
  ) async {
    for (final entity in entities) {
      for (final includeEntry in includes.entries) {
        final relationName = includeEntry.key;
        final relationQuery = includeEntry.value is Map
            ? Map<String, dynamic>.from(includeEntry.value as Map)
            : null;

        // Simple relation resolution based on naming conventions
        if (relationName.endsWith('s')) {
          // One-to-many relation (e.g., "posts")
          // Keep the relationName as-is since it's already plural (which matches our entity types)

          // For one-to-many relationships, we need to determine the foreign key
          // Convention: posts belong to a user via 'authorId', 'userId', etc.
          // Try common patterns
          String foreignKey;
          final parentType = entity['__type']?.toString() ?? '';
          final singularParentType = parentType.endsWith('s')
              ? parentType.substring(0, parentType.length - 1)
              : parentType;

          // Try specific naming patterns first
          if (relationName == 'posts') {
            foreignKey = 'authorId'; // posts commonly use authorId
          } else {
            foreignKey =
                '${singularParentType}Id'; // fallback to standard pattern
          }

          final whereClause = <String, dynamic>{foreignKey: entity['id']};

          // Merge with any additional where conditions from the relation query
          if (relationQuery != null && relationQuery['where'] != null) {
            whereClause.addAll(relationQuery['where'] as Map<String, dynamic>);
          }

          final queryMap = <String, dynamic>{'where': whereClause};

          // Add other query parameters
          if (relationQuery != null) {
            for (final entry in relationQuery.entries) {
              if (entry.key != 'where') {
                queryMap[entry.key] = entry.value;
              }
            }
          }

          final relatedEntities = await _queryEntities(relationName, queryMap);
          entity[relationName] = relatedEntities;
        } else {
          // One-to-one relation (e.g., "author")
          final foreignKey = '${relationName}Id';

          if (entity.containsKey(foreignKey)) {
            // Map common relationship names to actual entity types
            String entityType;
            switch (relationName) {
              case 'author':
                entityType = 'users';
                break;
              case 'user':
                entityType = 'users';
                break;
              default:
                entityType = '${relationName}s'; // Pluralize by default
            }

            final queryMap = <String, dynamic>{
              'where': {'id': entity[foreignKey]},
              'limit': 1,
            };

            // Add other query parameters
            if (relationQuery != null) {
              for (final entry in relationQuery.entries) {
                if (entry.key != 'where') {
                  queryMap[entry.key] = entry.value;
                } else {
                  // Merge where conditions
                  queryMap['where'].addAll(entry.value as Map<String, dynamic>);
                }
              }
            }

            final relatedEntity = await _queryEntities(entityType, queryMap);

            entity[relationName] = relatedEntity.isNotEmpty
                ? relatedEntity.first
                : null;
          }
        }
      }
    }

    return entities;
  }

  void _handleStoreChange(TripleChange change) {
    // Skip internal system changes to avoid feedback loops
    if (change.triple.entityId == '__query_invalidation') {
      return;
    }

    // Collect queries that need updating
    for (final entry in _queryCache.entries) {
      final query = _parseQueryKey(entry.key);
      if (_queryAffectedByChange(query, change)) {
        _pendingQueryUpdates.add(entry.key);
      }
    }

    // Batch query updates with a larger delay to avoid excessive re-queries
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 200), () {
      // Execute all pending query updates
      for (final queryKey in _pendingQueryUpdates) {
        final query = _parseQueryKey(queryKey);
        final resultSignal = _queryCache[queryKey];
        if (resultSignal != null) {
          _executeQuery(query, resultSignal);
        }
      }
      _pendingQueryUpdates.clear();
    });
  }

  /// Apply query filters to cached data
  List<Map<String, dynamic>> _applyQueryFilters(
    List<Map<String, dynamic>> data,
    Map<String, dynamic> query,
  ) {
    var filteredData = List<Map<String, dynamic>>.from(data);

    // Apply where clause filters if present
    final where = query['where'] as Map<String, dynamic>?;
    if (where != null) {
      filteredData = filteredData.where((doc) {
        return _evaluateWhereCondition(doc, where);
      }).toList();
    }

    // Apply orderBy if present
    final orderByInput = query['order'] ?? query['orderBy'];
    if (orderByInput != null) {
      // Convert orderBy to expected format
      List<String>? orderBy;
      if (orderByInput is Map) {
        orderBy = orderByInput.entries.map((e) => '${e.key} ${e.value}').toList();
      } else if (orderByInput is List) {
        orderBy = orderByInput.map((item) {
          if (item is Map) {
            return item.entries.map((e) => '${e.key} ${e.value}').join(' ');
          }
          return item.toString();
        }).toList();
      } else if (orderByInput is String) {
        orderBy = [orderByInput];
      }

      if (orderBy != null) {
        // Apply sorting
        for (final orderClause in orderBy.reversed) {
          final parts = orderClause.split(' ');
          final field = parts[0];
          final isDesc = parts.length > 1 && parts[1].toLowerCase() == 'desc';

          filteredData.sort((a, b) {
            final aValue = a[field];
            final bValue = b[field];
            
            if (aValue == null && bValue == null) return 0;
            if (aValue == null) return isDesc ? 1 : -1;
            if (bValue == null) return isDesc ? -1 : 1;

            final comparison = Comparable.compare(aValue as Comparable, bValue as Comparable);
            return isDesc ? -comparison : comparison;
          });
        }
      }
    }

    // Apply limit if present
    final limit = query['limit'] as int?;
    if (limit != null && limit > 0) {
      filteredData = filteredData.take(limit).toList();
    }

    // Apply offset if present
    final offset = query['offset'] as int?;
    if (offset != null && offset > 0) {
      filteredData = filteredData.skip(offset).toList();
    }

    return filteredData;
  }

  /// Evaluate where conditions for filtering cached data
  bool _evaluateWhereCondition(Map<String, dynamic> doc, Map<String, dynamic> where) {
    for (final entry in where.entries) {
      final field = entry.key;
      final condition = entry.value;
      final fieldValue = doc[field];

      if (condition is Map) {
        // Handle operators like $eq, $ne, $gt, $lt, etc.
        for (final op in condition.entries) {
          final operator = op.key;
          final compareValue = op.value;

          switch (operator) {
            case '\$eq':
              if (fieldValue != compareValue) return false;
              break;
            case '\$ne':
              if (fieldValue == compareValue) return false;
              break;
            case '\$gt':
              if (fieldValue == null || (fieldValue as Comparable).compareTo(compareValue) <= 0) return false;
              break;
            case '\$gte':
              if (fieldValue == null || (fieldValue as Comparable).compareTo(compareValue) < 0) return false;
              break;
            case '\$lt':
              if (fieldValue == null || (fieldValue as Comparable).compareTo(compareValue) >= 0) return false;
              break;
            case '\$lte':
              if (fieldValue == null || (fieldValue as Comparable).compareTo(compareValue) > 0) return false;
              break;
            case '\$in':
              if (compareValue is List && !compareValue.contains(fieldValue)) return false;
              break;
            case '\$nin':
              if (compareValue is List && compareValue.contains(fieldValue)) return false;
              break;
            case '\$exists':
              final exists = doc.containsKey(field);
              if ((compareValue == true && !exists) || (compareValue == false && exists)) return false;
              break;
            case '\$isNull':
              if ((compareValue == true && fieldValue != null) || (compareValue == false && fieldValue == null)) return false;
              break;
            default:
              // Unknown operator, skip
              break;
          }
        }
      } else {
        // Direct equality check
        if (fieldValue != condition) return false;
      }
    }
    
    return true;
  }

  bool _queryAffectedByChange(Map<String, dynamic> query, TripleChange change) {
    // Check if the query is affected by the change for any entity type

    // If it's a __type change, check if the query includes that entity type
    if (change.triple.attribute == '__type') {
      final entityType = change.triple.value as String;
      return query.containsKey(entityType);
    }

    // For any other attribute changes, check all entity types in the query
    // This ensures all queries (todos, tiles, messages, etc.) are properly updated
    for (final _ in query.keys) {
      // This is a broad match - any change could affect any query
      // In production, this could be optimized to check specific relationships
      return true;
    }

    return false;
  }

  String _generateQueryKey(Map<String, dynamic> query) {
    return jsonEncode(query);
  }

  Map<String, dynamic> _parseQueryKey(String queryKey) {
    return jsonDecode(queryKey) as Map<String, dynamic>;
  }

  /// Clear query cache
  void clearCache() {
    _queryCache.clear();
  }

  /// Dispose query engine
  void dispose() {
    _batchTimer?.cancel();
    _storeSubscription.cancel();
    _queryCache.clear();
  }
}

/// Query builder for fluent API
class QueryBuilder {
  final QueryEngine _engine;
  final Map<String, dynamic> _query = {};

  QueryBuilder(this._engine);

  /// Add an entity query
  QueryBuilder entity(
    String entityType, {
    Map<String, dynamic>? where,
    Map<String, dynamic>? orderBy,
    int? limit,
    int? offset,
    Map<String, dynamic>? include,
  }) {
    final entityQuery = <String, dynamic>{};

    if (where != null) entityQuery['where'] = where;
    if (orderBy != null) entityQuery['orderBy'] = orderBy;
    if (limit != null) entityQuery['limit'] = limit;
    if (offset != null) entityQuery['offset'] = offset;
    if (include != null) entityQuery['include'] = include;

    _query[entityType] = entityQuery;
    return this;
  }

  /// Execute the query
  Signal<QueryResult> execute() {
    return _engine.query(_query);
  }
}
