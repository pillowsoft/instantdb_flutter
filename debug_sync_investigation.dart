import 'dart:io';
import 'lib/src/core/instant_db.dart';
import 'lib/src/core/types.dart';

/// Debug script to investigate todo sync issues between instances
/// This script creates a todo and monitors logging output to understand sync flow
Future<void> main() async {
  print('=== InstantDB Sync Investigation ===');
  print('Starting instance with detailed logging...\n');
  
  // Initialize InstantDB with verbose logging
  final db = await InstantDB.init(
    appId: 'your_app_id_here', // Replace with actual app ID
    config: const InstantConfig(
      verboseLogging: true,
      syncEnabled: true,
      storageBackend: StorageBackend.reaxdb,
    ),
  );
  
  print('✓ InstantDB initialized');
  print('✓ Instance ID: ${db.config}');
  print('✓ Storage backend: ${db.config.storageBackend.name}');
  print('✓ Sync enabled: ${db.config.syncEnabled}\n');
  
  // Wait for connection
  print('Waiting for sync connection...');
  var connectionChecks = 0;
  while (!db.isOnline.value && connectionChecks < 30) {
    await Future.delayed(Duration(seconds: 1));
    connectionChecks++;
    if (connectionChecks % 5 == 0) {
      print('Still waiting for connection... (${connectionChecks}s)');
    }
  }
  
  if (!db.isOnline.value) {
    print('❌ Failed to establish sync connection');
    exit(1);
  }
  
  print('✓ Sync connection established\n');
  
  // Create a test todo with detailed logging
  print('=== CREATING TEST TODO ===');
  final todoId = db.id();
  final testTodo = {
    'id': todoId,
    'text': 'Test todo for sync investigation - ${DateTime.now().millisecondsSinceEpoch}',
    'completed': false,
    'createdAt': DateTime.now().toIso8601String(),
  };
  
  print('Todo to create: $testTodo\n');
  
  try {
    // Create transaction operations
    final operations = db.create('todos', testTodo);
    print('Operations created: ${operations.length} operations');
    for (int i = 0; i < operations.length; i++) {
      final op = operations[i];
      print('  Operation $i: ${op.type.name} - ${op.entityType} - ${op.entityId}');
    }
    
    // Execute transaction
    print('\n=== EXECUTING TRANSACTION ===');
    final result = await db.transact(operations);
    print('Transaction result: ${result.status.name}');
    if (result.error != null) {
      print('Transaction error: ${result.error}');
    }
    
    // Wait a bit for sync to process
    print('\n=== WAITING FOR SYNC PROPAGATION ===');
    await Future.delayed(Duration(seconds: 3));
    
    // Query todos to verify local storage
    print('\n=== QUERYING TODOS LOCALLY ===');
    final queryResult = await db.queryOnce({'todos': {}});
    if (queryResult.hasError) {
      print('Query error: ${queryResult.error}');
    } else if (queryResult.hasData) {
      final todos = queryResult.data?['todos'] as List?;
      print('Local todos count: ${todos?.length ?? 0}');
      if (todos != null) {
        for (int i = 0; i < todos.length; i++) {
          final todo = todos[i];
          print('  Todo $i: ${todo['id']} - "${todo['text']}"');
          if (todo['id'] == todoId) {
            print('    ✓ Our test todo found locally!');
          }
        }
      }
    }
    
    print('\n=== SYNC INVESTIGATION COMPLETE ===');
    print('Key points to check:');
    print('1. Was the transaction applied locally?');
    print('2. Was the transaction sent to the server?');
    print('3. Did other instances receive the update?');
    print('\nTo test multi-instance sync:');
    print('1. Run this script in one terminal');
    print('2. Run the Flutter app in another terminal/device');
    print('3. Check if the todo appears in both instances');
    
  } catch (e, stackTrace) {
    print('❌ Error during transaction: $e');
    print('Stack trace: $stackTrace');
  }
  
  // Keep the script running for manual testing
  print('\n=== KEEPING ALIVE FOR MANUAL TESTING ===');
  print('Press Ctrl+C to exit');
  
  // Listen for todos changes
  final todosQuery = db.query({'todos': {}});
  todosQuery.value.addListener(() {
    print('\n🔄 TODOS QUERY UPDATED:');
    final result = todosQuery.value.value;
    if (result.hasData) {
      final todos = result.data?['todos'] as List?;
      print('Updated todos count: ${todos?.length ?? 0}');
      for (int i = 0; i < (todos?.length ?? 0); i++) {
        final todo = todos![i];
        print('  Todo $i: ${todo['id']} - "${todo['text']}"');
      }
    }
  });
  
  // Keep running
  while (true) {
    await Future.delayed(Duration(seconds: 10));
    print('Still running... Online: ${db.isOnline.value}');
  }
}