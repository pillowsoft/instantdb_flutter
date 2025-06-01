# Reactivity Fix Summary

This document details the reactivity fixes applied to the InstantDB Flutter implementation.

## Update: Delete Operation Validation Errors Fixed

### Problem
Delete operations were failing with validation errors because entity IDs were being sent as arrays instead of strings:
```
Validation failed for tx-steps, hint: {data-type: tx-steps, input: [[delete-entity, [7acab2c9-01e8-4868-b4e5-2b94a5f0924c, 9d180c96-ce87-4ca1-ad3c-a7d77b067162, 1748658311547, 1748660872389], todos]]
```

### Root Cause
When processing query results with join-rows format where entity IDs come as arrays, the entire array was being converted to a string and stored as the entity ID for delete operations.

### Solution
1. **Fixed delete operation generation in sync_engine.dart**: Added logic to detect and fix corrupted entity IDs before sending to server
2. **Added validation in instant_db.dart**: The delete() method now validates and cleans entity IDs
3. **Updated triple_store.dart**: Added logic to detect and mark corrupted pending transactions as failed
4. **Prevented future corruption**: All delete operations now validate entity IDs before creating operations

### Code Changes
- sync_engine.dart: Added entity ID validation in delete operation processing
- instant_db.dart: Added entity ID cleaning in delete() method
- triple_store.dart: Added corrupted transaction detection in getPendingTransactions()

## Original Cloud Reactivity Fix

### The Problem
When running two instances of the app, changes made in one instance were not appearing in the other. The logs showed:
- Local transactions were successful (transact/transact-ok pairs)
- But NO incoming `transact` messages from other clients
- This indicated we weren't properly subscribed to receive updates

### Root Cause
The query subscription wasn't being established because:
1. Queries were executed locally but never sent to InstantDB server
2. Without sending queries, InstantDB doesn't know to send us updates

### The Fix
I made three key changes:

#### 1. Added `sendQuery()` method to SyncEngine
```dart
void sendQuery(Map<String, dynamic> query) {
  // Sends 'add-query' message to InstantDB
  // This establishes a subscription for that query pattern
}
```

#### 2. Modified QueryEngine to call sendQuery
When a query is executed:
- Runs locally against triple store
- Sends query to InstantDB via `sendQuery()`
- Tracks subscribed queries to avoid duplicates

#### 3. Added connection status listener
When WebSocket connects:
- All existing queries are re-sent to establish subscriptions
- This handles race conditions where queries run before connection

## Additional Reactivity Issues Fixed

### Problem 1: Todos showing without titles
**Root cause**: Missing attribute mapping for `todos.completed` field.
**Solution**: Added hardcoded mapping in sync_engine.dart for the missing attribute UUID.

### Problem 2: Excessive logging (860KB log files)
**Root cause**: Verbose logging of all WebSocket messages and operations.
**Solution**: Implemented InstantLogger with configurable verbosity levels.

### Problem 3: Feedback loop causing hundreds of transactions
**Root cause**: Store changes triggering query re-execution which created new transactions.
**Solution**: 
- Added deduplication logic in triple_store.dart
- Increased batch timer delay in query_engine.dart
- Added filtering for system entities

### Problem 4: Delete operations not updating UI
**Root cause**: Delete operations were not emitting proper change events.
**Solution**: Updated triple_store.dart to emit change events for each retracted triple during delete operations.

### Problem 5: Offline operations not syncing
**Root cause**: Pending transactions were processed before WebSocket authentication.
**Solution**: Moved pending transaction processing to occur after receiving init-ok message.

### Problem 6: Many duplicate transact-ok messages
**Root cause**: Duplicate data processing and missing deduplication.
**Solution**: Added data hashing and duplicate detection in refresh-ok message handling.

## Technical Details

### Join-rows Format
InstantDB returns query results in a datalog format with join-rows:
```
[[entityId, attributeId, value, timestamp], ...]
```

Sometimes entity IDs come as arrays themselves, requiring special handling:
```
[[[entityId, attr1, val1, ts1], attr2, val2, ts2], ...]
```

### Transaction Format
Delete operations must use this format:
```
['delete-entity', entityId, namespace]
```
Where entityId must be a string, not an array.

### Files Modified
1. lib/src/sync/sync_engine.dart
2. lib/src/storage/triple_store.dart
3. lib/src/core/instant_db.dart
4. lib/src/query/query_engine.dart
5. lib/src/core/logging.dart (created)
6. lib/src/core/types.dart

## Results
- ✅ Real-time sync between multiple app instances
- ✅ Todos display with proper titles
- ✅ Delete operations update UI immediately
- ✅ Offline operations sync when reconnecting
- ✅ Reduced log verbosity
- ✅ No more feedback loops
- ✅ Delete operations no longer fail with validation errors
- ✅ Clear All functionality works properly

## Testing the Fix
1. Run two instances of the app
2. Make changes in one instance
3. You should now see in the logs:
   - First instance: "Sending query to establish subscription"
   - When changes are made: "transact-ok" confirmations
   - Second instance: "Received transact message from another client"
   - UI updates automatically

## Architecture Note
This aligns with InstantDB's subscription model where queries themselves act as subscriptions. There's no separate "subscribe" operation - sending a query automatically subscribes you to updates matching that query pattern.