import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/board_object.dart';
import '../domain/models/map_projection.dart';
import '../domain/models/presence.dart';

/// Abstract contract for real-time multiplayer board synchronization.
abstract class BoardSyncRepository {
  /// Emits the current list of objects on [boardId] whenever an object is added,
  /// updated, or removed remotely.
  Stream<List<BoardObject>> watchObjects(String boardId);

  /// Upserts a discrete board object (stroke, shape, note, text).
  Future<void> upsertObject(String boardId, BoardObject object);

  /// Deletes a discrete board object by ID.
  Future<void> deleteObject(String boardId, String objectId);

  /// Clears all objects for the board.
  Future<void> clearBoard(String boardId);

  /// Emits the active collaborators' presence map {userId: UserPresence}.
  Stream<Map<String, UserPresence>> watchPresence(String boardId);

  /// Updates or broadcasts the local user's presence coordinates & tool state.
  Future<void> updatePresence(String boardId, UserPresence presence);

  /// Removes the user's presence when disconnecting or navigating away.
  Future<void> removePresence(String boardId, String userId);

  /// Emits the geographic location of the person who last edited [boardId].
  Stream<LastEditorLocation?> watchLastEditorLocation(String boardId);

  /// Publishes the geographic location of the person who last edited [boardId].
  Future<void> updateLastEditorLocation(
    String boardId,
    LastEditorLocation location,
  );

  /// Whether this repository is connected to a remote cloud backend.
  bool get isCloudSync;

  void dispose();
}

/// In-memory broadcast sync engine for zero-configuration local development,
/// automated testing, and Android Studio offline preview.
class BroadcastBoardSyncRepository implements BoardSyncRepository {
  BroadcastBoardSyncRepository._();
  static final BroadcastBoardSyncRepository instance =
      BroadcastBoardSyncRepository._();

  final Map<String, Map<String, BoardObject>> _objectsByBoard = {};
  final Map<String, StreamController<List<BoardObject>>> _objectControllers =
      {};

  final Map<String, Map<String, UserPresence>> _presenceByBoard = {};
  final Map<String, StreamController<Map<String, UserPresence>>>
  _presenceControllers = {};

  final Map<String, LastEditorLocation> _lastEditorByBoard = {};
  final Map<String, StreamController<LastEditorLocation?>>
  _lastEditorControllers = {};

  StreamController<List<BoardObject>> _getObjectController(String boardId) {
    return _objectControllers.putIfAbsent(
      boardId,
      () => StreamController<List<BoardObject>>.broadcast(
        onListen: () {
          final current = _objectsByBoard[boardId]?.values.toList() ?? const [];
          _objectControllers[boardId]?.add(current);
        },
      ),
    );
  }

  StreamController<Map<String, UserPresence>> _getPresenceController(
    String boardId,
  ) {
    return _presenceControllers.putIfAbsent(
      boardId,
      () => StreamController<Map<String, UserPresence>>.broadcast(
        onListen: () {
          final current = _presenceByBoard[boardId] ?? const {};
          _presenceControllers[boardId]?.add(current);
        },
      ),
    );
  }

  @override
  bool get isCloudSync => false;

  @override
  Stream<List<BoardObject>> watchObjects(String boardId) {
    return _getObjectController(boardId).stream;
  }

  @override
  Future<void> upsertObject(String boardId, BoardObject object) async {
    final boardMap = _objectsByBoard.putIfAbsent(boardId, () => {});
    boardMap[object.id] = object;
    _getObjectController(boardId).add(boardMap.values.toList());
  }

  @override
  Future<void> deleteObject(String boardId, String objectId) async {
    final boardMap = _objectsByBoard[boardId];
    if (boardMap != null && boardMap.containsKey(objectId)) {
      boardMap.remove(objectId);
      _getObjectController(boardId).add(boardMap.values.toList());
    }
  }

  @override
  Future<void> clearBoard(String boardId) async {
    final boardMap = _objectsByBoard[boardId];
    if (boardMap != null) {
      boardMap.clear();
      _getObjectController(boardId).add(const []);
    }
  }

  @override
  Stream<Map<String, UserPresence>> watchPresence(String boardId) {
    return _getPresenceController(boardId).stream;
  }

  @override
  Future<void> updatePresence(String boardId, UserPresence presence) async {
    final presMap = _presenceByBoard.putIfAbsent(boardId, () => {});
    presMap[presence.userId] = presence;
    _getPresenceController(boardId).add(Map.unmodifiable(presMap));
  }

  @override
  Future<void> removePresence(String boardId, String userId) async {
    final presMap = _presenceByBoard[boardId];
    if (presMap != null && presMap.containsKey(userId)) {
      presMap.remove(userId);
      _getPresenceController(boardId).add(Map.unmodifiable(presMap));
    }
  }

  StreamController<LastEditorLocation?> _getLastEditorController(
    String boardId,
  ) {
    return _lastEditorControllers.putIfAbsent(
      boardId,
      () => StreamController<LastEditorLocation?>.broadcast(
        onListen: () {
          _lastEditorControllers[boardId]?.add(_lastEditorByBoard[boardId]);
        },
      ),
    );
  }

  @override
  Stream<LastEditorLocation?> watchLastEditorLocation(String boardId) {
    return _getLastEditorController(boardId).stream;
  }

  @override
  Future<void> updateLastEditorLocation(
    String boardId,
    LastEditorLocation location,
  ) async {
    _lastEditorByBoard[boardId] = location;
    _getLastEditorController(boardId).add(location);
  }

  /// Triggers a simulated remote collaborator for Android Studio testing/demos.
  /// Moves a remote cursor and places an interactive sticky note on the canvas.
  Future<void> simulateCollaboratorActivity(
    String boardId, {
    String collaboratorName = 'Maya (Design)',
    int colorValue = 0xFF8B5CF6, // Purple
  }) async {
    final collaboratorId = 'sim-${collaboratorName.hashCode}';

    // Step 1: Collaborator moves cursor into view
    final steps = [
      const Offset(200, 150),
      const Offset(320, 220),
      const Offset(450, 300),
      const Offset(520, 360),
    ];

    for (final pos in steps) {
      await updatePresence(
        boardId,
        UserPresence(
          userId: collaboratorId,
          userName: collaboratorName,
          colorValue: colorValue,
          x: pos.dx,
          y: pos.dy,
          lastActive: DateTime.now().millisecondsSinceEpoch,
          toolName: 'stickyNote',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    // Step 2: Collaborator places a sticky note
    final note = StickyNoteObject(
      id: 'note-sim-${DateTime.now().millisecondsSinceEpoch}',
      rect: const Rect.fromLTWH(480, 320, 180, 160),
      text: 'Great work team!\nNext: Realtime sync validated.',
      color: const Color(0xFF1F2937),
      noteColor: const Color(0xFFD1FAE5), // Mint green
      fontSize: 14,
    );
    await upsertObject(boardId, note);
    await updateLastEditorLocation(
      boardId,
      LastEditorLocation(
        latitude: 35.6762,
        longitude: 139.6503,
        locationName: 'Tokyo, Japan',
        editorName: collaboratorName,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    // Step 3: Move cursor slightly away
    await updatePresence(
      boardId,
      UserPresence(
        userId: collaboratorId,
        userName: collaboratorName,
        colorValue: colorValue,
        x: 700,
        y: 420,
        lastActive: DateTime.now().millisecondsSinceEpoch,
        toolName: 'pen',
      ),
    );
  }

  /// Clears in-memory data (useful for test teardown).
  @visibleForTesting
  void reset() {
    _objectsByBoard.clear();
    _presenceByBoard.clear();
    _lastEditorByBoard.clear();
  }

  @override
  void dispose() {
    for (final c in _objectControllers.values) {
      c.close();
    }
    for (final c in _presenceControllers.values) {
      c.close();
    }
    _objectControllers.clear();
    _presenceControllers.clear();
    _objectsByBoard.clear();
    _presenceByBoard.clear();
  }
}

/// Firebase Realtime Database discrete object & presence synchronization.
class FirebaseBoardSyncRepository implements BoardSyncRepository {
  FirebaseBoardSyncRepository({FirebaseDatabase? database})
    : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;
  final Map<String, StreamSubscription> _subscriptions = {};

  @override
  bool get isCloudSync => true;

  DatabaseReference _objectsRef(String boardId) =>
      _db.ref('board_objects').child(boardId);

  DatabaseReference _presenceRef(String boardId) =>
      _db.ref('board_presence').child(boardId);

  DatabaseReference _lastEditorRef(String boardId) =>
      _db.ref('board_meta').child(boardId).child('lastEditorLocation');

  @override
  Stream<List<BoardObject>> watchObjects(String boardId) {
    return _objectsRef(boardId).onValue.map((event) {
      final snapshot = event.snapshot.value;
      if (snapshot == null) return <BoardObject>[];
      if (snapshot is! Map) return <BoardObject>[];

      final objects = <BoardObject>[];
      snapshot.forEach((key, value) {
        if (value is Map) {
          try {
            final map = Map<String, dynamic>.from(value);
            final obj = BoardObject.fromJson(map);
            objects.add(obj);
          } catch (e) {
            debugPrint('Failed to deserialize remote BoardObject $key: $e');
          }
        }
      });
      return objects;
    });
  }

  @override
  Future<void> upsertObject(String boardId, BoardObject object) async {
    try {
      await _objectsRef(boardId).child(object.id).set(object.toJson());
    } catch (e) {
      debugPrint('Firebase upsertObject failed: $e');
    }
  }

  @override
  Future<void> deleteObject(String boardId, String objectId) async {
    try {
      await _objectsRef(boardId).child(objectId).remove();
    } catch (e) {
      debugPrint('Firebase deleteObject failed: $e');
    }
  }

  @override
  Future<void> clearBoard(String boardId) async {
    try {
      await _objectsRef(boardId).remove();
    } catch (e) {
      debugPrint('Firebase clearBoard failed: $e');
    }
  }

  @override
  Stream<Map<String, UserPresence>> watchPresence(String boardId) {
    return _presenceRef(boardId).onValue.map((event) {
      final snapshot = event.snapshot.value;
      if (snapshot == null || snapshot is! Map) {
        return <String, UserPresence>{};
      }

      final presenceMap = <String, UserPresence>{};
      snapshot.forEach((key, value) {
        if (value is Map) {
          try {
            final map = Map<String, dynamic>.from(value);
            final pres = UserPresence.fromJson(map);
            if (pres.isOnline()) {
              presenceMap[pres.userId] = pres;
            }
          } catch (e) {
            debugPrint('Failed to parse presence for $key: $e');
          }
        }
      });
      return presenceMap;
    });
  }

  @override
  Future<void> updatePresence(String boardId, UserPresence presence) async {
    try {
      final ref = _presenceRef(boardId).child(presence.userId);
      await ref.set(presence.toJson());
      // Automatically remove user presence when disconnecting from network/app
      await ref.onDisconnect().remove();
    } catch (e) {
      debugPrint('Firebase updatePresence failed: $e');
    }
  }

  @override
  Future<void> removePresence(String boardId, String userId) async {
    try {
      await _presenceRef(boardId).child(userId).remove();
    } catch (e) {
      debugPrint('Firebase removePresence failed: $e');
    }
  }

  @override
  Stream<LastEditorLocation?> watchLastEditorLocation(String boardId) {
    return _lastEditorRef(boardId).onValue.map((event) {
      final snapshot = event.snapshot.value;
      if (snapshot == null || snapshot is! Map) return null;
      try {
        return LastEditorLocation.fromJson(Map<String, dynamic>.from(snapshot));
      } catch (e) {
        debugPrint('Failed to parse lastEditorLocation: $e');
        return null;
      }
    });
  }

  @override
  Future<void> updateLastEditorLocation(
    String boardId,
    LastEditorLocation location,
  ) async {
    try {
      await _lastEditorRef(boardId).set(location.toJson());
    } catch (e) {
      debugPrint('Firebase updateLastEditorLocation failed: $e');
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions.values) {
      s.cancel();
    }
    _subscriptions.clear();
  }
}

/// Riverpod provider delivering the appropriate [BoardSyncRepository].
/// Dynamically uses Firebase if configured, otherwise smoothly falls back to
/// [BroadcastBoardSyncRepository] for zero-configuration Android Studio running.
final boardSyncRepositoryProvider = Provider<BoardSyncRepository>((ref) {
  try {
    if (Firebase.apps.isNotEmpty) {
      final repo = FirebaseBoardSyncRepository();
      ref.onDispose(repo.dispose);
      return repo;
    }
  } catch (e) {
    debugPrint('Firebase not available: $e. Using local broadcast sync.');
  }

  return BroadcastBoardSyncRepository.instance;
});
