import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/board_export_service.dart';
import '../../data/board_storage_service.dart';
import '../../data/board_sync_repository.dart';
import '../../data/gemini_ai_service.dart';
import '../../domain/models/board_object.dart';
import '../../domain/models/map_projection.dart';
import '../../domain/models/presence.dart';

const _uuid = Uuid();
const _maxHistory = 100;

@immutable
class BoardState {
  const BoardState({
    this.boardId = '',
    this.objects = const [],
    this.activeObject,
    this.selectedObjectId,
    this.tool = BoardTool.pen,
    this.color = const Color(0xFF1F2937),
    this.noteColor = const Color(0xFFFEF3C7),
    this.width = 4,
    this.isSaving = false,
    this.statusMessage = 'Saved',
    this.isMapMode = false,
    this.lastEditorLocation,
    this.past = const [],
    this.future = const [],
  });

  final String boardId;
  final List<BoardObject> objects;
  final BoardObject? activeObject;
  final String? selectedObjectId;
  final BoardTool tool;
  final Color color;
  final Color noteColor;
  final double width;
  final bool isSaving;
  final String statusMessage;
  final bool isMapMode;

  /// Geographic location of the person who last edited this board.
  final LastEditorLocation? lastEditorLocation;

  /// Undo/redo immutable snapshots.
  final List<List<BoardObject>> past;
  final List<List<BoardObject>> future;

  bool get canUndo => past.isNotEmpty;
  bool get canRedo => future.isNotEmpty;

  BoardObject? get selectedObject {
    if (selectedObjectId == null) return null;
    try {
      return objects.firstWhere((o) => o.id == selectedObjectId);
    } catch (_) {
      return null;
    }
  }

  BoardState copyWith({
    String? boardId,
    List<BoardObject>? objects,
    BoardObject? activeObject,
    bool clearActive = false,
    String? selectedObjectId,
    bool clearSelection = false,
    BoardTool? tool,
    Color? color,
    Color? noteColor,
    double? width,
    bool? isSaving,
    String? statusMessage,
    bool? isMapMode,
    LastEditorLocation? lastEditorLocation,
    List<List<BoardObject>>? past,
    List<List<BoardObject>>? future,
  }) => BoardState(
    boardId: boardId ?? this.boardId,
    objects: objects ?? this.objects,
    activeObject: clearActive ? null : (activeObject ?? this.activeObject),
    selectedObjectId: clearSelection
        ? null
        : (selectedObjectId ?? this.selectedObjectId),
    tool: tool ?? this.tool,
    color: color ?? this.color,
    noteColor: noteColor ?? this.noteColor,
    width: width ?? this.width,
    isSaving: isSaving ?? this.isSaving,
    statusMessage: statusMessage ?? this.statusMessage,
    isMapMode: isMapMode ?? this.isMapMode,
    lastEditorLocation: lastEditorLocation ?? this.lastEditorLocation,
    past: past ?? this.past,
    future: future ?? this.future,
  );
}

class BoardNotifier extends Notifier<BoardState> {
  Offset? _dragOrigin;
  BoardStorageService? _storage;
  BoardSyncRepository? _syncRepo;
  GeminiAIService? _aiService;
  StreamSubscription<List<BoardObject>>? _remoteSub;
  StreamSubscription<LastEditorLocation?>? _remoteLocSub;
  LastEditorLocation? _detectedUserLocation;
  int _lastPresencePublishMs = 0;
  String? _cachedUserId;
  String? _cachedUserName;

  @override
  BoardState build() {
    _storage = ref.watch(boardStorageServiceProvider);
    _syncRepo = ref.watch(boardSyncRepositoryProvider);
    _aiService = ref.watch(geminiAIServiceProvider);
    final user = ref.watch(authStateProvider).value;
    _cachedUserId = user?.uid;
    _cachedUserName = user?.displayName;

    ref.onDispose(() {
      _remoteSub?.cancel();
      _remoteLocSub?.cancel();
      final uid = _cachedUserId;
      if (uid != null && state.boardId.isNotEmpty) {
        _syncRepo?.removePresence(state.boardId, uid);
      }
    });
    return const BoardState();
  }

  /// Automatically resolves the current user's real-world location via IP
  /// geolocation (works inside Android Studio Emulator & desktop without GPS
  /// permission prompts).
  Future<void> _detectDeviceLocation() async {
    if (_detectedUserLocation != null) return;
    // Skip network lookup during unit tests when using custom mock storage
    if (_storage != null && _storage.runtimeType != BoardStorageService) {
      return;
    }
    try {
      final res = await http
          .get(
            Uri.parse(
              'http://ip-api.com/json/?fields=status,country,regionName,city,lat,lon',
            ),
          )
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final lat = (json['lat'] as num?)?.toDouble();
        final lon = (json['lon'] as num?)?.toDouble();
        final city = (json['city'] as String?) ?? '';
        final country = (json['country'] as String?) ?? '';
        if (lat != null && lon != null) {
          final locName = [
            if (city.isNotEmpty) city,
            if (country.isNotEmpty) country,
          ].join(', ');
          _detectedUserLocation = LastEditorLocation(
            latitude: lat,
            longitude: lon,
            locationName: locName.isEmpty ? 'Current Location' : locName,
            editorName: _cachedUserName ?? 'Demo Editor',
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          if (ref.mounted && state.lastEditorLocation == null) {
            state = state.copyWith(lastEditorLocation: _detectedUserLocation);
          }
          return;
        }
      }
    } catch (_) {
      // Fallback to HTTPS geolocation endpoint
      try {
        final res2 = await http
            .get(Uri.parse('https://ipapi.co/json/'))
            .timeout(const Duration(seconds: 3));
        if (res2.statusCode == 200) {
          final json = jsonDecode(res2.body) as Map<String, dynamic>;
          final lat = (json['latitude'] as num?)?.toDouble();
          final lon = (json['longitude'] as num?)?.toDouble();
          final city = (json['city'] as String?) ?? '';
          final country = (json['country_name'] as String?) ?? '';
          if (lat != null && lon != null) {
            final locName = [
              if (city.isNotEmpty) city,
              if (country.isNotEmpty) country,
            ].join(', ');
            _detectedUserLocation = LastEditorLocation(
              latitude: lat,
              longitude: lon,
              locationName: locName.isEmpty ? 'Current Location' : locName,
              editorName: _cachedUserName ?? 'Demo Editor',
              updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            );
            if (ref.mounted && state.lastEditorLocation == null) {
              state = state.copyWith(lastEditorLocation: _detectedUserLocation);
            }
            return;
          }
        }
      } catch (_) {}
    }
  }

  // ---- Board Lifecycle & Persistence ----

  Future<void> initBoard(String boardId) async {
    state = state.copyWith(
      boardId: boardId,
      isSaving: true,
      statusMessage: 'Loading...',
    );

    final storage = _storage ?? BoardStorageService();
    var loaded = await storage.loadBoard(boardId);
    final savedEditorLoc = await storage.loadLastEditorLocation(boardId);
    var isFreshDemoSeed = false;

    // If opening demo board for the first time locally, populate with demo fixture
    if (loaded == null && boardId == 'demo') {
      loaded = BoardStorageService.createDemoBoardObjects();
      isFreshDemoSeed = true;
      await storage.saveBoard(boardId, loaded);
    } else if (loaded == null) {
      // Record newly created board in recent boards immediately
      await storage.saveBoard(boardId, const []);
    }

    state = state.copyWith(
      objects: loaded ?? const [],
      lastEditorLocation: savedEditorLoc ?? _detectedUserLocation,
      isSaving: false,
      statusMessage: 'Saved',
      past: const [],
      future: const [],
    );

    // Kick off non-blocking device location lookup
    unawaited(_detectDeviceLocation());

    // Seed repository only when we have user-saved local objects (or in local
    // broadcast mode), so a fresh install doesn't overwrite existing cloud data.
    if (loaded != null &&
        loaded.isNotEmpty &&
        _syncRepo != null &&
        (!isFreshDemoSeed || !_syncRepo!.isCloudSync)) {
      for (final obj in loaded) {
        _syncRepo!.upsertObject(boardId, obj);
      }
    }

    // Subscribe to remote real-time updates
    _remoteSub?.cancel();
    _remoteLocSub?.cancel();
    if (_syncRepo != null) {
      _remoteSub = _syncRepo!.watchObjects(boardId).listen((remoteObjects) {
        _handleRemoteObjectsUpdate(remoteObjects);
      });
      _remoteLocSub = _syncRepo!.watchLastEditorLocation(boardId).listen((loc) {
        if (loc != null && loc != state.lastEditorLocation) {
          state = state.copyWith(lastEditorLocation: loc);
          _storage?.saveLastEditorLocation(boardId, loc);
          if (state.isMapMode) {
            centerOnLastEditorLocation();
          }
        }
      });
    }
  }

  void _handleRemoteObjectsUpdate(List<BoardObject> remoteObjects) {
    if (remoteObjects.isEmpty && state.objects.isNotEmpty) return;
    // Don't overwrite if identical
    if (remoteObjects.length == state.objects.length) {
      var identical = true;
      for (var i = 0; i < remoteObjects.length; i++) {
        if (remoteObjects[i] != state.objects[i]) {
          identical = false;
          break;
        }
      }
      if (identical) return;
    }

    state = state.copyWith(objects: remoteObjects, statusMessage: 'Saved');
    _storage?.saveBoard(state.boardId, remoteObjects);
  }

  // ---- Real-time Sync & Collaborator Helpers ----

  void _syncUpsert(BoardObject obj) {
    if (state.boardId.isNotEmpty && _syncRepo != null) {
      _syncRepo!.upsertObject(state.boardId, obj);
    }
  }

  void _syncDelete(String objectId) {
    if (state.boardId.isNotEmpty && _syncRepo != null) {
      _syncRepo!.deleteObject(state.boardId, objectId);
    }
  }

  void _syncClear() {
    if (state.boardId.isNotEmpty && _syncRepo != null) {
      _syncRepo!.clearBoard(state.boardId);
    }
  }

  void publishPresence(Offset scenePoint) {
    if (state.boardId.isEmpty || _syncRepo == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPresencePublishMs < 40) return;
    _lastPresencePublishMs = now;

    final userId = _cachedUserId ?? 'editor-demo-1';
    final userName = _cachedUserName ?? 'You';
    final colorValue = _colorForUserId(userId);

    _syncRepo!.updatePresence(
      state.boardId,
      UserPresence(
        userId: userId,
        userName: userName,
        colorValue: colorValue,
        x: scenePoint.dx,
        y: scenePoint.dy,
        lastActive: now,
        toolName: state.tool.name,
      ),
    );
  }

  static int _colorForUserId(String id) {
    const palette = [
      0xFF3B82F6, // Blue
      0xFF10B981, // Emerald
      0xFFF59E0B, // Amber
      0xFF8B5CF6, // Purple
      0xFFEC4899, // Pink
      0xFF06B6D4, // Cyan
      0xFFF97316, // Orange
    ];
    return palette[id.hashCode.abs() % palette.length];
  }

  /// Triggers a simulated collaborator (useful for testing in Android Studio).
  Future<void> simulateCollaborator() async {
    if (state.boardId.isEmpty) return;
    if (_syncRepo is BroadcastBoardSyncRepository) {
      await (_syncRepo as BroadcastBoardSyncRepository)
          .simulateCollaboratorActivity(state.boardId);
    }
  }

  LastEditorLocation _buildCurrentEditorLocation() {
    final editorName = (_cachedUserName != null && _cachedUserName!.isNotEmpty)
        ? _cachedUserName!
        : 'Demo Editor';
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Prefer user's detected / explicitly chosen location
    final detected = _detectedUserLocation;
    if (detected != null) {
      return LastEditorLocation(
        latitude: detected.latitude,
        longitude: detected.longitude,
        locationName: detected.locationName,
        editorName: editorName,
        updatedAtMs: now,
      );
    }

    // 2. Or if there is a MapPinObject on the board, use the latest pin's location
    for (var i = state.objects.length - 1; i >= 0; i--) {
      final obj = state.objects[i];
      if (obj is MapPinObject) {
        return LastEditorLocation(
          latitude: obj.latitude,
          longitude: obj.longitude,
          locationName: obj.label,
          editorName: editorName,
          updatedAtMs: now,
        );
      }
    }

    // 3. Or keep existing lastEditorLocation coordinates with updated editorName
    final existing = state.lastEditorLocation;
    if (existing != null) {
      return LastEditorLocation(
        latitude: existing.latitude,
        longitude: existing.longitude,
        locationName: existing.locationName,
        editorName: editorName,
        updatedAtMs: now,
      );
    }

    // 4. Default fallback (Mumbai, India)
    return LastEditorLocation(
      latitude: 19.0760,
      longitude: 72.8777,
      locationName: 'Mumbai, India',
      editorName: editorName,
      updatedAtMs: now,
    );
  }

  Future<void> _triggerAutoSave() async {
    final editorLoc = _buildCurrentEditorLocation();
    state = state.copyWith(lastEditorLocation: editorLoc);

    if (state.boardId.isEmpty) return;
    state = state.copyWith(isSaving: true, statusMessage: 'Saving...');
    final storage = _storage ?? BoardStorageService();
    await storage.saveBoard(state.boardId, state.objects);
    await storage.saveLastEditorLocation(state.boardId, editorLoc);
    _syncRepo?.updateLastEditorLocation(state.boardId, editorLoc);
    state = state.copyWith(isSaving: false, statusMessage: 'Saved');
  }

  // ---- Tool & Styling ----

  void setTool(BoardTool tool) {
    state = state.copyWith(
      tool: tool,
      clearSelection: tool != BoardTool.select,
      clearActive: true,
    );
  }

  void setColor(Color color) {
    state = state.copyWith(color: color);
    if (state.selectedObjectId != null) {
      final selected = state.selectedObject;
      if (selected != null) {
        final updated = switch (selected) {
          StrokeObject s => s.copyWith(color: color),
          RectangleObject r => r.copyWith(color: color),
          CircleObject c => c.copyWith(color: color),
          LineObject l => l.copyWith(color: color),
          TextObject t => t.copyWith(color: color),
          StickyNoteObject n => n.copyWith(color: color),
          MapPinObject p => p.copyWith(color: color),
          GeometricShapeObject g => g.copyWith(color: color),
          ErTableObject t => t.copyWith(color: color),
          ErRelationshipObject r => r.copyWith(color: color),
        };
        _replaceObject(updated);
      }
    }
  }

  void setNoteColor(Color noteColor) {
    state = state.copyWith(noteColor: noteColor);
    if (state.selectedObjectId != null) {
      final selected = state.selectedObject;
      if (selected is StickyNoteObject) {
        _replaceObject(selected.copyWith(noteColor: noteColor));
      }
    }
  }

  void setWidth(double width) {
    state = state.copyWith(width: width);
    if (state.selectedObjectId != null) {
      final selected = state.selectedObject;
      if (selected != null) {
        final updated = switch (selected) {
          StrokeObject s => s.copyWith(strokeWidth: width),
          RectangleObject r => r.copyWith(strokeWidth: width),
          CircleObject c => c.copyWith(strokeWidth: width),
          LineObject l => l.copyWith(strokeWidth: width),
          TextObject t => t.copyWith(strokeWidth: width),
          StickyNoteObject n => n,
          MapPinObject p => p.copyWith(strokeWidth: width),
          GeometricShapeObject g => g.copyWith(strokeWidth: width),
          ErTableObject t => t,
          ErRelationshipObject r => r.copyWith(strokeWidth: width),
        };
        _replaceObject(updated);
      }
    }
  }

  List<List<BoardObject>> _pushPast() {
    final past = [...state.past, state.objects];
    return past.length > _maxHistory
        ? past.sublist(past.length - _maxHistory)
        : past;
  }

  // ---- Selection & Manipulation ----

  void selectAt(Offset scenePoint) {
    // Search in reverse Z-order to pick the top-most object matching current mode
    for (var i = state.objects.length - 1; i >= 0; i--) {
      final obj = state.objects[i];
      final belongsToCurrentMode = state.isMapMode
          ? (obj.isMapObject || obj is MapPinObject)
          : (!obj.isMapObject && obj is! MapPinObject);
      if (belongsToCurrentMode && obj.hitTest(scenePoint)) {
        state = state.copyWith(selectedObjectId: obj.id);
        return;
      }
    }
    state = state.copyWith(clearSelection: true);
  }

  void selectById(String? id) {
    if (id == null) {
      state = state.copyWith(clearSelection: true);
    } else {
      state = state.copyWith(selectedObjectId: id);
    }
  }

  void beginMove() {
    state = state.copyWith(past: _pushPast(), future: const []);
  }

  void moveSelected(Offset delta) {
    final selected = state.selectedObject;
    if (selected == null) return;
    if (selected.groupId != null) {
      final gid = selected.groupId!;
      final updated = [
        for (final o in state.objects)
          if (o.groupId == gid) o.translate(delta) else o,
      ];
      state = state.copyWith(objects: updated);
    } else {
      final moved = selected.translate(delta);
      final updated = [
        for (final o in state.objects)
          if (o.id == selected.id) moved else o,
      ];
      state = state.copyWith(objects: updated);
    }
  }

  void commitMove() {
    final selected = state.selectedObject;
    if (selected != null) {
      if (selected.groupId != null) {
        final gid = selected.groupId!;
        for (final o in state.objects) {
          if (o.groupId == gid) {
            _syncUpsert(o);
          }
        }
      } else {
        _syncUpsert(selected);
      }
    }
    _triggerAutoSave();
  }

  void resizeSelected(Rect newBounds) {
    final selected = state.selectedObject;
    if (selected == null) return;
    final resized = selected.resize(newBounds);
    _replaceObject(resized);
  }

  void duplicateSelected() {
    final selected = state.selectedObject;
    if (selected == null) return;
    final copy = selected.translate(const Offset(30, 30));
    final newId = _uuid.v4();
    final newObj = switch (copy) {
      StrokeObject s => s.copyWith(id: newId),
      RectangleObject r => r.copyWith(id: newId),
      CircleObject c => c.copyWith(id: newId),
      LineObject l => l.copyWith(id: newId),
      TextObject t => t.copyWith(id: newId),
      StickyNoteObject n => n.copyWith(id: newId),
      MapPinObject p => p.copyWith(
        id: newId,
        latitude: p.latitude - 0.2,
        longitude: p.longitude + 0.2,
      ),
      GeometricShapeObject g => g.copyWith(id: newId),
      ErTableObject t => t.copyWith(id: newId),
      ErRelationshipObject r => r.copyWith(id: newId),
    };
    state = state.copyWith(
      objects: [...state.objects, newObj],
      selectedObjectId: newId,
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
    _syncUpsert(newObj);
  }

  void deleteSelected() {
    final selectedId = state.selectedObjectId;
    if (selectedId == null) return;
    state = state.copyWith(
      objects: state.objects.where((o) => o.id != selectedId).toList(),
      clearSelection: true,
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
    _syncDelete(selectedId);
  }

  void bringToFront() {
    final selectedId = state.selectedObjectId;
    if (selectedId == null) return;
    final obj = state.selectedObject;
    if (obj == null) return;
    final remaining = state.objects.where((o) => o.id != selectedId).toList();
    state = state.copyWith(
      objects: [...remaining, obj],
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
  }

  void sendToBack() {
    final selectedId = state.selectedObjectId;
    if (selectedId == null) return;
    final obj = state.selectedObject;
    if (obj == null) return;
    final remaining = state.objects.where((o) => o.id != selectedId).toList();
    state = state.copyWith(
      objects: [obj, ...remaining],
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
  }

  void updateText(String id, String newText) {
    final obj = state.objects.firstWhere((o) => o.id == id);
    final updated = switch (obj) {
      TextObject t => t.copyWith(text: newText),
      StickyNoteObject n => n.copyWith(text: newText),
      MapPinObject p => p.copyWith(label: newText),
      GeometricShapeObject g => g.copyWith(label: newText),
      ErTableObject t => t.copyWith(tableName: newText),
      _ => obj,
    };
    _replaceObject(updated);
  }

  void _replaceObject(BoardObject updated) {
    final list = [
      for (final o in state.objects)
        if (o.id == updated.id) updated else o,
    ];
    state = state.copyWith(objects: list, past: _pushPast(), future: const []);
    _triggerAutoSave();
    _syncUpsert(updated);
  }

  // ---- Map Whiteboard Layer ----

  void toggleMapMode({Size? screenSize}) {
    final turningOn = !state.isMapMode;
    state = state.copyWith(isMapMode: turningOn, clearSelection: true);
    _triggerAutoSave();
    if (turningOn) {
      centerOnLastEditorLocation(screenSize: screenSize);
    }
  }

  /// Centers the Google Maps viewport on the geographic location of the person
  /// who last edited this board.
  void centerOnLastEditorLocation({Size? screenSize}) {
    final loc = state.lastEditorLocation ?? _buildCurrentEditorLocation();
    if (state.lastEditorLocation == null) {
      state = state.copyWith(lastEditorLocation: loc);
    }
    ref
        .read(viewportProvider.notifier)
        .centerOn(
          loc.scenePosition,
          screenSize: screenSize ?? const Size(800, 600),
          targetScale: 4.0,
        );
  }

  /// Updates the current editor's geographic location and centers the map on it.
  void setEditorLocation({
    required double latitude,
    required double longitude,
    required String locationName,
    Size? screenSize,
  }) {
    final editorName = (_cachedUserName != null && _cachedUserName!.isNotEmpty)
        ? _cachedUserName!
        : 'Demo Editor';
    final loc = LastEditorLocation(
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
      editorName: editorName,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _detectedUserLocation = loc;
    state = state.copyWith(lastEditorLocation: loc);
    if (state.boardId.isNotEmpty) {
      _storage?.saveLastEditorLocation(state.boardId, loc);
      _syncRepo?.updateLastEditorLocation(state.boardId, loc);
    }
    if (state.isMapMode) {
      centerOnLastEditorLocation(screenSize: screenSize);
    }
  }

  void addMapPinAt(
    Offset scenePoint, {
    String label = 'Pin',
    String description = '',
  }) {
    final (lat, lng) = const MercatorProjection().sceneToLatLng(scenePoint);
    final pin = MapPinObject(
      id: _uuid.v4(),
      latitude: lat,
      longitude: lng,
      label: label,
      description: description,
      color: state.color,
    );
    _detectedUserLocation = LastEditorLocation(
      latitude: lat,
      longitude: lng,
      locationName: label,
      editorName: _cachedUserName ?? 'Demo Editor',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    state = state.copyWith(
      objects: [...state.objects, pin],
      selectedObjectId: pin.id,
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
    _syncUpsert(pin);
  }

  void panToLocation(MapLocationPreset preset, {Size? screenSize}) {
    final pos = const MercatorProjection().latLngToScene(
      preset.latitude,
      preset.longitude,
    );
    setEditorLocation(
      latitude: preset.latitude,
      longitude: preset.longitude,
      locationName: '${preset.name}, ${preset.country}',
      screenSize: screenSize,
    );
    ref
        .read(viewportProvider.notifier)
        .centerOn(
          pos,
          screenSize: screenSize ?? const Size(800, 600),
          targetScale: 1.0,
        );
  }

  // ---- Gemini AI Multimodal Engine ----

  /// Generates a mindmap (Gemini when configured, offline otherwise) centred
  /// at [origin] and returns a user-facing status message.
  Future<String> generateMindmapFromPrompt(
    String prompt, {
    Offset? origin,
  }) async {
    final ai = _aiService ?? const GeminiAIService();
    final result = await ai.generateMindmapSmart(
      prompt,
      origin: origin ?? const Offset(400, 300),
    );
    if (!ref.mounted) return result.message;
    final newObjects = result.value;

    state = state.copyWith(
      objects: [...state.objects, ...newObjects],
      selectedObjectId: newObjects.isNotEmpty ? newObjects.first.id : null,
      tool: BoardTool.select,
      past: _pushPast(),
      future: const [],
    );

    for (final obj in newObjects) {
      _syncUpsert(obj);
    }
    _triggerAutoSave();
    return result.message;
  }

  /// Converts the selected freehand stroke into a clean vector shape.
  /// Returns a user-facing status message.
  String cleanSelectedStrokeWithAI() {
    final selected = state.selectedObject;
    if (selected is! StrokeObject) {
      return 'Select a hand-drawn pen stroke first (Select tool, then tap it).';
    }

    final ai = _aiService ?? const GeminiAIService();
    final cleanShape = ai.recognizeRoughShape(selected);
    if (cleanShape == null) {
      return 'Could not recognise a line, circle or rectangle in that stroke.';
    }
    _replaceObject(cleanShape);
    return switch (cleanShape) {
      LineObject() => 'Stroke converted to a straight arrow.',
      CircleObject() => 'Stroke converted to a circle.',
      RectangleObject() => 'Stroke converted to a rectangle.',
      _ => 'Stroke converted to a clean shape.',
    };
  }

  /// Adds an AI summary card to the board (Gemini when configured).
  /// Returns a user-facing status message.
  Future<String> generateBoardSummaryWithAI({Offset? position}) async {
    final ai = _aiService ?? const GeminiAIService();
    final result = await ai.generateBoardSummarySmart(
      state.objects,
      position: position ?? const Offset(60, 60),
    );
    if (!ref.mounted) return result.message;
    final summaryNote = result.value;

    state = state.copyWith(
      objects: [...state.objects, summaryNote],
      selectedObjectId: summaryNote.id,
      tool: BoardTool.select,
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
    _syncUpsert(summaryNote);
    return result.message;
  }

  // ---- Drawing & Shape Creation Pipeline ----

  void startDrawing(Offset scenePoint, {double? strokeWidth}) {
    _dragOrigin = scenePoint;
    final id = _uuid.v4();
    final effectiveWidth = strokeWidth ?? state.width;

    switch (state.tool) {
      case BoardTool.pen:
        state = state.copyWith(
          activeObject: StrokeObject(
            id: id,
            points: [scenePoint],
            color: state.color,
            strokeWidth: effectiveWidth,
            isHighlighter: false,
            isMapObject: state.isMapMode,
          ),
        );
      case BoardTool.highlighter:
        state = state.copyWith(
          activeObject: StrokeObject(
            id: id,
            points: [scenePoint],
            color: state.color.withValues(alpha: 0.35),
            strokeWidth: effectiveWidth * 3,
            isHighlighter: true,
            isMapObject: state.isMapMode,
          ),
        );
      case BoardTool.rectangle:
        state = state.copyWith(
          activeObject: RectangleObject(
            id: id,
            rect: Rect.fromPoints(scenePoint, scenePoint),
            color: state.color,
            strokeWidth: state.width,
            isMapObject: state.isMapMode,
          ),
        );
      case BoardTool.circle:
        state = state.copyWith(
          activeObject: CircleObject(
            id: id,
            rect: Rect.fromPoints(scenePoint, scenePoint),
            color: state.color,
            strokeWidth: state.width,
            isMapObject: state.isMapMode,
          ),
        );
      case BoardTool.line:
        state = state.copyWith(
          activeObject: LineObject(
            id: id,
            start: scenePoint,
            end: scenePoint,
            color: state.color,
            strokeWidth: state.width,
            isArrow: false,
            isMapObject: state.isMapMode,
          ),
        );
      case BoardTool.arrow:
        state = state.copyWith(
          activeObject: LineObject(
            id: id,
            start: scenePoint,
            end: scenePoint,
            color: state.color,
            strokeWidth: state.width,
            isArrow: true,
            isMapObject: state.isMapMode,
          ),
        );
      case BoardTool.stickyNote:
        state = state.copyWith(
          activeObject: StickyNoteObject(
            id: id,
            rect: Rect.fromLTWH(scenePoint.dx, scenePoint.dy, 180, 140),
            text: 'New Note',
            color: state.color,
            noteColor: state.noteColor,
            isMapObject: state.isMapMode,
          ),
        );
      case BoardTool.triangle:
      case BoardTool.diamond:
      case BoardTool.star:
      case BoardTool.hexagon:
      case BoardTool.parallelogram:
      case BoardTool.cylinder:
      case BoardTool.cloud:
        final shapeType = switch (state.tool) {
          BoardTool.triangle => ShapeType.triangle,
          BoardTool.diamond => ShapeType.diamond,
          BoardTool.star => ShapeType.star,
          BoardTool.hexagon => ShapeType.hexagon,
          BoardTool.parallelogram => ShapeType.parallelogram,
          BoardTool.cylinder => ShapeType.cylinder,
          _ => ShapeType.cloud,
        };
        state = state.copyWith(
          activeObject: GeometricShapeObject(
            id: id,
            shapeType: shapeType,
            rect: Rect.fromPoints(scenePoint, scenePoint),
            color: state.color,
            strokeWidth: state.width,
            isMapObject: state.isMapMode,
          ),
        );
      case BoardTool.erRelationship:
        state = state.copyWith(
          activeObject: ErRelationshipObject(
            id: id,
            start: scenePoint,
            end: scenePoint,
            color: state.color,
            strokeWidth: state.width,
            cardinality: ErCardinality.oneToMany,
            isMapObject: state.isMapMode,
          ),
        );
      case BoardTool.erTable:
      case BoardTool.text:
      case BoardTool.mapPin:
        // Handled on pointer up / tap
        break;
      case BoardTool.select:
      case BoardTool.eraser:
      case BoardTool.hand:
        break;
    }
  }

  void extendDrawing(Offset scenePoint, double minDistance) {
    final active = state.activeObject;
    if (active == null || _dragOrigin == null) return;

    if (active is StrokeObject) {
      if ((active.points.last - scenePoint).distance < minDistance) return;
      state = state.copyWith(
        activeObject: active.copyWith(points: [...active.points, scenePoint]),
      );
    } else if (active is RectangleObject) {
      state = state.copyWith(
        activeObject: active.copyWith(
          rect: Rect.fromPoints(_dragOrigin!, scenePoint),
        ),
      );
    } else if (active is CircleObject) {
      state = state.copyWith(
        activeObject: active.copyWith(
          rect: Rect.fromPoints(_dragOrigin!, scenePoint),
        ),
      );
    } else if (active is LineObject) {
      state = state.copyWith(activeObject: active.copyWith(end: scenePoint));
    } else if (active is StickyNoteObject) {
      final rect = Rect.fromPoints(_dragOrigin!, scenePoint);
      if (rect.width > 40 && rect.height > 40) {
        state = state.copyWith(activeObject: active.copyWith(rect: rect));
      }
    } else if (active is GeometricShapeObject) {
      state = state.copyWith(
        activeObject: active.copyWith(
          rect: Rect.fromPoints(_dragOrigin!, scenePoint),
        ),
      );
    } else if (active is ErRelationshipObject) {
      state = state.copyWith(activeObject: active.copyWith(end: scenePoint));
    }
  }

  void endDrawing() {
    final active = state.activeObject;
    if (active == null) return;

    // Filter out accidental micro-taps on shapes
    if (active is RectangleObject &&
        (active.rect.width < 5 || active.rect.height < 5)) {
      cancelDrawing();
      return;
    }
    if (active is CircleObject &&
        (active.rect.width < 5 || active.rect.height < 5)) {
      cancelDrawing();
      return;
    }
    if (active is GeometricShapeObject &&
        (active.rect.width < 5 || active.rect.height < 5)) {
      cancelDrawing();
      return;
    }

    state = state.copyWith(
      objects: [...state.objects, active],
      clearActive: true,
      selectedObjectId:
          state.tool != BoardTool.pen && state.tool != BoardTool.highlighter
          ? active.id
          : null,
      past: _pushPast(),
      future: const [],
    );
    _dragOrigin = null;
    _triggerAutoSave();
    _syncUpsert(active);
  }

  void cancelDrawing() {
    state = state.copyWith(clearActive: true);
    _dragOrigin = null;
  }

  // ---- Text & Sticky Note Quick Creation ----

  void addTextAt(Offset scenePoint, String text) {
    final textObj = TextObject(
      id: _uuid.v4(),
      position: scenePoint,
      text: text.isEmpty ? 'Type here...' : text,
      color: state.color,
      isMapObject: state.isMapMode,
    );
    state = state.copyWith(
      objects: [...state.objects, textObj],
      selectedObjectId: textObj.id,
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
    _syncUpsert(textObj);
  }

  void addStickyNoteAt(
    Offset scenePoint, {
    String text = 'Note',
    Color? noteColor,
  }) {
    final chosenColor = noteColor ?? state.noteColor;
    final note = StickyNoteObject(
      id: _uuid.v4(),
      rect: Rect.fromLTWH(scenePoint.dx, scenePoint.dy, 180, 140),
      text: text.trim().isEmpty ? 'Note' : text.trim(),
      color: const Color(0xFF1F2937),
      noteColor: chosenColor,
      isMapObject: state.isMapMode,
    );
    state = state.copyWith(
      objects: [...state.objects, note],
      selectedObjectId: note.id,
      noteColor: chosenColor,
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
    _syncUpsert(note);
  }

  void addGeometricShapeAt(
    Offset scenePoint,
    ShapeType shapeType, {
    String label = '',
    Size size = const Size(160, 110),
  }) {
    final shape = GeometricShapeObject(
      id: _uuid.v4(),
      shapeType: shapeType,
      rect: Rect.fromLTWH(
        scenePoint.dx,
        scenePoint.dy,
        size.width,
        size.height,
      ),
      color: state.color,
      strokeWidth: state.width,
      label: label,
      isMapObject: state.isMapMode,
    );
    state = state.copyWith(
      objects: [...state.objects, shape],
      selectedObjectId: shape.id,
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
    _syncUpsert(shape);
  }

  void addErTableAt(
    Offset scenePoint, {
    required String tableName,
    required List<ErColumn> columns,
    Color? color,
    double width = 240.0,
  }) {
    final table = ErTableObject(
      id: _uuid.v4(),
      position: scenePoint,
      tableName: tableName,
      columns: columns,
      color: color ?? state.color,
      width: width,
      isMapObject: state.isMapMode,
    );
    state = state.copyWith(
      objects: [...state.objects, table],
      selectedObjectId: table.id,
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
    _syncUpsert(table);
  }

  void addErRelationship(
    Offset start,
    Offset end, {
    String? fromTableId,
    String? toTableId,
    ErCardinality cardinality = ErCardinality.oneToMany,
    String label = '',
  }) {
    final rel = ErRelationshipObject(
      id: _uuid.v4(),
      start: start,
      end: end,
      color: state.color,
      strokeWidth: state.width,
      cardinality: cardinality,
      fromTableId: fromTableId,
      toTableId: toTableId,
      label: label,
      isMapObject: state.isMapMode,
    );
    state = state.copyWith(
      objects: [...state.objects, rel],
      selectedObjectId: rel.id,
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
    _syncUpsert(rel);
  }

  void insertErTemplate(
    String templateName, {
    Offset origin = const Offset(150, 150),
  }) {
    final List<BoardObject> templateObjects = [];

    switch (templateName) {
      case 'E-Commerce Schema':
        final usersTable = ErTableObject(
          id: _uuid.v4(),
          position: origin,
          tableName: 'users',
          columns: const [
            ErColumn(name: 'id', type: 'UUID', isPrimaryKey: true),
            ErColumn(name: 'email', type: 'VARCHAR(255)'),
            ErColumn(name: 'password_hash', type: 'VARCHAR(255)'),
            ErColumn(name: 'full_name', type: 'VARCHAR(100)', isNullable: true),
            ErColumn(name: 'created_at', type: 'TIMESTAMP'),
          ],
          color: const Color(0xFF2563EB),
        );
        final ordersTable = ErTableObject(
          id: _uuid.v4(),
          position: origin + const Offset(340, 0),
          tableName: 'orders',
          columns: const [
            ErColumn(name: 'id', type: 'UUID', isPrimaryKey: true),
            ErColumn(name: 'user_id', type: 'UUID', isForeignKey: true),
            ErColumn(name: 'status', type: 'VARCHAR(50)'),
            ErColumn(name: 'total_amount', type: 'DECIMAL(10,2)'),
            ErColumn(name: 'created_at', type: 'TIMESTAMP'),
          ],
          color: const Color(0xFF059669),
        );
        final itemsTable = ErTableObject(
          id: _uuid.v4(),
          position: origin + const Offset(340, 220),
          tableName: 'order_items',
          columns: const [
            ErColumn(name: 'id', type: 'UUID', isPrimaryKey: true),
            ErColumn(name: 'order_id', type: 'UUID', isForeignKey: true),
            ErColumn(name: 'product_id', type: 'UUID', isForeignKey: true),
            ErColumn(name: 'quantity', type: 'INT'),
            ErColumn(name: 'unit_price', type: 'DECIMAL(10,2)'),
          ],
          color: const Color(0xFFD97706),
        );
        final productsTable = ErTableObject(
          id: _uuid.v4(),
          position: origin + const Offset(0, 220),
          tableName: 'products',
          columns: const [
            ErColumn(name: 'id', type: 'UUID', isPrimaryKey: true),
            ErColumn(name: 'sku', type: 'VARCHAR(64)'),
            ErColumn(name: 'title', type: 'VARCHAR(200)'),
            ErColumn(name: 'price', type: 'DECIMAL(10,2)'),
            ErColumn(name: 'stock_qty', type: 'INT'),
          ],
          color: const Color(0xFF7C3AED),
        );

        final relUsersOrders = ErRelationshipObject(
          id: _uuid.v4(),
          start: usersTable.bounds.centerRight,
          end: ordersTable.bounds.centerLeft,
          color: const Color(0xFF2563EB),
          cardinality: ErCardinality.oneToMany,
          fromTableId: usersTable.id,
          toTableId: ordersTable.id,
          label: 'places',
        );
        final relOrdersItems = ErRelationshipObject(
          id: _uuid.v4(),
          start: ordersTable.bounds.bottomCenter,
          end: itemsTable.bounds.topCenter,
          color: const Color(0xFF059669),
          cardinality: ErCardinality.oneToMany,
          fromTableId: ordersTable.id,
          toTableId: itemsTable.id,
          label: 'contains',
        );
        final relProductsItems = ErRelationshipObject(
          id: _uuid.v4(),
          start: productsTable.bounds.centerRight,
          end: itemsTable.bounds.centerLeft,
          color: const Color(0xFF7C3AED),
          cardinality: ErCardinality.oneToMany,
          fromTableId: productsTable.id,
          toTableId: itemsTable.id,
          label: 'itemized_in',
        );

        templateObjects.addAll([
          usersTable,
          ordersTable,
          itemsTable,
          productsTable,
          relUsersOrders,
          relOrdersItems,
          relProductsItems,
        ]);

      case 'Auth & Roles':
        final accounts = ErTableObject(
          id: _uuid.v4(),
          position: origin,
          tableName: 'accounts',
          columns: const [
            ErColumn(name: 'id', type: 'UUID', isPrimaryKey: true),
            ErColumn(name: 'username', type: 'VARCHAR(50)'),
            ErColumn(name: 'email', type: 'VARCHAR(150)'),
            ErColumn(name: 'is_active', type: 'BOOLEAN'),
          ],
          color: const Color(0xFF0284C7),
        );
        final roles = ErTableObject(
          id: _uuid.v4(),
          position: origin + const Offset(360, 0),
          tableName: 'roles',
          columns: const [
            ErColumn(name: 'id', type: 'VARCHAR(32)', isPrimaryKey: true),
            ErColumn(name: 'description', type: 'VARCHAR(255)'),
          ],
          color: const Color(0xFF9333EA),
        );
        final accountRoles = ErTableObject(
          id: _uuid.v4(),
          position: origin + const Offset(180, 180),
          tableName: 'account_roles',
          columns: const [
            ErColumn(name: 'account_id', type: 'UUID', isForeignKey: true),
            ErColumn(name: 'role_id', type: 'VARCHAR(32)', isForeignKey: true),
            ErColumn(name: 'assigned_at', type: 'TIMESTAMP'),
          ],
          color: const Color(0xFF0D9488),
        );
        final rel1 = ErRelationshipObject(
          id: _uuid.v4(),
          start: accounts.bounds.bottomCenter,
          end: accountRoles.bounds.topLeft,
          color: const Color(0xFF0284C7),
          cardinality: ErCardinality.oneToMany,
          fromTableId: accounts.id,
          toTableId: accountRoles.id,
        );
        final rel2 = ErRelationshipObject(
          id: _uuid.v4(),
          start: roles.bounds.bottomCenter,
          end: accountRoles.bounds.topRight,
          color: const Color(0xFF9333EA),
          cardinality: ErCardinality.oneToMany,
          fromTableId: roles.id,
          toTableId: accountRoles.id,
        );
        templateObjects.addAll([accounts, roles, accountRoles, rel1, rel2]);

      case 'Microservices Flow':
      default:
        final clientShape = GeometricShapeObject(
          id: _uuid.v4(),
          shapeType: ShapeType.cloud,
          rect: Rect.fromLTWH(origin.dx, origin.dy + 30, 160, 90),
          color: const Color(0xFF2563EB),
          label: 'API Gateway',
        );
        final serviceShape = GeometricShapeObject(
          id: _uuid.v4(),
          shapeType: ShapeType.hexagon,
          rect: Rect.fromLTWH(origin.dx + 240, origin.dy + 25, 140, 100),
          color: const Color(0xFF10B981),
          label: 'Order Service',
        );
        final dbShape = GeometricShapeObject(
          id: _uuid.v4(),
          shapeType: ShapeType.cylinder,
          rect: Rect.fromLTWH(origin.dx + 460, origin.dy + 20, 130, 110),
          color: const Color(0xFFF59E0B),
          label: 'Primary DB',
        );
        final conn1 = ErRelationshipObject(
          id: _uuid.v4(),
          start: clientShape.bounds.centerRight,
          end: serviceShape.bounds.centerLeft,
          color: const Color(0xFF2563EB),
          cardinality: ErCardinality.oneToMany,
          label: 'REST / gRPC',
        );
        final conn2 = ErRelationshipObject(
          id: _uuid.v4(),
          start: serviceShape.bounds.centerRight,
          end: dbShape.bounds.centerLeft,
          color: const Color(0xFF10B981),
          cardinality: ErCardinality.oneToOne,
          label: 'PostgreSQL Pool',
        );
        templateObjects.addAll([
          clientShape,
          serviceShape,
          dbShape,
          conn1,
          conn2,
        ]);
    }

    state = state.copyWith(
      objects: [...state.objects, ...templateObjects],
      past: _pushPast(),
      future: const [],
    );
    for (final obj in templateObjects) {
      _syncUpsert(obj);
    }
    _triggerAutoSave();
  }

  // ---- Erasing ----

  void beginErase() {
    state = state.copyWith(past: _pushPast(), future: const []);
  }

  void eraseAt(Offset scenePoint, double radius) {
    final hitBox = Rect.fromCircle(center: scenePoint, radius: radius);
    final remaining = state.objects.where((o) {
      final belongsToCurrentMode = state.isMapMode
          ? (o.isMapObject || o is MapPinObject)
          : (!o.isMapObject && o is! MapPinObject);
      if (!belongsToCurrentMode) {
        return true;
      }
      if (!o.bounds.inflate(o.strokeWidth / 2 + radius).overlaps(hitBox)) {
        return true;
      }
      return !o.hitTest(scenePoint, padding: radius);
    }).toList();

    if (remaining.length != state.objects.length) {
      final removed = state.objects.where((o) => !remaining.contains(o));
      for (final r in removed) {
        _syncDelete(r.id);
      }
      state = state.copyWith(
        objects: remaining,
        clearSelection: remaining.every((o) => o.id != state.selectedObjectId),
      );
      _triggerAutoSave();
    }
  }

  // ---- History (Undo / Redo / Clear) ----

  void undo() {
    if (!state.canUndo) return;
    state = state.copyWith(
      objects: state.past.last,
      past: state.past.sublist(0, state.past.length - 1),
      future: [...state.future, state.objects],
      clearSelection: true,
    );
    _triggerAutoSave();
  }

  void redo() {
    if (!state.canRedo) return;
    state = state.copyWith(
      objects: state.future.last,
      future: state.future.sublist(0, state.future.length - 1),
      past: [...state.past, state.objects],
      clearSelection: true,
    );
    _triggerAutoSave();
  }

  void clear() {
    if (state.objects.isEmpty) return;
    state = state.copyWith(
      objects: const [],
      clearSelection: true,
      clearActive: true,
      past: _pushPast(),
      future: const [],
    );
    _triggerAutoSave();
    _syncClear();
  }

  // ---- Export & Sharing (Stage S8) ----

  Future<Uint8List> exportPng({
    double pixelRatio = 2.0,
    Color backgroundColor = Colors.white,
    double padding = 40.0,
  }) {
    final visibleObjects = state.objects.where((o) {
      return state.isMapMode
          ? (o.isMapObject || o is MapPinObject)
          : (!o.isMapObject && o is! MapPinObject);
    }).toList();

    return ref
        .read(exportServiceProvider)
        .exportToPng(
          visibleObjects.isEmpty ? state.objects : visibleObjects,
          pixelRatio: pixelRatio,
          backgroundColor: backgroundColor,
          padding: padding,
        );
  }

  String exportSvg({
    Color backgroundColor = Colors.white,
    double padding = 40.0,
  }) {
    return ref
        .read(exportServiceProvider)
        .exportToSvg(
          state.objects,
          backgroundColor: backgroundColor,
          padding: padding,
        );
  }

  String exportJson({String title = 'Whiteboard Backup'}) {
    return ref
        .read(exportServiceProvider)
        .exportToJson(state.objects, boardId: state.boardId, title: title);
  }

  void importJson(String jsonString) {
    final imported = ref.read(exportServiceProvider).importFromJson(jsonString);
    if (imported.isEmpty) return;
    state = state.copyWith(
      objects: [...state.objects, ...imported],
      past: _pushPast(),
      future: const [],
      clearSelection: true,
    );
    _triggerAutoSave();
    for (final obj in imported) {
      _syncUpsert(obj);
    }
  }

  String getShareLink({ShareAccess access = ShareAccess.readWrite}) {
    return ref
        .read(exportServiceProvider)
        .generateShareLink(
          state.boardId.isEmpty ? 'demo' : state.boardId,
          access: access,
        );
  }
}

final exportServiceProvider = Provider<BoardExportService>(
  (ref) => const BoardExportService(),
);

final boardProvider = NotifierProvider.autoDispose<BoardNotifier, BoardState>(
  BoardNotifier.new,
);

// ---------------------------------------------------------------------------
// Viewport (Camera pan & zoom)
// ---------------------------------------------------------------------------

const kMinZoom = 0.1;
const kMaxZoom = 64.0;

@immutable
class Viewport {
  const Viewport({this.pan = Offset.zero, this.scale = 1});
  final Offset pan;
  final double scale;

  Offset toScene(Offset screen) => (screen - pan) / scale;
  Offset toScreen(Offset scene) => scene * scale + pan;
}

class ViewportNotifier extends Notifier<Viewport> {
  @override
  Viewport build() => const Viewport();

  void set(Offset pan, double scale) =>
      state = Viewport(pan: pan, scale: scale.clamp(kMinZoom, kMaxZoom));

  /// Zooms by [factor] keeping the scene point under [focal] fixed on screen.
  void zoomAt(Offset focal, double factor) {
    final newScale = (state.scale * factor).clamp(kMinZoom, kMaxZoom);
    final anchor = state.toScene(focal);
    state = Viewport(pan: focal - anchor * newScale, scale: newScale);
  }

  void reset() => state = const Viewport();

  /// Centers the camera on [scenePoint] for a given [screenSize].
  void centerOn(
    Offset scenePoint, {
    Size screenSize = const Size(800, 600),
    double? targetScale,
  }) {
    final scale = (targetScale ?? state.scale).clamp(kMinZoom, kMaxZoom);
    final pan =
        Offset(screenSize.width / 2, screenSize.height / 2) -
        scenePoint * scale;
    state = Viewport(pan: pan, scale: scale);
  }
}

final viewportProvider =
    NotifierProvider.autoDispose<ViewportNotifier, Viewport>(
      ViewportNotifier.new,
    );
