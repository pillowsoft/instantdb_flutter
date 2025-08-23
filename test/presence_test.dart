import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';

void main() {
  group('Presence System Tests', () {
    late InstantDB db;
    
    setUpAll(() async {
      // Initialize database factory for testing
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      // Initialize InstantDB instance with unique persistence dir for each test
      final testId = DateTime.now().millisecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: 'test-presence',
        config: InstantConfig(
          syncEnabled: false, // Disable sync for unit tests
          persistenceDir: 'test_db_presence_$testId',
        ),
      );

      // Note: Presence system now supports anonymous usage for testing
      // No authentication setup needed for these tests
      await Future.delayed(const Duration(milliseconds: 50));
    });

    tearDown(() async {
      await db.dispose();
    });

    group('Basic Presence Functionality', () {
      test('should set and get user presence', () async {
        final roomId = 'room1';
        final presenceData = {'status': 'online', 'activity': 'typing'};

        await db.presence.setPresence(roomId, presenceData);
        
        final presenceSignal = db.presence.getPresence(roomId);
        final presence = presenceSignal.value;
        
        expect(presence.isNotEmpty, isTrue);
        expect(presence.values.first.data, equals(presenceData));
        expect(presence.values.first.userId, isNotEmpty);
      });

      test('should update presence when called multiple times', () async {
        final roomId = 'room1';

        // Set initial presence
        await db.presence.setPresence(roomId, {'status': 'online'});
        
        final presenceSignal = db.presence.getPresence(roomId);
        final initialPresence = presenceSignal.value.values.first;
        
        // Update presence
        await db.presence.setPresence(roomId, {'status': 'away'});
        
        final updatedPresence = presenceSignal.value.values.first;
        expect(updatedPresence.data['status'], equals('away'));
        expect(updatedPresence.lastSeen.isAfter(initialPresence.lastSeen), isTrue);
      });

      test('should handle presence for multiple rooms', () async {
        final room1 = 'room1';
        final room2 = 'room2';
        
        await db.presence.setPresence(room1, {'status': 'online'});
        await db.presence.setPresence(room2, {'status': 'busy'});
        
        final presence1 = db.presence.getPresence(room1);
        final presence2 = db.presence.getPresence(room2);
        
        expect(presence1.value.values.first.data['status'], equals('online'));
        expect(presence2.value.values.first.data['status'], equals('busy'));
      });

      test('should clear presence when leaving room', () async {
        final roomId = 'room1';
        
        await db.presence.setPresence(roomId, {'status': 'online'});
        
        final presenceSignal = db.presence.getPresence(roomId);
        expect(presenceSignal.value.isNotEmpty, isTrue);
        
        await db.presence.leaveRoom(roomId);
        
        // Presence should be cleared for current user
        expect(presenceSignal.value.isEmpty, isTrue);
      });
    });

    group('Cursor Tracking', () {
      test('should update and get cursor positions', () async {
        final roomId = 'room1';
        
        await db.presence.updateCursor(
          roomId,
          x: 100.0,
          y: 200.0,
          userName: 'Test User',
          userColor: '#ff0000',
        );
        
        final cursorsSignal = db.presence.getCursors(roomId);
        final cursors = cursorsSignal.value;
        
        expect(cursors.isNotEmpty, isTrue);
        final cursor = cursors.values.first;
        expect(cursor.x, equals(100.0));
        expect(cursor.y, equals(200.0));
        expect(cursor.userName, equals('Test User'));
        expect(cursor.userColor, equals('#ff0000'));
      });

      test('should update cursor position multiple times', () async {
        final roomId = 'room1';
        
        await db.presence.updateCursor(roomId, x: 50.0, y: 50.0);
        await db.presence.updateCursor(roomId, x: 150.0, y: 250.0);
        
        final cursorsSignal = db.presence.getCursors(roomId);
        final cursor = cursorsSignal.value.values.first;
        
        expect(cursor.x, equals(150.0));
        expect(cursor.y, equals(250.0));
      });

      test('should handle cursor metadata', () async {
        final roomId = 'room1';
        final metadata = {'tool': 'pen', 'width': 2.5};
        
        await db.presence.updateCursor(
          roomId,
          x: 100.0,
          y: 100.0,
          metadata: metadata,
        );
        
        final cursorsSignal = db.presence.getCursors(roomId);
        final cursor = cursorsSignal.value.values.first;
        
        expect(cursor.metadata, equals(metadata));
      });
    });

    group('Typing Indicators', () {
      test('should set and get typing status', () async {
        final roomId = 'room1';
        
        await db.presence.setTyping(roomId, true);
        
        final typingSignal = db.presence.getTyping(roomId);
        final typing = typingSignal.value;
        
        expect(typing.isNotEmpty, isTrue);
        expect(typing.values.first, isA<DateTime>());
      });

      test('should clear typing when set to false', () async {
        final roomId = 'room1';
        
        await db.presence.setTyping(roomId, true);
        await db.presence.setTyping(roomId, false);
        
        final typingSignal = db.presence.getTyping(roomId);
        expect(typingSignal.value.isEmpty, isTrue);
      });

      test('should auto-clear typing after timeout', () async {
        final roomId = 'room1';
        
        await db.presence.setTyping(roomId, true);
        
        final typingSignal = db.presence.getTyping(roomId);
        expect(typingSignal.value.isNotEmpty, isTrue);
        
        // Wait for auto-clear (3 seconds + buffer)
        await Future.delayed(const Duration(seconds: 4));
        
        // Should be automatically cleared
        expect(typingSignal.value.isEmpty, isTrue);
      });
    });

    group('Reactions', () {
      test('should send and receive reactions', () async {
        final roomId = 'room1';
        
        await db.presence.sendReaction(roomId, '👍');
        
        final reactionsSignal = db.presence.getReactions(roomId);
        final reactions = reactionsSignal.value;
        
        expect(reactions.length, equals(1));
        expect(reactions.first.emoji, equals('👍'));
        expect(reactions.first.roomId, equals(roomId));
        expect(reactions.first.userId, isNotEmpty);
      });

      test('should handle reactions with metadata', () async {
        final roomId = 'room1';
        final messageId = 'msg123';
        final metadata = {'intensity': 'high'};
        
        await db.presence.sendReaction(
          roomId,
          '❤️',
          messageId: messageId,
          metadata: metadata,
        );
        
        final reactionsSignal = db.presence.getReactions(roomId);
        final reaction = reactionsSignal.value.first;
        
        expect(reaction.emoji, equals('❤️'));
        expect(reaction.messageId, equals(messageId));
        expect(reaction.metadata, equals(metadata));
      });

      test('should auto-remove reactions after timeout', () async {
        final roomId = 'room1';
        
        await db.presence.sendReaction(roomId, '😂');
        
        final reactionsSignal = db.presence.getReactions(roomId);
        expect(reactionsSignal.value.length, equals(1));
        
        // Wait for auto-removal (5 seconds + buffer)
        await Future.delayed(const Duration(seconds: 6));
        
        // Should be automatically removed
        expect(reactionsSignal.value.isEmpty, isTrue);
      });

      test('should limit reactions to prevent memory issues', () async {
        final roomId = 'room1';
        
        // Send 60 reactions (more than the limit of 50)
        for (int i = 0; i < 60; i++) {
          await db.presence.sendReaction(roomId, '👍');
        }
        
        final reactionsSignal = db.presence.getReactions(roomId);
        
        // Should be limited to 50
        expect(reactionsSignal.value.length, lessThanOrEqualTo(50));
      });
    });

    group('Signal Reactivity', () {
      test('should emit changes when presence updates', () async {
        final roomId = 'room1';
        final presenceSignal = db.presence.getPresence(roomId);
        
        var changeCount = 0;
        effect(() {
          presenceSignal.value; // Subscribe to changes
          changeCount++;
        });
        
        // Initial effect call
        expect(changeCount, equals(1));
        
        await db.presence.setPresence(roomId, {'status': 'online'});
        
        // Should trigger effect
        expect(changeCount, equals(2));
        
        await db.presence.setPresence(roomId, {'status': 'away'});
        
        // Should trigger effect again
        expect(changeCount, equals(3));
      });

      test('should emit changes when cursor updates', () async {
        final roomId = 'room1';
        final cursorsSignal = db.presence.getCursors(roomId);
        
        var changeCount = 0;
        effect(() {
          cursorsSignal.value; // Subscribe to changes
          changeCount++;
        });
        
        expect(changeCount, equals(1));
        
        await db.presence.updateCursor(roomId, x: 10.0, y: 20.0);
        
        expect(changeCount, equals(2));
      });

      test('should emit changes when typing status changes', () async {
        final roomId = 'room1';
        final typingSignal = db.presence.getTyping(roomId);
        
        var changeCount = 0;
        effect(() {
          typingSignal.value; // Subscribe to changes
          changeCount++;
        });
        
        expect(changeCount, equals(1));
        
        await db.presence.setTyping(roomId, true);
        expect(changeCount, equals(2));
        
        await db.presence.setTyping(roomId, false);
        expect(changeCount, equals(3));
      });

      test('should emit changes when reactions are sent', () async {
        final roomId = 'room1';
        final reactionsSignal = db.presence.getReactions(roomId);
        
        var changeCount = 0;
        effect(() {
          reactionsSignal.value; // Subscribe to changes
          changeCount++;
        });
        
        expect(changeCount, equals(1));
        
        await db.presence.sendReaction(roomId, '🎉');
        
        expect(changeCount, equals(2));
      });
    });

    group('Data Validation', () {
      test('should validate presence data structure', () async {
        final roomId = 'room1';
        final complexData = {
          'status': 'online',
          'lastActivity': DateTime.now().millisecondsSinceEpoch,
          'preferences': {
            'theme': 'dark',
            'notifications': true,
          },
          'tags': ['developer', 'flutter'],
        };
        
        await db.presence.setPresence(roomId, complexData);
        
        final presenceSignal = db.presence.getPresence(roomId);
        final presence = presenceSignal.value.values.first;
        
        expect(presence.data, equals(complexData));
        expect(presence.userId, isA<String>());
        expect(presence.lastSeen, isA<DateTime>());
      });

      test('should validate cursor data bounds', () async {
        final roomId = 'room1';
        
        // Test with extreme coordinates
        await db.presence.updateCursor(roomId, x: -999.99, y: 9999.99);
        
        final cursorsSignal = db.presence.getCursors(roomId);
        final cursor = cursorsSignal.value.values.first;
        
        expect(cursor.x, equals(-999.99));
        expect(cursor.y, equals(9999.99));
        expect(cursor.lastUpdated, isA<DateTime>());
      });

      test('should handle empty and null values gracefully', () async {
        final roomId = 'room1';
        
        // Empty presence data
        await db.presence.setPresence(roomId, {});
        
        final presenceSignal = db.presence.getPresence(roomId);
        expect(presenceSignal.value.values.first.data, equals({}));
        
        // Cursor with null optional fields
        await db.presence.updateCursor(
          roomId,
          x: 0.0,
          y: 0.0,
          userName: null,
          userColor: null,
          metadata: null,
        );
        
        final cursorsSignal = db.presence.getCursors(roomId);
        final cursor = cursorsSignal.value.values.first;
        expect(cursor.userName, isNull);
        expect(cursor.userColor, isNull);
        expect(cursor.metadata, isNull);
      });
    });

    group('Room Isolation', () {
      test('should isolate presence between different rooms', () async {
        final room1 = 'room1';
        final room2 = 'room2';
        
        await db.presence.setPresence(room1, {'status': 'room1_status'});
        await db.presence.setPresence(room2, {'status': 'room2_status'});
        
        final presence1 = db.presence.getPresence(room1);
        final presence2 = db.presence.getPresence(room2);
        
        expect(presence1.value.values.first.data['status'], equals('room1_status'));
        expect(presence2.value.values.first.data['status'], equals('room2_status'));
        
        // Leaving one room shouldn't affect the other
        await db.presence.leaveRoom(room1);
        
        expect(presence1.value.isEmpty, isTrue);
        expect(presence2.value.isNotEmpty, isTrue);
      });

      test('should isolate cursors between rooms', () async {
        final room1 = 'room1';
        final room2 = 'room2';
        
        await db.presence.updateCursor(room1, x: 100.0, y: 100.0);
        await db.presence.updateCursor(room2, x: 200.0, y: 200.0);
        
        final cursors1 = db.presence.getCursors(room1);
        final cursors2 = db.presence.getCursors(room2);
        
        expect(cursors1.value.values.first.x, equals(100.0));
        expect(cursors2.value.values.first.x, equals(200.0));
      });

      test('should isolate reactions between rooms', () async {
        final room1 = 'room1';
        final room2 = 'room2';
        
        await db.presence.sendReaction(room1, '👍');
        await db.presence.sendReaction(room2, '👎');
        
        final reactions1 = db.presence.getReactions(room1);
        final reactions2 = db.presence.getReactions(room2);
        
        expect(reactions1.value.first.emoji, equals('👍'));
        expect(reactions2.value.first.emoji, equals('👎'));
        expect(reactions1.value.first.roomId, equals(room1));
        expect(reactions2.value.first.roomId, equals(room2));
      });
    });

    group('Performance Tests', () {
      test('should handle rapid cursor updates efficiently', () async {
        final roomId = 'room1';
        final stopwatch = Stopwatch()..start();
        
        // Send 100 cursor updates rapidly
        for (int i = 0; i < 100; i++) {
          await db.presence.updateCursor(roomId, x: i.toDouble(), y: i.toDouble());
        }
        
        stopwatch.stop();
        
        final cursorsSignal = db.presence.getCursors(roomId);
        final cursor = cursorsSignal.value.values.first;
        
        expect(cursor.x, equals(99.0));
        expect(cursor.y, equals(99.0));
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should complete in under 5s
      });

      test('should handle many simultaneous reactions efficiently', () async {
        final roomId = 'room1';
        final emojis = ['👍', '👎', '❤️', '😂', '😮', '😢', '😡'];
        
        final stopwatch = Stopwatch()..start();
        
        // Send many reactions
        for (int i = 0; i < 20; i++) {
          final emoji = emojis[i % emojis.length];
          await db.presence.sendReaction(roomId, emoji);
        }
        
        stopwatch.stop();
        
        final reactionsSignal = db.presence.getReactions(roomId);
        expect(reactionsSignal.value.length, equals(20));
        expect(stopwatch.elapsedMilliseconds, lessThan(2000)); // Should complete in under 2s
      });

      test('should handle multiple rooms efficiently', () async {
        final numRooms = 50;
        final stopwatch = Stopwatch()..start();
        
        // Set presence in 50 different rooms
        for (int i = 0; i < numRooms; i++) {
          await db.presence.setPresence('room$i', {'status': 'active', 'roomIndex': i});
        }
        
        stopwatch.stop();
        
        // Verify all rooms have presence
        for (int i = 0; i < numRooms; i++) {
          final presence = db.presence.getPresence('room$i');
          expect(presence.value.isNotEmpty, isTrue);
        }
        
        expect(stopwatch.elapsedMilliseconds, lessThan(3000)); // Should complete in under 3s
      });
    });

    group('Error Handling', () {
      test('should handle invalid room IDs gracefully', () async {
        // Empty room ID
        await db.presence.setPresence('', {'status': 'test'});
        
        final presence = db.presence.getPresence('');
        expect(presence.value, isA<Map>());
      });

      test('should handle extremely large presence data', () async {
        final roomId = 'room1';
        final largeData = <String, dynamic>{};
        
        // Create large data structure
        for (int i = 0; i < 1000; i++) {
          largeData['key$i'] = 'value$i';
        }
        
        await db.presence.setPresence(roomId, largeData);
        
        final presence = db.presence.getPresence(roomId);
        expect(presence.value.values.first.data.length, equals(1000));
      });

      test('should handle special characters in room IDs', () async {
        final roomId = 'room-with_special.chars@123';
        
        await db.presence.setPresence(roomId, {'status': 'test'});
        
        final presence = db.presence.getPresence(roomId);
        expect(presence.value.isNotEmpty, isTrue);
      });
    });

    group('Cleanup and Memory Management', () {
      test('should dispose cleanly', () async {
        final roomId = 'room1';
        
        await db.presence.setPresence(roomId, {'status': 'online'});
        await db.presence.updateCursor(roomId, x: 100.0, y: 200.0);
        await db.presence.sendReaction(roomId, '👍');
        
        // Should not throw
        expect(() => db.presence.dispose(), returnsNormally);
      });
    });
  });
}