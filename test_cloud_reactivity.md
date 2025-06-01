# Testing Cloud Reactivity

## What was fixed
The issue was that when the UI performed queries, they were only executed locally against the triple store. The queries were never sent to InstantDB server, which meant no subscription was established to receive updates from other clients.

## Changes made
1. Added `sendQuery()` method to SyncEngine to send query messages to InstantDB
2. Modified QueryEngine to:
   - Accept a SyncEngine reference
   - Send queries to InstantDB when executed (establishing subscriptions)
   - Track subscribed queries to avoid duplicates
3. Updated InstantDB initialization to wire SyncEngine to QueryEngine

## How it works now
When `InstantBuilder` executes a query:
1. Query runs locally against triple store
2. Query is sent to InstantDB via WebSocket (`op: 'query'`)
3. InstantDB establishes a subscription for that query pattern
4. Updates from other clients trigger `transact` messages
5. UI automatically updates via reactive signals

## Testing steps
1. Run two instances of the example app
2. Add/update/delete todos in one instance
3. Changes should appear in the other instance within seconds
4. Check logs for:
   - "Sending query to establish subscription"
   - "Received transact message from another client"

## Expected behavior
- Local changes appear immediately
- Remote changes appear after a short network delay
- Both instances stay in sync
- Connection status indicator shows "Online"