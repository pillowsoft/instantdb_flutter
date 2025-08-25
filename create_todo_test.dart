import 'dart:io';
import 'lib/instantdb_flutter.dart';

/// Simple script to create a todo and observe the sync logging
Future<void> main() async {
  print('\n=== TODO CREATION SYNC TEST ===\n');
  
  // Initialize with detailed logging
  final db = await InstantDB.init(
    appId: '82100963-e4c0-4f02-b49b-b6fa92d64a17',
    config: const InstantConfig(
      verboseLogging: true,
      syncEnabled: true,
    ),
  );
  
  print('✓ InstantDB initialized and connected');
  
  // Wait for connection
  while (!db.isOnline.value) {
    print('Waiting for connection...');
    await Future.delayed(Duration(seconds: 1));
  }
  
  print('✓ Connection established');
  print('✓ Creating test todo...\n');
  
  // Create a simple todo
  final todoId = db.id();
  final todoData = {
    'id': todoId,
    'text': 'Test sync todo - ${DateTime.now().millisecondsSinceEpoch}',
    'completed': false,
    'createdAt': DateTime.now().toIso8601String(),
  };
  
  print('Todo data: $todoData');
  
  try {
    // Create and execute transaction
    final operations = db.create('todos', todoData);
    print('\\n=== EXECUTING TRANSACTION ===');
    print('Operations: ${operations.length}');
    
    final result = await db.transact(operations);
    print('Transaction result: ${result.status}');
    
    if (result.error != null) {
      print('❌ Transaction error: ${result.error}');
    } else {
      print('✅ Transaction successful');
    }
    
    // Query back to verify
    print('\\n=== QUERYING TODOS ===');
    await Future.delayed(Duration(seconds: 2));
    
    final queryResult = await db.queryOnce({'todos': {}});
    if (queryResult.hasData) {
      final todos = queryResult.data?['todos'] as List?;
      print('Found ${todos?.length ?? 0} todos:');
      todos?.forEach((todo) {
        print('  - ${todo['id']}: "${todo['text']}"');
      });
    }
    
  } catch (e, stackTrace) {
    print('❌ Error: $e');
    print('Stack trace: $stackTrace');
  }
  
  print('\\n=== TEST COMPLETE ===');
  print('Check the logs above for transaction and sync details.');
  
  await db.dispose();
  exit(0);
}