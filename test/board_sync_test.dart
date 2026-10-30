import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boardmate/features/board/data/board_storage_service.dart';
import 'package:boardmate/features/board/data/board_sync_repository.dart';
import 'package:boardmate/features/board/domain/models/board_object.dart';
import 'package:boardmate/features/board/domain/models/presence.dart';
import 'package:boardmate/features/board/presentation/providers/board_provider.dart';
import 'package:boardmate/features/board/presentation/providers/sync_provider.dart';

class InMemoryBoardStorageService extends BoardStorageService {
  final Map<String, List<BoardObject>> _store = {};

  @override
  Future<void> saveBoard(String boardId, List<BoardObject> objects) async {
    _store[boardId] = objects;
  }

  @override
  Future<List<BoardObject>?> loadBoard(String boardId) async {
    return _store[boardId];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Stage S4: Real-Time Sync & Presence Models', () {
    test('UserPresence JSON serialization and deserialization round-trip', () {
      const original = UserPresence(
        userId: 'user-42',
        userName: 'Alex Collaborator',
        colorValue: 0xFF3B82F6,
        x: 150.5,
        y: 275.25,
        lastActive: 1700000000000,
        toolName: 'rectangle',
      );

      final json = original.toJson();
      final roundTrip = UserPresence.fromJson(json);

      expect(roundTrip.userId, original.userId);
      expect(roundTrip.userName, original.userName);
      expect(roundTrip.colorValue, original.colorValue);
      expect(roundTrip.color, const Color(0xFF3B82F6));
      expect(roundTrip.x, original.x);
      expect(roundTrip.y, original.y);
      expect(roundTrip.position, const Offset(150.5, 275.25));
      expect(roundTrip.lastActive, original.lastActive);
      expect(roundTrip.toolName, 'rectangle');
      expect(roundTrip, equals(original));
    });

    test('UserPresence.isOnline checks heartbeat threshold accurately', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final onlineUser = UserPresence(
        userId: 'u1',
        userName: 'Active',
        colorValue: 0xFF10B981,
        x: 0,
        y: 0,
        lastActive: now - 5000, // 5 seconds ago
      );
      expect(onlineUser.isOnline(timeoutMs: 30000), isTrue);

      final staleUser = UserPresence(
        userId: 'u2',
        userName: 'Stale',
        colorValue: 0xFFEF4444,
        x: 0,
        y: 0,
        lastActive: now - 35000, // 35 seconds ago
      );
      expect(staleUser.isOnline(timeoutMs: 30000), isFalse);
    });
  });

  group('Stage S4: BroadcastBoardSyncRepository Engine', () {
    late BroadcastBoardSyncRepository repo;

    setUp(() {
      repo = BroadcastBoardSyncRepository.instance;
      repo.reset();
    });

    tearDown(() {
      repo.reset();
    });

    test(
      'upsertObject and watchObjects streams discrete object changes',
      () async {
        const boardId = 'test-board-sync-1';
        final stream = repo.watchObjects(boardId);

        final emitted = <List<BoardObject>>[];
        final sub = stream.listen((list) => emitted.add(list));

        final rect = RectangleObject(
          id: 'rect-sync-1',
          rect: const Rect.fromLTWH(100, 100, 200, 150),
          color: const Color(0xFF10B981),
          strokeWidth: 3,
        );

        await repo.upsertObject(boardId, rect);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(emitted.isNotEmpty, isTrue);
        expect(emitted.last.length, 1);
        expect(emitted.last.first.id, 'rect-sync-1');

        // Update same object
        final updated = rect.copyWith(strokeWidth: 6);
        await repo.upsertObject(boardId, updated);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(emitted.last.first.strokeWidth, 6);

        // Delete object
        await repo.deleteObject(boardId, 'rect-sync-1');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(emitted.last.isEmpty, isTrue);

        await sub.cancel();
      },
    );

    test(
      'updatePresence and removePresence stream active collaborators',
      () async {
        const boardId = 'test-board-presence-1';
        final stream = repo.watchPresence(boardId);

        final emitted = <Map<String, UserPresence>>[];
        final sub = stream.listen((m) => emitted.add(m));

        final p1 = UserPresence(
          userId: 'user-alice',
          userName: 'Alice',
          colorValue: 0xFF8B5CF6,
          x: 100,
          y: 200,
          lastActive: DateTime.now().millisecondsSinceEpoch,
          toolName: 'pen',
        );

        await repo.updatePresence(boardId, p1);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(emitted.last.containsKey('user-alice'), isTrue);
        expect(emitted.last['user-alice']!.userName, 'Alice');

        // Alice moves cursor
        await repo.updatePresence(boardId, p1.copyWith(x: 120, y: 240));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(emitted.last['user-alice']!.x, 120);

        // Alice leaves board
        await repo.removePresence(boardId, 'user-alice');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(emitted.last.containsKey('user-alice'), isFalse);

        await sub.cancel();
      },
    );

    test('clearBoard removes all objects on the target board', () async {
      const boardId = 'test-board-clear-1';
      final stream = repo.watchObjects(boardId);

      final emitted = <List<BoardObject>>[];
      final sub = stream.listen((list) => emitted.add(list));

      await repo.upsertObject(
        boardId,
        StrokeObject(
          id: 'stroke-1',
          points: const [Offset(0, 0), Offset(10, 10)],
          color: Colors.black,
          strokeWidth: 2,
        ),
      );
      await repo.upsertObject(
        boardId,
        TextObject(
          id: 'text-1',
          position: const Offset(50, 50),
          text: 'Hello sync',
          color: Colors.blue,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emitted.last.length, 2);

      await repo.clearBoard(boardId);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(emitted.last.isEmpty, isTrue);

      await sub.cancel();
    });

    test('different boards do not cross-contaminate data', () async {
      await repo.upsertObject(
        'board-A',
        RectangleObject(
          id: 'obj-A',
          rect: const Rect.fromLTWH(0, 0, 10, 10),
          color: Colors.red,
          strokeWidth: 1,
        ),
      );
      await repo.upsertObject(
        'board-B',
        RectangleObject(
          id: 'obj-B',
          rect: const Rect.fromLTWH(0, 0, 10, 10),
          color: Colors.blue,
          strokeWidth: 1,
        ),
      );

      final streamA = repo.watchObjects('board-A');
      final streamB = repo.watchObjects('board-B');

      final aList = await streamA.first;
      final bList = await streamB.first;

      expect(aList.length, 1);
      expect(aList.first.id, 'obj-A');

      expect(bList.length, 1);
      expect(bList.first.id, 'obj-B');
    });

    test(
      'simulateCollaboratorActivity moves cursor and adds sticky note',
      () async {
        const boardId = 'sim-test-board';

        final presenceEvents = <Map<String, UserPresence>>[];
        final objectEvents = <List<BoardObject>>[];

        final pSub = repo
            .watchPresence(boardId)
            .listen((p) => presenceEvents.add(p));
        final oSub = repo
            .watchObjects(boardId)
            .listen((o) => objectEvents.add(o));

        await repo.simulateCollaboratorActivity(
          boardId,
          collaboratorName: 'Maya (Design)',
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Presence should be recorded
        expect(presenceEvents.isNotEmpty, isTrue);
        final lastPresence = presenceEvents.last;
        expect(
          lastPresence.values.any((p) => p.userName == 'Maya (Design)'),
          isTrue,
        );

        // Sticky note should be placed
        expect(objectEvents.isNotEmpty, isTrue);
        final hasSticky = objectEvents.last.any((o) => o is StickyNoteObject);
        expect(hasSticky, isTrue);

        await pSub.cancel();
        await oSub.cancel();
      },
    );
  });

  group('Stage S4: Riverpod Integration & BoardNotifier Sync Pipeline', () {
    late ProviderContainer container;

    setUp(() {
      BroadcastBoardSyncRepository.instance.reset();
      container = ProviderContainer(
        overrides: [
          boardStorageServiceProvider.overrideWithValue(
            InMemoryBoardStorageService(),
          ),
        ],
      );
      container.listen(boardProvider, (_, _) {});
    });

    tearDown(() {
      container.dispose();
      BroadcastBoardSyncRepository.instance.reset();
    });

    test('initBoard subscribes to sync repo and syncs new drawings', () async {
      final notifier = container.read(boardProvider.notifier);
      await notifier.initBoard('sync-riverpod-board');

      final syncRepo = container.read(boardSyncRepositoryProvider);
      final emitted = <List<BoardObject>>[];
      final sub = syncRepo
          .watchObjects('sync-riverpod-board')
          .listen((list) => emitted.add(list));

      // Draw a line
      notifier.setTool(BoardTool.pen);
      notifier.startDrawing(const Offset(10, 10));
      notifier.extendDrawing(const Offset(30, 30), 1.0);
      notifier.endDrawing();

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(emitted.isNotEmpty, isTrue);
      expect(emitted.last.length, 1);
      expect(emitted.last.first, isA<StrokeObject>());

      await sub.cancel();
    });

    test(
      'remote collaborator objects merge into BoardNotifier state',
      () async {
        final notifier = container.read(boardProvider.notifier);
        await notifier.initBoard('remote-merge-board');

        final syncRepo = container.read(boardSyncRepositoryProvider);

        // Remote client pushes a sticky note
        final remoteNote = StickyNoteObject(
          id: 'remote-note-1',
          rect: const Rect.fromLTWH(200, 200, 160, 140),
          text: 'From remote device',
          color: const Color(0xFF1F2937),
        );
        await syncRepo.upsertObject('remote-merge-board', remoteNote);

        // Allow stream broadcast to deliver event to notifier listener
        await Future<void>.delayed(const Duration(milliseconds: 60));

        final state = container.read(boardProvider);
        expect(state.objects.any((o) => o.id == 'remote-note-1'), isTrue);
      },
    );

    test(
      'publishPresence throttles rapid updates to prevent flooding',
      () async {
        final notifier = container.read(boardProvider.notifier);
        await notifier.initBoard('presence-throttle-board');

        final syncRepo = container.read(boardSyncRepositoryProvider);
        final presenceEmissions = <Map<String, UserPresence>>[];
        final sub = syncRepo
            .watchPresence('presence-throttle-board')
            .listen((m) => presenceEmissions.add(m));

        // Call 10 times in immediate loop
        for (var i = 0; i < 10; i++) {
          notifier.publishPresence(Offset(i * 10.0, i * 10.0));
        }

        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Due to 40ms throttling, immediate consecutive calls are ignored
        expect(presenceEmissions.length, lessThan(5));

        await sub.cancel();
      },
    );

    test('remoteCollaboratorsProvider filters out the current user', () async {
      final syncRepo = container.read(boardSyncRepositoryProvider);
      const boardId = 'filter-collaborators-board';

      // Keep stream active
      container.listen(boardPresenceStreamProvider(boardId), (_, _) {});
      container.listen(remoteCollaboratorsProvider(boardId), (_, _) {});

      // Current user
      await syncRepo.updatePresence(
        boardId,
        UserPresence(
          userId: 'editor-demo-1',
          userName: 'You',
          colorValue: 0xFF3B82F6,
          x: 50,
          y: 50,
          lastActive: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      // Remote collaborator
      await syncRepo.updatePresence(
        boardId,
        UserPresence(
          userId: 'collaborator-maya',
          userName: 'Maya (Design)',
          colorValue: 0xFF8B5CF6,
          x: 200,
          y: 300,
          lastActive: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final remoteList = container.read(remoteCollaboratorsProvider(boardId));

      expect(remoteList.length, 1);
      expect(remoteList.first.userName, 'Maya (Design)');
      expect(remoteList.first.userId, 'collaborator-maya');
    });
  });
}
