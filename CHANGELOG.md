## 0.2.4

### 🎯 Critical Fix: Entity Type Resolution in Datalog Conversion

**Fixed Entity Type Mismatch Bug**
* ✅ **Fixed entities being cached under wrong collection name** - Queries for 'conversations' no longer return 0 documents when entities lack __type field
* ✅ **Proper entity type detection** - Extract query entity type from response `data['q']` field and use it throughout conversion pipeline
* ✅ **Correct cache key resolution** - Entities are now cached under their query type instead of defaulting to 'todos'

**Technical Solution**
* ✅ **Query type extraction** - Parse the original query from response to determine intended entity type
* ✅ **Type propagation** - Pass entity type through entire datalog conversion pipeline
* ✅ **Smart grouping** - Use query type when grouping entities, fallback to __type field, then 'todos'
* ✅ **Cache alignment** - Ensure cached collection names match query collection names

### 📚 Impact

This release completes the datalog conversion fix trilogy. The critical bug was:

1. App queries for `{'conversations': {}}`
2. Server returns datalog with conversation entities
3. Entities lack __type field, so they default to 'todos'
4. Cache stores them under 'todos' key
5. Query engine looks for 'conversations' and finds nothing

**Now fixed**: Entities are cached under the correct collection name matching the original query.

---

## 0.2.3

### 🔥 Critical Fix: Race Condition in Query Execution

**Fixed Critical Race Condition**
* ✅ **Fixed queries returning 0 documents despite successful datalog conversion** - Eliminated race condition where queries returned empty results before cache was populated
* ✅ **Synchronous cache checking** - Queries now check cache synchronously before returning Signal, ensuring immediate data availability
* ✅ **Added "Reconstructed X entities" logging** - Clear logging confirms entities are successfully parsed from join-rows

**Technical Improvements**
* ✅ **Synchronous initialization** - Query Signals are now initialized with cached data if available, preventing empty initial results
* ✅ **Enhanced logging pipeline** - Added comprehensive logging throughout datalog conversion: parsing, reconstruction, grouping, and caching
* ✅ **Immediate data availability** - Applications receive data immediately when cache is populated, no async delays

### 📚 Impact

This release fixes the final piece of the datalog conversion issue. While v0.2.2 added caching, there was still a race condition causing queries to return empty results. Now:

1. Cache is checked synchronously BEFORE creating the query Signal
2. Query results are initialized with cached data immediately
3. Applications receive data without any race conditions
4. Full visibility into datalog processing with enhanced logging

**The complete fix ensures**: No more "0 documents" when data exists. The package now properly converts datalog, caches it, AND returns it immediately to applications.

---

## 0.2.2

### 🚀 Major Fix: Query Result Caching for Datalog Format

**Fixed Critical Issue**
* ✅ **Fixed datalog format not being returned as collection format** - Applications now receive properly converted collection data instead of raw datalog format
* ✅ **Added query result caching** - Converted datalog results are cached for immediate access, solving the "0 documents" issue
* ✅ **Improved data availability** - Queries now return cached results immediately after datalog conversion, without waiting for async storage operations

**Technical Improvements**
* ✅ **Query result cache in SyncEngine** - Stores converted collection data from datalog processing
* ✅ **Cache-first query strategy** - QueryEngine checks cache before querying storage
* ✅ **Smart cache invalidation** - Cache clears when local transactions affect collections
* ✅ **Enhanced query filtering** - Apply where, orderBy, limit, and offset to cached data

**Architecture Enhancements**
* ✅ **Direct data path** - Datalog conversion results are immediately available to queries
* ✅ **Reduced latency** - No dependency on async storage operations for query results
* ✅ **Better synchronization** - Ensures data consistency between datalog processing and query results

### 📚 Impact

This release fixes a critical issue where applications using the InstantDB Flutter package would receive 0 documents from queries, even though the package successfully processed datalog internally. The fix ensures that:

1. Datalog format is properly converted to collection format
2. Converted data is immediately available to applications
3. No data loss occurs during the conversion process
4. Applications no longer need workarounds to parse datalog manually

**For AppShell Users**: While AppShell v0.7.19+ includes a workaround, updating to InstantDB Flutter v0.2.2 provides the proper fix at the package level.

---

## 0.2.1

### 🐛 Critical Bug Fixes

**Enhanced Datalog Processing**
* ✅ **Fixed datalog-result format edge cases** - Resolved scenarios where malformed join-rows or unexpected data structures could cause silent failures, leading to empty query results despite data existing in the response
* ✅ **Added robust format detection** - Implemented comprehensive datalog format detection that handles multiple variations including nested structures and different datalog path locations
* ✅ **Enhanced error logging** - Added detailed logging for unrecognized query response formats to aid debugging instead of failing silently
* ✅ **Multiple fallback paths** - Added systematic fallback logic that tries various datalog extraction methods before falling back to simple collection format
* ✅ **Improved delete detection** - Better handling of entity deletions across different data formats and connection states

**Connection & Timing Improvements**
* ✅ **Fixed connection timing race conditions** - Resolved timing-dependent format detection failures during connection initialization that could cause datalog responses to be ignored
* ✅ **Enhanced message type handling** - Improved processing of different query response message types (`add-query-ok`, `refresh-ok`, `query-invalidation`) with varying data structure expectations
* ✅ **Added explicit failure warnings** - Replaced silent failures with explicit warnings when query responses don't match expected formats

### 🔧 Technical Improvements

**Code Quality**
* ✅ **Modularized datalog processing** - Refactored datalog handling into focused, testable methods for better maintainability
* ✅ **Enhanced type safety** - Improved type checking and reduced unnecessary casts in datalog processing logic
* ✅ **Better error reporting** - Added comprehensive logging at different levels to help debug datalog processing issues

**Architecture**
* ✅ **Robust conversion pipeline** - Implemented a systematic approach to converting datalog-result format to collection format with multiple validation points
* ✅ **Improved data flow** - Enhanced the data processing pipeline to handle edge cases gracefully while maintaining performance

### 📚 Documentation
* ✅ Updated CLAUDE.md with detailed information about datalog processing improvements
* ✅ Added documentation for debugging datalog format detection issues

---

## 0.2.0

### 🚀 Major Features - React/JS SDK Feature Parity

**New Transaction System (tx namespace)**
* ✅ Added fluent `tx` namespace API for cleaner transactions (`db.tx['entity'][id].update({})`)
* ✅ Implemented `transactChunk()` method for transaction chunks
* ✅ Added `merge()` operation for deep nested object updates
* ✅ Added `link()` and `unlink()` operations for entity relationships
* ✅ Implemented `lookup()` references to reference entities by attributes instead of IDs

**Advanced Query Operators**
* ✅ Added comparison operators: `$gt`, `$gte`, `$lt`, `$lte`, `$ne`
* ✅ Added string pattern matching: `$like`, `$ilike` with wildcard support
* ✅ Added array operations: `$contains`, `$size`, `$in`, `$nin`
* ✅ Added existence operators: `$exists`, `$isNull`
* ✅ Enhanced logical operators: improved `$and`, `$or`, `$not` support

**Room-based Presence System**
* ✅ Added `joinRoom()` API returning scoped `InstantRoom` instances
* ✅ Implemented room-specific presence operations (scoped to individual rooms)
* ✅ Added topic-based pub/sub messaging with `publishTopic()` and `subscribeTopic()`
* ✅ Complete room isolation - presence data separated between rooms
* ✅ Backward compatible with existing direct room ID APIs

**API Improvements**
* ✅ Added `subscribeQuery()` alias for reactive queries (matches React SDK)
* ✅ Implemented `queryOnce()` for one-time query execution
* ✅ Added `getAuth()` and `subscribeAuth()` convenience methods
* ✅ Improved error handling and validation

### 🧪 Testing & Quality
* ✅ **150 total tests passing** (up from 118 tests)
* ✅ Added comprehensive test suite for all new features
* ✅ Performance testing for large datasets and query caching
* ✅ Room-based presence system testing with isolation validation

### 🐛 Bug Fixes & Performance Improvements
* ✅ **Fixed transaction conversion for real-time sync** - transactions now properly convert to tx-steps with actual data instead of sending 0 steps
* ✅ **Fixed duplicate entity issue during sync** - implemented deduplication logic to prevent locally-created entities from being re-applied during refresh-ok
* ✅ **Fixed entity type resolution during sync** - entities from server now properly stored with correct type (e.g., `todos:id` instead of `unknown:id`)
* ✅ **Fixed delete synchronization between instances** - implemented differential sync to detect and apply deletions when entities are missing from server responses, including handling empty entity lists
* ✅ **Fixed presence reactions not appearing in peer instances** - implemented proper refresh-presence message handling to convert reaction data to visible UI reactions
* ✅ **Fixed cursors, typing indicators, and avatars not working in peer instances** - implemented complete presence data detection and routing in refresh-presence messages to handle all presence types
* ✅ **Fixed avatars page showing only 1 user instead of both users** - preserved local user's presence when processing refresh-presence messages to match React SDK behavior
* ✅ **Fixed avatar presence data extraction and room ID consistency** - corrected nested data structure extraction from refresh-presence messages and unified room key format usage
* ✅ **Fixed typing indicators showing 'Someone' instead of actual user names** - updated typing page to set initial presence with userName and display actual user names in typing indicators
* ✅ **Added comprehensive hierarchical logging system** - using `logging` package for better debugging and monitoring of sync operations
* ✅ **Enhanced sync engine with proper attribute UUID mapping** - transactions now use correct InstantDB attribute UUIDs instead of attribute names

### 📖 Documentation
* ✅ Updated README with all new APIs and examples
* ✅ Created `ADVANCED_FEATURES.md` comprehensive feature guide
* ✅ Added `MIGRATION_GUIDE.md` for upgrading existing code
* ✅ Updated example applications showcasing new room-based presence APIs

### 📱 Example Applications Updated
* ✅ Cursors demo updated to use room-based presence API
* ✅ Reactions demo updated with room-scoped reactions
* ✅ Typing indicators demo updated with room-scoped typing
* ✅ Avatars demo updated with room-scoped presence
* ✅ Todos demo updated to showcase new `tx` namespace API

### 🔧 Breaking Changes
**None!** This release is fully backward compatible. All existing APIs continue to work.

### 🎯 Migration Path
* **Immediate**: New projects can use new APIs from day one
* **Gradual**: Existing projects can migrate incrementally at their own pace
* **Optional**: Migration provides better performance and developer experience but is not required

---

## 0.1.2

### 📚 Documentation & Web Support
- Added web platform setup documentation with SQLite web worker configuration
- Added documentation link to pub.dev pointing to https://instantdb-flutter-docs.pages.dev
- Improved setup instructions to prevent web worker initialization errors

## 0.1.1

### 🔧 Fixes
- Fixed incorrect GitHub repository links in pubspec.yaml and CONTRIBUTING.md
- Repository links now correctly point to https://github.com/pillowsoft/instantdb_flutter

## 0.1.0

### 🎉 Initial Release

**Core Features**
* ✅ Real-time synchronization with InstantDB backend
* ✅ Offline-first local storage with SQLite triple store
* ✅ Reactive UI updates using Signals
* ✅ InstaQL query language support
* ✅ Transaction system with optimistic updates
* ✅ Authentication system integration
* ✅ Schema validation and type safety

**Flutter Integration**
* ✅ `InstantProvider` for dependency injection
* ✅ `InstantBuilder` and `InstantBuilderTyped` reactive widgets  
* ✅ `AuthBuilder` for authentication state management
* ✅ `Watch` widget for reactive UI updates
* ✅ `ConnectionStatusBuilder` for network status

**Presence System**
* ✅ Real-time cursor tracking
* ✅ Typing indicators
* ✅ Emoji reactions
* ✅ User presence status
* ✅ Room-based collaboration features

**Developer Experience**
* ✅ Comprehensive example application
* ✅ Full test coverage
* ✅ TypeScript-style API design
* ✅ Hot reload support
* ✅ Debug tooling integration

---

## 0.0.1

* Initial development release with basic InstantDB integration
