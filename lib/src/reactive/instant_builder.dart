import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/types.dart';
import '../core/instant_db.dart';

/// Main reactive widget for InstantDB queries
class InstantBuilder extends StatefulWidget {
  final Map<String, dynamic> query;
  final Widget Function(BuildContext context, Map<String, dynamic> data) builder;
  final Widget Function(BuildContext context, String error)? errorBuilder;
  final Widget Function(BuildContext context)? loadingBuilder;

  const InstantBuilder({
    Key? key,
    required this.query,
    required this.builder,
    this.errorBuilder,
    this.loadingBuilder,
  }) : super(key: key);

  @override
  State<InstantBuilder> createState() => _InstantBuilderState();
}

class _InstantBuilderState extends State<InstantBuilder> {
  Signal<QueryResult>? _querySignal;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_querySignal == null) {
      final db = InstantProvider.of(context);
      _querySignal = db.query(widget.query);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final result = _querySignal?.value ?? QueryResult.loading();

      if (result.isLoading) {
        return widget.loadingBuilder?.call(context) ??
            const Center(child: CircularProgressIndicator());
      }

      if (result.hasError) {
        return widget.errorBuilder?.call(context, result.error!) ??
            Center(child: Text('Error: ${result.error}'));
      }

      if (result.hasData) {
        return widget.builder(context, result.data!);
      }

      return const SizedBox.shrink();
    });
  }
}

/// Generic typed version of InstantBuilder
class InstantBuilderTyped<T> extends StatefulWidget {
  final Map<String, dynamic> query;
  final T Function(Map<String, dynamic> data) transformer;
  final Widget Function(BuildContext context, T data) builder;
  final Widget Function(BuildContext context, String error)? errorBuilder;
  final Widget Function(BuildContext context)? loadingBuilder;

  const InstantBuilderTyped({
    Key? key,
    required this.query,
    required this.transformer,
    required this.builder,
    this.errorBuilder,
    this.loadingBuilder,
  }) : super(key: key);

  @override
  State<InstantBuilderTyped<T>> createState() => _InstantBuilderTypedState<T>();
}

class _InstantBuilderTypedState<T> extends State<InstantBuilderTyped<T>> {
  Signal<QueryResult>? _querySignal;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_querySignal == null) {
      final db = InstantProvider.of(context);
      _querySignal = db.query(widget.query);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final result = _querySignal?.value ?? QueryResult.loading();

      if (result.isLoading) {
        return widget.loadingBuilder?.call(context) ??
            const Center(child: CircularProgressIndicator());
      }

      if (result.hasError) {
        return widget.errorBuilder?.call(context, result.error!) ??
            Center(child: Text('Error: ${result.error}'));
      }

      if (result.hasData) {
        try {
          final transformedData = widget.transformer(result.data!);
          return widget.builder(context, transformedData);
        } catch (e) {
          return widget.errorBuilder?.call(context, 'Transformation error: $e') ??
              Center(child: Text('Transformation error: $e'));
        }
      }

      return const SizedBox.shrink();
    });
  }
}

/// Hook-style API for queries (requires a StatefulWidget context)
Signal<QueryResult> useInstantQuery(
  BuildContext context,
  Map<String, dynamic> query,
) {
  final db = InstantProvider.of(context);
  return db.query(query);
}

/// Provider widget for InstantDB instance
class InstantProvider extends InheritedWidget {
  final InstantDB db;

  const InstantProvider({
    Key? key,
    required this.db,
    required Widget child,
  }) : super(key: key, child: child);

  static InstantDB of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<InstantProvider>();
    if (provider == null) {
      throw Exception('InstantProvider not found in widget tree. '
          'Make sure to wrap your app with InstantProvider.');
    }
    return provider.db;
  }

  @override
  bool updateShouldNotify(InstantProvider oldWidget) => db != oldWidget.db;
}

/// Widget that listens to authentication state changes
class AuthBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, AuthUser? user) builder;

  const AuthBuilder({
    Key? key,
    required this.builder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final db = InstantProvider.of(context);
    
    return Watch((context) {
      final user = db.auth.currentUser.value;
      return builder(context, user);
    });
  }
}

/// Widget that shows content only when authenticated
class AuthGuard extends StatelessWidget {
  final Widget child;
  final Widget? fallback;
  final Widget Function(BuildContext context)? loginBuilder;

  const AuthGuard({
    Key? key,
    required this.child,
    this.fallback,
    this.loginBuilder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AuthBuilder(
      builder: (context, user) {
        if (user != null) {
          return child;
        }
        
        return fallback ?? 
               loginBuilder?.call(context) ?? 
               const Center(child: Text('Please sign in'));
      },
    );
  }
}

/// Widget that shows connection status
class ConnectionStatusBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, bool isOnline) builder;

  const ConnectionStatusBuilder({
    Key? key,
    required this.builder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final db = InstantProvider.of(context);
    
    return Watch((context) {
      final isOnline = db.isOnline.value;
      return builder(context, isOnline);
    });
  }
}

/// Extension for common data transformations
extension InstantBuilderExtensions on InstantBuilder {
  /// Create a builder for a list of entities
  static InstantBuilderTyped<List<Map<String, dynamic>>> list({
    Key? key,
    required String entityType,
    Map<String, dynamic>? where,
    Map<String, dynamic>? orderBy,
    int? limit,
    int? offset,
    Map<String, dynamic>? include,
    required Widget Function(BuildContext context, List<Map<String, dynamic>> items) builder,
    Widget Function(BuildContext context, String error)? errorBuilder,
    Widget Function(BuildContext context)? loadingBuilder,
  }) {
    final query = <String, dynamic>{
      entityType: <String, dynamic>{
        if (where != null) 'where': where,
        if (orderBy != null) 'orderBy': orderBy,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (include != null) 'include': include,
      },
    };

    return InstantBuilderTyped<List<Map<String, dynamic>>>(
      key: key,
      query: query,
      transformer: (data) => (data[entityType] as List).cast<Map<String, dynamic>>(),
      builder: builder,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );
  }

  /// Create a builder for a single entity
  static InstantBuilderTyped<Map<String, dynamic>?> single({
    Key? key,
    required String entityType,
    required String id,
    Map<String, dynamic>? include,
    required Widget Function(BuildContext context, Map<String, dynamic>? item) builder,
    Widget Function(BuildContext context, String error)? errorBuilder,
    Widget Function(BuildContext context)? loadingBuilder,
  }) {
    final query = <String, dynamic>{
      entityType: <String, dynamic>{
        'where': {'id': id},
        'limit': 1,
        if (include != null) 'include': include,
      },
    };

    return InstantBuilderTyped<Map<String, dynamic>?>(
      key: key,
      query: query,
      transformer: (data) {
        final items = (data[entityType] as List).cast<Map<String, dynamic>>();
        return items.isNotEmpty ? items.first : null;
      },
      builder: builder,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );
  }
}