import 'dart:io';
import 'package:instantdb_flutter/instantdb_flutter.dart';

Future<void> main() async {
  print('=== ReaxDB Sync Debug Test ===');
  
  // Initialize first instance
  final db1 = await InstantDB.init(
    appId: '82100963-e4c0-4f02-b49b-b6fa92d64a17',
    config: const InstantConfig(
      storageBackend: StorageBackend.sqlite,
      verboseLogging: true,
      syncEnabled: true,
    ),
  );
  
  print('DB1 initialized successfully');
  await Future.delayed(Duration(seconds: 2));
  
  // Initialize second instance (simulating another device)
  final db2 = await InstantDB.init(
    appId: '82100963-e4c0-4f02-b49b-b6fa92d64a17',
    config: const InstantConfig(
      storageBackend: StorageBackend.sqlite,
      verboseLogging: true,
      syncEnabled: true,
      persistenceDir: './test_db2', // Different directory
    ),
  );
  
  print('DB2 initialized successfully');
  await Future.delayed(Duration(seconds: 2));
  
  // Subscribe to todos on both instances
  final todos1 = db1.query({'todos': {}});
  final todos2 = db2.query({'todos': {}});
  
  print('Queries set up on both instances');
  
  // Listen to changes on both instances
  todos1.subscribe((result) {
    print('DB1 - Todos updated: ${result.data['todos']?.length ?? 0} items');
    if (result.data['todos'] != null) {
      for (var todo in result.data['todos']) {
        print('  DB1 Todo: ${todo['text']} (${todo['id']})');
      }
    }
  });
  
  todos2.subscribe((result) {
    print('DB2 - Todos updated: ${result.data['todos']?.length ?? 0} items');
    if (result.data['todos'] != null) {
      for (var todo in result.data['todos']) {
        print('  DB2 Todo: ${todo['text']} (${todo['id']})');
      }
    }
  });
  
  print('Subscriptions active, waiting 3 seconds...');
  await Future.delayed(Duration(seconds: 3));
  
  // Create a todo on DB1
  print('\n=== Creating todo on DB1 ===');
  final createOps = db1.tx['todos'].create({
    'text': 'Test todo from DB1 - ${DateTime.now().millisecondsSinceEpoch}',
    'done': false,
  });
  
  final result1 = await db1.transactChunk(createOps);
  print('DB1 transaction result: ${result1.status}');
  
  // Wait for sync
  print('Waiting 5 seconds for sync...');
  await Future.delayed(Duration(seconds: 5));
  
  // Create a todo on DB2
  print('\n=== Creating todo on DB2 ===');
  final createOps2 = db2.tx['todos'].create({
    'text': 'Test todo from DB2 - ${DateTime.now().millisecondsSinceEpoch}',
    'done': false,
  });
  
  final result2 = await db2.transactChunk(createOps2);
  print('DB2 transaction result: ${result2.status}');
  
  // Wait for sync
  print('Waiting 5 seconds for final sync...');
  await Future.delayed(Duration(seconds: 5));
  
  // Check final state
  print('\n=== Final State Check ===');
  final finalTodos1 = await db1.queryOnce({'todos': {}});
  final finalTodos2 = await db2.queryOnce({'todos': {}});
  
  print('DB1 final todos: ${finalTodos1.data['todos']?.length ?? 0}');
  print('DB2 final todos: ${finalTodos2.data['todos']?.length ?? 0}');
  
  if ((finalTodos1.data['todos']?.length ?? 0) == (finalTodos2.data['todos']?.length ?? 0) &&
      (finalTodos1.data['todos']?.length ?? 0) >= 2) {
    print('\n✅ SYNC TEST PASSED: Both instances have same number of todos');
  } else {
    print('\n❌ SYNC TEST FAILED: Instances have different todo counts');
    print('   DB1: ${finalTodos1.data['todos']?.length ?? 0} todos');
    print('   DB2: ${finalTodos2.data['todos']?.length ?? 0} todos');
  }
  
  await db1.dispose();
  await db2.dispose();
  
  exit(0);
}