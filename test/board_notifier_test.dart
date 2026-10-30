import 'dart:ui';

import 'package:boardmate/features/board/domain/models/board_object.dart';
import 'package:boardmate/features/board/presentation/providers/board_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late BoardNotifier board;

  setUp(() {
    container = ProviderContainer();
    container.listen(boardProvider, (_, _) {});
    board = container.read(boardProvider.notifier);
  });

  tearDown(() => container.dispose());

  BoardState read() => container.read(boardProvider);

  void drawStroke(List<Offset> pts) {
    board.setTool(BoardTool.pen);
    board.startDrawing(pts.first);
    for (final p in pts.skip(1)) {
      board.extendDrawing(p, 0);
    }
    board.endDrawing();
  }

  test('drawing commits a StrokeObject and enables undo', () {
    drawStroke(const [Offset(0, 0), Offset(10, 10), Offset(20, 20)]);
    expect(read().objects, hasLength(1));
    expect(read().objects.first, isA<StrokeObject>());
    final stroke = read().objects.first as StrokeObject;
    expect(stroke.points, hasLength(3));
    expect(read().canUndo, isTrue);
    expect(read().activeObject, isNull);
  });

  test('creating a RectangleObject commits with correct bounds', () {
    board.setTool(BoardTool.rectangle);
    board.startDrawing(const Offset(50, 50));
    board.extendDrawing(const Offset(150, 120), 0);
    board.endDrawing();

    expect(read().objects, hasLength(1));
    expect(read().objects.first, isA<RectangleObject>());
    final rect = read().objects.first as RectangleObject;
    expect(rect.rect, const Rect.fromLTWH(50, 50, 100, 70));
    expect(read().selectedObjectId, rect.id);
  });

  test('creating a CircleObject commits with correct bounds', () {
    board.setTool(BoardTool.circle);
    board.startDrawing(const Offset(100, 100));
    board.extendDrawing(const Offset(200, 200), 0);
    board.endDrawing();

    expect(read().objects, hasLength(1));
    expect(read().objects.first, isA<CircleObject>());
    final circle = read().objects.first as CircleObject;
    expect(circle.rect, const Rect.fromLTWH(100, 100, 100, 100));
  });

  test('creating an Arrow LineObject sets isArrow to true', () {
    board.setTool(BoardTool.arrow);
    board.startDrawing(const Offset(10, 10));
    board.extendDrawing(const Offset(100, 10), 0);
    board.endDrawing();

    expect(read().objects, hasLength(1));
    expect(read().objects.first, isA<LineObject>());
    final line = read().objects.first as LineObject;
    expect(line.isArrow, isTrue);
    expect(line.start, const Offset(10, 10));
    expect(line.end, const Offset(100, 10));
  });

  test('creating Text and StickyNote objects', () {
    board.addTextAt(const Offset(20, 30), 'Hello BoardMate');
    board.addStickyNoteAt(const Offset(200, 200), text: 'Task item 1');

    expect(read().objects, hasLength(2));
    expect(read().objects[0], isA<TextObject>());
    expect(read().objects[1], isA<StickyNoteObject>());

    final textObj = read().objects[0] as TextObject;
    expect(textObj.text, 'Hello BoardMate');

    final note = read().objects[1] as StickyNoteObject;
    expect(note.text, 'Task item 1');
    expect(note.rect.width, 180);
  });

  test('selecting and moving an object updates position', () {
    board.addStickyNoteAt(const Offset(100, 100), text: 'Movable Note');
    final noteId = read().objects.first.id;

    board.selectAt(const Offset(150, 150));
    expect(read().selectedObjectId, noteId);

    board.moveSelected(const Offset(50, 20));
    final updatedNote = read().objects.first as StickyNoteObject;
    expect(updatedNote.rect.left, 150);
    expect(updatedNote.rect.top, 120);
  });

  test('duplicating selected object creates a new offset copy', () {
    board.setTool(BoardTool.rectangle);
    board.startDrawing(const Offset(10, 10));
    board.extendDrawing(const Offset(50, 50), 0);
    board.endDrawing();

    board.duplicateSelected();
    expect(read().objects, hasLength(2));
    expect(read().objects[1].id, isNot(equals(read().objects[0].id)));
    expect(read().objects[1].bounds.left, 40); // 10 + 30 delta
  });

  test('deleteSelected removes object and clears selection', () {
    board.addTextAt(const Offset(10, 10), 'To delete');
    expect(read().objects, hasLength(1));

    board.deleteSelected();
    expect(read().objects, isEmpty);
    expect(read().selectedObjectId, isNull);
  });

  test('undo / redo round-trip across different objects', () {
    drawStroke(const [Offset(0, 0), Offset(1, 1)]);
    board.addStickyNoteAt(const Offset(100, 100));
    expect(read().objects, hasLength(2));

    board.undo();
    expect(read().objects, hasLength(1));
    expect(read().objects.first, isA<StrokeObject>());

    board.redo();
    expect(read().objects, hasLength(2));
    expect(read().objects.last, isA<StickyNoteObject>());
  });

  test('erase drag removes hit objects as a single undo step', () {
    drawStroke(const [Offset(0, 0), Offset(10, 0)]);
    board.setTool(BoardTool.rectangle);
    board.startDrawing(const Offset(100, 100));
    board.extendDrawing(const Offset(150, 150), 0);
    board.endDrawing();

    expect(read().objects, hasLength(2));

    board.beginErase();
    board.eraseAt(const Offset(5, 0), 10);
    board.eraseAt(const Offset(120, 120), 10);

    expect(read().objects, isEmpty);

    board.undo();
    expect(read().objects, hasLength(2));
  });

  test(
    'JSON serialization & deserialization round-trip for all object types',
    () {
      final originalObjects = <BoardObject>[
        StrokeObject(
          id: 's1',
          points: const [Offset(1, 2), Offset(3, 4)],
          color: const Color(0xFFEF4444),
          strokeWidth: 3,
          isHighlighter: false,
        ),
        const RectangleObject(
          id: 'r1',
          rect: Rect.fromLTWH(10, 20, 100, 80),
          color: Color(0xFF3B82F6),
          strokeWidth: 2,
          isFilled: true,
          fillColor: Color(0xFFDBEAFE),
        ),
        const CircleObject(
          id: 'c1',
          rect: Rect.fromLTWH(50, 50, 60, 60),
          color: Color(0xFF10B981),
          strokeWidth: 2.5,
        ),
        LineObject(
          id: 'l1',
          start: const Offset(0, 0),
          end: const Offset(100, 100),
          color: const Color(0xFF1F2937),
          strokeWidth: 2,
          isArrow: true,
        ),
        const TextObject(
          id: 't1',
          position: Offset(40, 40),
          text: 'Architecture Diagram',
          color: Color(0xFF1F2937),
          fontSize: 16,
          isBold: true,
        ),
        const StickyNoteObject(
          id: 'n1',
          rect: Rect.fromLTWH(200, 200, 150, 120),
          text: 'Important task',
          color: Color(0xFF1F2937),
          noteColor: Color(0xFFFEF3C7),
        ),
      ];

      for (final obj in originalObjects) {
        final json = obj.toJson();
        final restored = BoardObject.fromJson(json);

        expect(restored.id, obj.id);
        expect(restored.color.toARGB32(), obj.color.toARGB32());
        expect(restored.strokeWidth, obj.strokeWidth);
        expect(restored.bounds, obj.bounds);
        expect(restored.runtimeType, obj.runtimeType);
      }
    },
  );

  test('viewport zoomAt keeps focal point fixed in scene coordinates', () {
    container.listen(viewportProvider, (_, _) {});
    final vp = container.read(viewportProvider.notifier);
    const focal = Offset(200, 100);
    final before = container.read(viewportProvider).toScene(focal);
    vp.zoomAt(focal, 2);
    final after = container.read(viewportProvider).toScene(focal);
    expect((before - after).distance, lessThan(1e-9));
    expect(container.read(viewportProvider).scale, 2);
  });
}
