import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/board_object.dart';
import '../domain/models/map_projection.dart';
import 'board_storage_platform.dart'
    if (dart.library.io) 'board_storage_io.dart'
    if (dart.library.html) 'board_storage_web.dart'
    if (dart.library.js_interop) 'board_storage_web.dart';

/// Local storage service for caching and persisting board objects to device disk.
class BoardStorageService {
  static const _recentBoardsKey = 'syncboard_recent_boards';
  static const _lastEditorLocPrefix = 'syncboard_last_editor_loc_';
  final BoardStoragePlatform _platform = getBoardStoragePlatform();

  /// Saves a list of [BoardObject]s to a local JSON file or Web storage.
  Future<void> saveBoard(String boardId, List<BoardObject> objects) async {
    try {
      final data = {
        'boardId': boardId,
        'savedAt': DateTime.now().toIso8601String(),
        'objects': objects.map((o) => o.toJson()).toList(),
      };
      await _platform.save(boardId, jsonEncode(data));

      // Record in recent boards
      final prefs = await SharedPreferences.getInstance();
      final recents = prefs.getStringList(_recentBoardsKey) ?? [];
      if (!recents.contains(boardId)) {
        recents.insert(0, boardId);
        await prefs.setStringList(_recentBoardsKey, recents);
      }
    } catch (e) {
      debugPrint('Error saving board $boardId: $e');
    }
  }

  /// Loads a list of [BoardObject]s from the local JSON file or Web storage.
  Future<List<BoardObject>?> loadBoard(String boardId) async {
    try {
      final contents = await _platform.load(boardId);
      if (contents == null) return null;

      final data = jsonDecode(contents) as Map<String, dynamic>;
      final rawObjects = (data['objects'] as List).cast<Map<String, dynamic>>();
      return rawObjects.map((json) => BoardObject.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error loading board $boardId: $e');
      return null;
    }
  }

  /// Persists the geographic location of the person who last edited [boardId].
  Future<void> saveLastEditorLocation(
    String boardId,
    LastEditorLocation location,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_lastEditorLocPrefix$boardId',
        jsonEncode(location.toJson()),
      );
    } catch (e) {
      debugPrint('Error saving last editor location for $boardId: $e');
    }
  }

  /// Loads the geographic location of the person who last edited [boardId].
  Future<LastEditorLocation?> loadLastEditorLocation(String boardId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_lastEditorLocPrefix$boardId');
      if (raw == null || raw.isEmpty) return null;
      return LastEditorLocation.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('Error loading last editor location for $boardId: $e');
      return null;
    }
  }

  /// Returns the list of saved/recent board IDs (always including `'demo'`).
  Future<List<String>> getRecentBoards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recents = List<String>.from(
        prefs.getStringList(_recentBoardsKey) ?? const <String>[],
      );
      if (!recents.contains('demo')) {
        recents.add('demo');
      }
      return recents;
    } catch (_) {
      return const ['demo'];
    }
  }

  /// Deletes a local board file or Web storage entry.
  Future<void> deleteBoard(String boardId) async {
    try {
      await _platform.delete(boardId);
      final prefs = await SharedPreferences.getInstance();
      final recents = prefs.getStringList(_recentBoardsKey) ?? [];
      recents.remove(boardId);
      await prefs.setStringList(_recentBoardsKey, recents);
    } catch (e) {
      debugPrint('Error deleting board $boardId: $e');
    }
  }

  /// Saves exported PNG [bytes] for [boardId] to device Downloads/Documents
  /// and returns the saved file path.
  Future<String?> saveExportedPng(String boardId, List<int> bytes) async {
    try {
      final safeId = boardId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'syncboard_${safeId}_$ts.png';
      return await _platform.saveExportedPng(fileName, bytes);
    } catch (e) {
      debugPrint('Error saving exported PNG for $boardId: $e');
      return null;
    }
  }

  /// Generates initial welcome demo objects for new demo boards.
  static List<BoardObject> createDemoBoardObjects() {
    return [
      StickyNoteObject(
        id: 'demo-welcome-note',
        rect: const Rect.fromLTWH(60, 60, 220, 160),
        text: '👋 Welcome to SyncBoard!\n\n• Miro-grade responsive whiteboard\n• Pen, Shapes, Sticky Notes & ER\n• Pinch or scroll to zoom',
        color: const Color(0xFF1F2937),
        noteColor: const Color(0xFFFEF3C7),
      ),
      const RectangleObject(
        id: 'demo-rect',
        rect: Rect.fromLTWH(340, 70, 180, 120),
        color: Color(0xFF3B82F6),
        strokeWidth: 3,
        cornerRadius: 12,
      ),
      const TextObject(
        id: 'demo-rect-text',
        position: Offset(370, 115),
        text: 'Client App (Android)',
        color: Color(0xFF1F2937),
        fontSize: 14,
        isBold: true,
      ),
      LineObject(
        id: 'demo-arrow',
        start: const Offset(520, 130),
        end: const Offset(620, 130),
        color: const Color(0xFF6B7280),
        strokeWidth: 2.5,
        isArrow: true,
      ),
      const CircleObject(
        id: 'demo-circle',
        rect: Rect.fromLTWH(620, 60, 140, 140),
        color: Color(0xFF10B981),
        strokeWidth: 3,
      ),
      const TextObject(
        id: 'demo-circle-text',
        position: Offset(645, 115),
        text: 'Cloud Service',
        color: Color(0xFF1F2937),
        fontSize: 14,
        isBold: true,
      ),
    ];
  }
}

final boardStorageServiceProvider = Provider<BoardStorageService>((ref) {
  return BoardStorageService();
});
