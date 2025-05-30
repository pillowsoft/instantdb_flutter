import 'dart:async';
import 'dart:convert';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/types.dart';
import '../storage/triple_store.dart';

/// Query engine that executes InstaQL queries reactively
class QueryEngine {
  final TripleStore _store;
  final Map<String, Signal<QueryResult>> _queryCache = {};
  late final StreamSubscription _storeSubscription;

  QueryEngine(this._store) {
    // Listen to store changes and invalidate affected queries
    _storeSubscription = _store.changes.listen(_handleStoreChange);
  }

  /// Execute a query and return a reactive signal
  Signal<QueryResult> query(Map<String, dynamic> query) {
    final queryKey = _generateQueryKey(query);

    // Return cached query if exists
    if (_queryCache.containsKey(queryKey)) {
      return _queryCache[queryKey]!;
    }

    // Create new reactive query
    final resultSignal = signal(QueryResult.loading());
    _queryCache[queryKey] = resultSignal;

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
      print('Query execution error: $e\n$stackTrace');
      resultSignal.value = QueryResult.error(e.toString());
    }
  }

  Future<Map<String, dynamic>> _processQuery(Map<String, dynamic> query) async {
    final results = <String, dynamic>{};

    for (final entry in query.entries) {
      final entityType = entry.key;
      final entityQuery = entry.value as Map<String, dynamic>?;

      // Execute entity query
      final entities = await _queryEntities(entityType, entityQuery ?? {});
      results[entityType] = entities;
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> _queryEntities(
    String entityType,
    Map<String, dynamic> query,
  ) async {
    // Extract query parameters
    final where = query['where'] as Map<String, dynamic>?;
    final orderBy = query['orderBy'] as Map<String, dynamic>?;
    final limit = query['limit'] as int?;
    final offset = query['offset'] as int?;
    final include = query['include'] as Map<String, dynamic>?;

    // Convert orderBy to string format
    String? orderByString;
    if (orderBy != null) {
      final field = orderBy.keys.first;
      final direction = orderBy[field] as String;
      orderByString = '$field ${direction.toLowerCase()}';
    }

    // Query entities from store
    var entities = await _store.queryEntities(
      entityType: entityType,
      where: where,
      orderBy: orderByString,
      limit: limit,
      offset: offset,
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
        final relationQuery = includeEntry.value as Map<String, dynamic>?;

        // Simple relation resolution based on naming conventions
        if (relationName.endsWith('s')) {
          // One-to-many relation (e.g., "posts")
          final singularName = relationName.substring(0, relationName.length - 1);
          final foreignKey = '${entity['__type']}Id';

          final relatedEntities = await _queryEntities(singularName, {
            'where': {foreignKey: entity['id']},
            ...?relationQuery,
          });

          entity[relationName] = relatedEntities;
        } else {
          // One-to-one relation (e.g., "author")
          final foreignKey = '${relationName}Id';
          
          if (entity.containsKey(foreignKey)) {
            final relatedEntity = await _queryEntities(relationName, {
              'where': {'id': entity[foreignKey]},
              'limit': 1,
              ...?relationQuery,
            });

            entity[relationName] = relatedEntity.isNotEmpty ? relatedEntity.first : null;
          }
        }
      }
    }

    return entities;
  }

  void _handleStoreChange(TripleChange change) {
    // Simple invalidation - invalidate all queries for now
    // In production, this would be more sophisticated
    for (final entry in _queryCache.entries) {
      final query = _parseQueryKey(entry.key);
      if (_queryAffectedByChange(query, change)) {
        _executeQuery(query, entry.value);
      }
    }
  }

  bool _queryAffectedByChange(Map<String, dynamic> query, TripleChange change) {
    // Check if the change affects this query
    final entityType = change.triple.value.toString();
    
    // If the triple is setting entity type
    if (change.triple.attribute == '__type') {
      return query.containsKey(entityType);
    }

    // For other attributes, check if any queried entity type could be affected
    // This is a simple implementation - production would be more precise
    return true;
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
  QueryBuilder entity(String entityType, {
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