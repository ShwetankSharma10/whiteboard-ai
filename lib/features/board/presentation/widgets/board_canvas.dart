import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/board_object.dart';
import '../../domain/models/map_projection.dart';
import '../providers/board_provider.dart';
import '../providers/sync_provider.dart';
import 'board_toolbar.dart';
import 'google_map_tile_layer.dart';
import 'painters.dart';
import '../../data/stylus_service.dart';

/// Returns true if [obj] has editable text/label content.
bool canEditObjectText(BoardObject? obj) => switch (obj) {
  StickyNoteObject() ||
  TextObject() ||
  GeometricShapeObject() ||
  MapPinObject() ||
  ErTableObject() => true,
  _ => false,
};

/// Opens a dialog to edit the text/label (and sticky note color) of [obj].
void showEditObjectTextDialog(
  BuildContext context,
  WidgetRef ref,
  BoardObject obj,
) {
  final initialText = switch (obj) {
    StickyNoteObject n => n.text,
    TextObject t => t.text,
    GeometricShapeObject g => g.label,
    MapPinObject p => p.label,
    ErTableObject t => t.tableName,
    _ => '',
  };
  final title = switch (obj) {
    StickyNoteObject() => 'Edit Sticky Note',
    TextObject() => 'Edit Text',
    GeometricShapeObject() => 'Edit Shape Label',
    MapPinObject() => 'Edit Map Pin Label',
    ErTableObject() => 'Edit Table Name',
    _ => 'Edit Text',
  };

  final controller = TextEditingController(text: initialText);
  var chosenNoteColor = obj is StickyNoteObject
      ? obj.noteColor
      : ref.read(boardProvider).noteColor;

  showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) => AlertDialog(
        title: Row(
          children: [
            Icon(
              obj is StickyNoteObject
                  ? Icons.note_alt_outlined
                  : Icons.edit_note,
              color: const Color(0xFF0D54FF),
            ),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: obj is StickyNoteObject || obj is TextObject ? 4 : 1,
              decoration: const InputDecoration(
                hintText: 'Type your note or text here...',
                border: OutlineInputBorder(),
              ),
            ),
            if (obj is StickyNoteObject) ...[
              const SizedBox(height: 12),
              const Text(
                'Note Color',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in kStickyNotePalette)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        setModalState(() => chosenNoteColor = c);
                        ref.read(boardProvider.notifier).setNoteColor(c);
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c == chosenNoteColor
                                ? const Color(0xFF0D54FF)
                                : const Color(0xFFCBD5E1),
                            width: c == chosenNoteColor ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                ref.read(boardProvider.notifier).updateText(obj.id, text);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

enum _InteractionMode { idle, draw, erase, move, transform }

class BoardCanvas extends ConsumerStatefulWidget {
  const BoardCanvas({super.key, required this.readOnly});

  final bool readOnly;

  @override
  ConsumerState<BoardCanvas> createState() => _BoardCanvasState();
}

class _BoardCanvasState extends ConsumerState<BoardCanvas> {
  final Map<int, Offset> _pointers = {};
  _InteractionMode _mode = _InteractionMode.idle;

  Offset _startPan = Offset.zero;
  double _startScale = 1;
  Offset _startFocal = Offset.zero;
  double _startDist = 1;
  Offset _lastPointerScene = Offset.zero;
  int _lastTapTimeMs = 0;
  Offset _lastTapScreen = Offset.zero;

  static const _eraserScreenRadius = 14.0;
  final _stylus = StylusService();
  final ValueNotifier<Offset> _hoverSceneNotifier = ValueNotifier<Offset>(
    const Offset(2048, 2048),
  );

  @override
  void dispose() {
    _hoverSceneNotifier.dispose();
    super.dispose();
  }

  BoardNotifier get _board => ref.read(boardProvider.notifier);
  ViewportNotifier get _viewport => ref.read(viewportProvider.notifier);

  Offset _centroid(Iterable<Offset> pts) =>
      pts.fold(Offset.zero, (a, b) => a + b) / pts.length.toDouble();

  void _beginTransform() {
    final vp = ref.read(viewportProvider);
    final pts = _pointers.values.toList();
    _startPan = vp.pan;
    _startScale = vp.scale;
    _startFocal = _centroid(pts);
    _startDist = pts.length >= 2 ? (pts[0] - pts[1]).distance : 1;
    _mode = _InteractionMode.transform;
  }

  void _onDown(PointerDownEvent e) {
    final classification = _stylus.classifyPointerEvent(
      e,
      activePointersCount: _pointers.length + 1,
    );

    if (classification == StylusInteractionType.rejectedPalm) {
      return;
    }

    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length > 1) {
      if (_mode == _InteractionMode.draw) _board.cancelDrawing();
      _beginTransform();
      return;
    }

    final tool = ref.read(boardProvider).tool;
    final isMouseSecondary =
        e.kind == PointerDeviceKind.mouse &&
        e.buttons != 0 &&
        (e.buttons & kPrimaryMouseButton) == 0;
    final canEdit =
        !widget.readOnly && tool != BoardTool.hand && !isMouseSecondary;

    if (!canEdit) {
      _beginTransform();
      return;
    }

    final vp = ref.read(viewportProvider);
    final scene = vp.toScene(e.localPosition);
    _lastPointerScene = scene;

    if (classification == StylusInteractionType.invertedStylusErase) {
      _board.beginErase();
      _board.eraseAt(scene, _eraserScreenRadius / vp.scale);
      _mode = _InteractionMode.erase;
      return;
    }

    switch (tool) {
      case BoardTool.select:
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final isDoubleTap =
            (nowMs - _lastTapTimeMs) < 400 &&
            (e.localPosition - _lastTapScreen).distance < 24;
        _lastTapTimeMs = nowMs;
        _lastTapScreen = e.localPosition;

        final isMapMode = ref.read(boardProvider).isMapMode;
        final currentSelected = ref.read(boardProvider).selectedObject;
        final isCurrentSelectedVisible =
            currentSelected != null &&
            (isMapMode
                ? (currentSelected.isMapObject ||
                      currentSelected is MapPinObject)
                : (!currentSelected.isMapObject &&
                      currentSelected is! MapPinObject));

        if (isCurrentSelectedVisible && currentSelected.hitTest(scene)) {
          if (isDoubleTap && canEditObjectText(currentSelected)) {
            _mode = _InteractionMode.idle;
            _pointers.remove(e.pointer);
            showEditObjectTextDialog(context, ref, currentSelected);
            return;
          }
          // Drag selected object
          _board.beginMove();
          _mode = _InteractionMode.move;
        } else {
          // Select object under cursor
          _board.selectAt(scene);
          final newlySelected = ref.read(boardProvider).selectedObject;
          if (newlySelected != null) {
            if (isDoubleTap && canEditObjectText(newlySelected)) {
              _mode = _InteractionMode.idle;
              _pointers.remove(e.pointer);
              showEditObjectTextDialog(context, ref, newlySelected);
              return;
            }
            _board.beginMove();
            _mode = _InteractionMode.move;
          }
        }
      case BoardTool.eraser:
        _board.beginErase();
        _board.eraseAt(scene, _eraserScreenRadius / vp.scale);
        _mode = _InteractionMode.erase;
      case BoardTool.text:
        _promptTextCreation(context, scene);
      case BoardTool.stickyNote:
        _promptStickyNoteCreation(context, scene);
      case BoardTool.mapPin:
        _promptMapPinCreation(context, scene);
      case BoardTool.pen:
      case BoardTool.highlighter:
      case BoardTool.rectangle:
      case BoardTool.circle:
      case BoardTool.line:
      case BoardTool.arrow:
      case BoardTool.triangle:
      case BoardTool.diamond:
      case BoardTool.star:
      case BoardTool.hexagon:
      case BoardTool.parallelogram:
      case BoardTool.cylinder:
      case BoardTool.cloud:
      case BoardTool.erRelationship:
        final dynamicWidth = StylusService.calculateDynamicWidth(
          baseWidth: ref.read(boardProvider).width,
          pressure: e.pressure,
          kind: e.kind,
        );
        _board.startDrawing(scene, strokeWidth: dynamicWidth);
        _mode = _InteractionMode.draw;
      case BoardTool.erTable:
        _promptErTableCreation(context, scene);
      case BoardTool.hand:
        _beginTransform();
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) {
      return;
    }
    if (_stylus.classifyPointerEvent(e) == StylusInteractionType.rejectedPalm) {
      return;
    }
    _pointers[e.pointer] = e.localPosition;
    final vp = ref.read(viewportProvider);
    final scene = vp.toScene(e.localPosition);

    switch (_mode) {
      case _InteractionMode.draw:
        _board.extendDrawing(scene, 1.5 / vp.scale);
      case _InteractionMode.move:
        final delta = scene - _lastPointerScene;
        _board.moveSelected(delta);
        _lastPointerScene = scene;
      case _InteractionMode.erase:
        _board.eraseAt(scene, _eraserScreenRadius / vp.scale);
      case _InteractionMode.transform:
        final pts = _pointers.values.toList();
        final focal = _centroid(pts);
        var scale = _startScale;
        if (pts.length >= 2 && _startDist > 0) {
          scale = (_startScale * (pts[0] - pts[1]).distance / _startDist).clamp(
            kMinZoom,
            kMaxZoom,
          );
        }
        final anchor = (_startFocal - _startPan) / _startScale;
        _viewport.set(focal - anchor * scale, scale);
      case _InteractionMode.idle:
        break;
    }
  }

  void _onUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    switch (_mode) {
      case _InteractionMode.draw:
        if (e is PointerCancelEvent) {
          _board.cancelDrawing();
        } else {
          _board.endDrawing();
        }
        _mode = _InteractionMode.idle;
      case _InteractionMode.move:
        _board.commitMove();
        _mode = _InteractionMode.idle;
      case _InteractionMode.erase:
        _mode = _InteractionMode.idle;
      case _InteractionMode.transform:
        if (_pointers.isEmpty) {
          _mode = _InteractionMode.idle;
        } else {
          _beginTransform(); // Re-anchor when lifting one finger
        }
      case _InteractionMode.idle:
        break;
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      _viewport.zoomAt(e.localPosition, math.exp(-e.scrollDelta.dy / 300));
    }
  }

  void _onPanZoomStart(PointerPanZoomStartEvent e) {
    final vp = ref.read(viewportProvider);
    _startPan = vp.pan;
    _startScale = vp.scale;
    _startFocal = e.localPosition;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    final scale = (_startScale * e.scale).clamp(kMinZoom, kMaxZoom);
    final anchor = (_startFocal - _startPan) / _startScale;
    _viewport.set(_startFocal + e.pan - anchor * scale, scale);
  }

  void _promptStickyNoteCreation(BuildContext context, Offset scenePoint) {
    final controller = TextEditingController();
    var chosenColor = ref.read(boardProvider).noteColor;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.note_alt_outlined, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('Add Sticky Note'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Write your sticky note text here...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Note Color',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in kStickyNotePalette)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setModalState(() => chosenColor = c),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c == chosenColor
                                ? const Color(0xFF0D54FF)
                                : const Color(0xFFCBD5E1),
                            width: c == chosenColor ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                _board.addStickyNoteAt(
                  scenePoint,
                  text: text.isEmpty ? 'New Note' : text,
                  noteColor: chosenColor,
                );
                _board.setTool(BoardTool.select);
                Navigator.of(ctx).pop();
              },
              child: const Text('Add Note'),
            ),
          ],
        ),
      ),
    );
  }

  void _promptTextCreation(BuildContext context, Offset scenePoint) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Text'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter text here...',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _board.addTextAt(scenePoint, controller.text.trim());
                _board.setTool(BoardTool.select);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _promptMapPinCreation(BuildContext context, Offset scenePoint) {
    final controller = TextEditingController(text: 'Location Pin');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Drop Map Pin'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. HQ Office, Meeting Point, Depot',
            labelText: 'Pin Label',
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              _board.addMapPinAt(scenePoint, label: v.trim());
              _board.setTool(BoardTool.select);
            }
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _board.addMapPinAt(scenePoint, label: controller.text.trim());
                _board.setTool(BoardTool.select);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Drop Pin'),
          ),
        ],
      ),
    );
  }

  void _promptErTableCreation(BuildContext context, Offset scenePoint) {
    final nameCtrl = TextEditingController(text: 'new_table');
    final colCtrl = TextEditingController(
      text: 'id:UUID:pk, name:VARCHAR(100), created_at:TIMESTAMP',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.table_chart, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Text('Create Database Table (ERD)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Table Name',
                hintText: 'e.g. users, orders, products',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: colCtrl,
              decoration: const InputDecoration(
                labelText: 'Columns (name:type:pk/fk)',
                helperText: 'Comma separated: col:type:pk, col:type:fk',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final tableName = nameCtrl.text.trim();
              if (tableName.isNotEmpty) {
                final cols = colCtrl.text
                    .split(',')
                    .map((part) {
                      final segs = part.trim().split(':');
                      final colName = segs.isNotEmpty ? segs[0].trim() : 'id';
                      final colType = segs.length > 1
                          ? segs[1].trim()
                          : 'VARCHAR(255)';
                      final tag = segs.length > 2
                          ? segs[2].trim().toLowerCase()
                          : '';
                      return ErColumn(
                        name: colName,
                        type: colType,
                        isPrimaryKey: tag == 'pk',
                        isForeignKey: tag == 'fk',
                      );
                    })
                    .where((c) => c.name.isNotEmpty)
                    .toList();

                _board.addErTableAt(
                  scenePoint,
                  tableName: tableName,
                  columns: cols.isEmpty
                      ? const [
                          ErColumn(
                            name: 'id',
                            type: 'UUID',
                            isPrimaryKey: true,
                          ),
                        ]
                      : cols,
                );
                _board.setTool(BoardTool.select);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Add Table'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vp = ref.watch(viewportProvider);
    final objects = ref.watch(boardProvider.select((s) => s.objects));
    final active = ref.watch(boardProvider.select((s) => s.activeObject));
    final selected = ref.watch(boardProvider.select((s) => s.selectedObject));
    final tool = ref.watch(boardProvider.select((s) => s.tool));
    final boardId = ref.watch(boardProvider.select((s) => s.boardId));
    final isMapMode = ref.watch(boardProvider.select((s) => s.isMapMode));
    final collaborators = ref.watch(remoteCollaboratorsProvider(boardId));

    final visibleObjects = objects.where((obj) {
      return isMapMode
          ? (obj.isMapObject || obj is MapPinObject)
          : (!obj.isMapObject && obj is! MapPinObject);
    }).toList();

    final isSelectedVisible =
        selected != null &&
        (isMapMode
            ? (selected.isMapObject || selected is MapPinObject)
            : (!selected.isMapObject && selected is! MapPinObject));

    final cursor = widget.readOnly || tool == BoardTool.hand
        ? (_mode == _InteractionMode.transform
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.grab)
        : (tool == BoardTool.select
              ? (_mode == _InteractionMode.move
                    ? SystemMouseCursors.move
                    : SystemMouseCursors.basic)
              : SystemMouseCursors.precise);

    return MouseRegion(
      cursor: cursor,
      onHover: (e) {
        final vp = ref.read(viewportProvider);
        final scene = vp.toScene(e.localPosition);
        if (_hoverSceneNotifier.value != scene) {
          _hoverSceneNotifier.value = scene;
        }
        _board.publishPresence(scene);
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onUp,
        onPointerSignal: _onSignal,
        onPointerPanZoomStart: _onPanZoomStart,
        onPointerPanZoomUpdate: _onPanZoomUpdate,
        child: ColoredBox(
          color: Colors.white, // Pure Miro Whiteboard Canvas
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isMapMode)
                GoogleMapTileLayer(
                  pan: vp.pan,
                  scale: vp.scale,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                )
              else
                RepaintBoundary(
                  child: CustomPaint(
                    painter: GridPainter(
                      pan: vp.pan,
                      scale: vp.scale,
                      color: const Color(0xFFCBD5E1)
                          .withValues(alpha: 0.70), // Miro dot grid
                    ),
                  ),
                ),
              // Committed objects layer
              RepaintBoundary(
                child: CustomPaint(
                  painter: BoardObjectsPainter(
                    objects: visibleObjects,
                    pan: vp.pan,
                    scale: vp.scale,
                  ),
                ),
              ),
              // Live active object preview (while drawing or dragging)
              if (active != null &&
                  (isMapMode
                      ? (active.isMapObject || active is MapPinObject)
                      : (!active.isMapObject && active is! MapPinObject)))
                RepaintBoundary(
                  child: CustomPaint(
                    painter: BoardObjectsPainter(
                      objects: [active],
                      pan: vp.pan,
                      scale: vp.scale,
                    ),
                  ),
                ),
              // Selection bounding box & handles
              if (isSelectedVisible && tool == BoardTool.select)
                CustomPaint(
                  painter: SelectionOverlayPainter(
                    selectedObject: selected,
                    pan: vp.pan,
                    scale: vp.scale,
                    accentColor: const Color(0xFF0D54FF), // Miro Blue
                  ),
                ),
              // Live remote collaborators cursors & name badges
              if (collaborators.isNotEmpty)
                CustomPaint(
                  painter: RemoteCursorsPainter(
                    collaborators: collaborators,
                    pan: vp.pan,
                    scale: vp.scale,
                  ),
                ),
              // Geospatial GPS HUD in Map Mode
              if (isMapMode)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: _MapCoordinateHud(
                    hoverNotifier: _hoverSceneNotifier,
                    viewport: vp,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapCoordinateHud extends ConsumerWidget {
  const _MapCoordinateHud({
    required this.hoverNotifier,
    required this.viewport,
  });

  final ValueNotifier<Offset> hoverNotifier;
  final Viewport viewport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeStyle = ref.watch(googleMapStyleProvider);
    final lastEditorLoc = ref.watch(
      boardProvider.select((s) => s.lastEditorLocation),
    );
    final zoomLevel = GoogleMapTileLayer.zoomForScale(viewport.scale);

    return ValueListenableBuilder<Offset>(
      valueListenable: hoverNotifier,
      builder: (context, hoverScene, _) {
        final (lat, lng) = const MercatorProjection().sceneToLatLng(hoverScene);
        final nearest = MapLocationPreset.findNearest(lat, lng);
        final latStr =
            '${lat.abs().toStringAsFixed(4)}° ${lat >= 0 ? "N" : "S"}';
        final lngStr =
            '${lng.abs().toStringAsFixed(4)}° ${lng >= 0 ? "E" : "W"}';

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (lastEditorLoc != null) ...[
              Material(
                color: const Color(0xFF050038).withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(10),
                elevation: 3,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => ref
                      .read(boardProvider.notifier)
                      .centerOnLastEditorLocation(
                        screenSize: MediaQuery.of(context).size,
                      ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.my_location,
                          size: 15,
                          color: Color(0xFF60A5FA),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Last edited: ${lastEditorLoc.locationName} (${lastEditorLoc.editorName}) • Tap to center',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            // Google Maps Layer Style Switcher (Roadmap | Satellite | Hybrid | Terrain)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Google Maps',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A73E8),
                      ),
                    ),
                  ),
                  for (final style in GoogleMapStyle.values)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => ref
                            .read(googleMapStyleProvider.notifier)
                            .setStyle(style),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: activeStyle == style
                                ? const Color(0xFF1A73E8)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                style.icon,
                                size: 13,
                                color: activeStyle == style
                                    ? Colors.white
                                    : const Color(0xFF4B5563),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                style.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: activeStyle == style
                                      ? Colors.white
                                      : const Color(0xFF374151),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Live GPS Coordinates & Nearest Preset
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.explore_outlined,
                    size: 16,
                    color: Color(0xFF0D54FF),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$latStr, $lngStr  (z$zoomLevel)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: Color(0xFF050038),
                    ),
                  ),
                  if (nearest != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '•  ${nearest.name}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
