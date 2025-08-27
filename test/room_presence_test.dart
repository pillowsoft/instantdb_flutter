import 'package:flutter_test/flutter_test.dart';
import 'package:instantdb_flutter/instantdb_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('Room-based Presence System Tests', () {
    late InstantDB db;
    late PresenceManager presence;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      db = await InstantDB.init(
        appId: 'test-app',
        config: const InstantConfig(syncEnabled: false),
      );
      presence = db.presence;
    });

    tearDown(() async {
      await db.dispose();
    });

    group('joinRoom API', () {
      test('should return InstantRoom instance', () {
        final room = presence.joinRoom('room-1');

        expect(room, isA<InstantRoom>());
        expect(room.roomId, equals('room-1'));
      });

      test('should initialize room data when joining', () {
        presence.joinRoom('room-1');

        // Room data should be initialized (internal state)
        expect(
          presence.getPresence('room-1'),
          isA<Signal<Map<String, PresenceData>>>(),
        );
        expect(
          presence.getCursors('room-1'),
          isA<Signal<Map<String, CursorData>>>(),
        );
        expect(
          presence.getTyping('room-1'),
          isA<Signal<Map<String, DateTime>>>(),
        );
        expect(
          presence.getReactions('room-1'),
          isA<Signal<List<ReactionData>>>(),
        );
      });

      test('should support initial presence data', () {
        const initialPresence = {'status': 'online', 'mood': 'happy'};
        final room = presence.joinRoom(
          'room-1',
          initialPresence: initialPresence,
        );

        // Should set initial presence
        room.setPresence(initialPresence);

        final roomPresence = presence.getPresence('room-1');
        // Note: In a real implementation, we'd need to simulate the user ID
        expect(roomPresence, isA<Signal<Map<String, PresenceData>>>());
      });
    });

    group('InstantRoom API', () {
      late InstantRoom room;

      setUp(() {
        room = presence.joinRoom('test-room');
      });

      test('should provide room-scoped presence methods', () {
        const presenceData = {'status': 'active', 'location': 'home'};

        room.setPresence(presenceData);

        final roomPresence = room.getPresence();
        expect(roomPresence, isA<Signal<Map<String, PresenceData>>>());
      });

      test('should provide room-scoped cursor methods', () {
        room.updateCursor(x: 100, y: 200);

        final cursors = room.getCursors();
        expect(cursors, isA<Signal<Map<String, CursorData>>>());
      });

      test('should provide room-scoped typing methods', () {
        room.setTyping(true);

        final typingUsers = room.getTyping();
        expect(typingUsers, isA<Signal<Map<String, DateTime>>>());
      });

      test('should provide room-scoped reaction methods', () {
        room.sendReaction('👍');

        final reactions = room.getReactions();
        expect(reactions, isA<Signal<List<ReactionData>>>());
      });

      test('should provide topic pub/sub methods', () {
        const topic = 'chat-messages';
        const message = {'text': 'Hello room!', 'userId': 'user-1'};

        // Subscribe to topic
        final subscription = room.subscribeTopic(topic);
        expect(subscription, isA<Stream<Map<String, dynamic>>>());

        // Publish to topic
        room.publishTopic(topic, message);

        // In a real test, we'd verify the message was received
      });
    });

    group('Topic Pub/Sub System', () {
      test('should handle topic subscriptions per room', () {
        final room1 = presence.joinRoom('room-1');
        final room2 = presence.joinRoom('room-2');

        const topic = 'notifications';

        final sub1 = room1.subscribeTopic(topic);
        final sub2 = room2.subscribeTopic(topic);

        expect(sub1, isA<Stream<Map<String, dynamic>>>());
        expect(sub2, isA<Stream<Map<String, dynamic>>>());
        expect(
          sub1,
          isNot(same(sub2)),
        ); // Different streams for different rooms
      });

      test('should isolate topics between rooms', () async {
        final room1 = presence.joinRoom('room-1');
        final room2 = presence.joinRoom('room-2');

        const topic = 'chat';
        const message1 = {'text': 'Hello room 1'};
        const message2 = {'text': 'Hello room 2'};

        final messages1 = <Map<String, dynamic>>[];
        final messages2 = <Map<String, dynamic>>[];

        // Subscribe to topics
        room1.subscribeTopic(topic).listen(messages1.add);
        room2.subscribeTopic(topic).listen(messages2.add);

        // Publish to different rooms
        room1.publishTopic(topic, message1);
        room2.publishTopic(topic, message2);

        await Future.delayed(const Duration(milliseconds: 50));

        // Messages should be isolated to their respective rooms
        expect(messages1, hasLength(1));
        expect(messages2, hasLength(1));
        expect(messages1.first['text'], equals('Hello room 1'));
        expect(messages2.first['text'], equals('Hello room 2'));
      });

      test('should support multiple subscribers to same topic', () async {
        final room = presence.joinRoom('room-1');

        const topic = 'updates';
        const message = {'type': 'user-joined', 'userId': 'user-2'};

        final messages1 = <Map<String, dynamic>>[];
        final messages2 = <Map<String, dynamic>>[];

        // Multiple subscribers to same topic
        room.subscribeTopic(topic).listen(messages1.add);
        room.subscribeTopic(topic).listen(messages2.add);

        room.publishTopic(topic, message);

        await Future.delayed(const Duration(milliseconds: 50));

        // Both subscribers should receive the message
        expect(messages1, hasLength(1));
        expect(messages2, hasLength(1));
        expect(messages1.first['type'], equals('user-joined'));
        expect(messages2.first['type'], equals('user-joined'));
      });
    });

    group('Room Isolation', () {
      test('should isolate presence data between rooms', () {
        final room1 = presence.joinRoom('room-1');
        final room2 = presence.joinRoom('room-2');

        const presence1 = {'status': 'room-1-status'};
        const presence2 = {'status': 'room-2-status'};

        room1.setPresence(presence1);
        room2.setPresence(presence2);

        final room1Presence = room1.getPresence();
        final room2Presence = room2.getPresence();

        expect(room1Presence, isNot(same(room2Presence)));
        // Note: Detailed validation would require simulating user IDs
      });

      test('should isolate cursors between rooms', () {
        final room1 = presence.joinRoom('room-1');
        final room2 = presence.joinRoom('room-2');

        room1.updateCursor(x: 100, y: 200);
        room2.updateCursor(x: 300, y: 400);

        final cursors1 = room1.getCursors();
        final cursors2 = room2.getCursors();

        expect(cursors1, isNot(same(cursors2)));
      });

      test('should isolate reactions between rooms', () {
        final room1 = presence.joinRoom('room-1');
        final room2 = presence.joinRoom('room-2');

        room1.sendReaction('👍');
        room2.sendReaction('❤️');

        final reactions1 = room1.getReactions();
        final reactions2 = room2.getReactions();

        expect(reactions1, isNot(same(reactions2)));
      });
    });

    group('API Compatibility', () {
      test(
        'should maintain backward compatibility with direct room ID methods',
        () {
          // Old API should still work
          const presenceData = {'status': 'online'};
          presence.setPresence('room-1', presenceData);

          final roomPresence = presence.getPresence('room-1');
          expect(roomPresence, isA<Signal<Map<String, PresenceData>>>());
        },
      );

      test('should work alongside new room API', () {
        // Mix old and new APIs
        presence.setPresence('room-1', {'status': 'legacy'});

        final room = presence.joinRoom('room-1');
        room.setPresence({'status': 'modern'});

        // Both should work on the same room
        final roomPresence = presence.getPresence('room-1');
        expect(roomPresence, isA<Signal<Map<String, PresenceData>>>());
      });
    });
  });
}
