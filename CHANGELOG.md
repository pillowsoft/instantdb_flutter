## 0.2.0 (Unreleased)

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
