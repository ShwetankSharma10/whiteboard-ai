import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:boardmate/features/board/data/board_storage_service.dart';
import 'package:boardmate/features/board/data/gemini_ai_service.dart';
import 'package:boardmate/features/board/domain/models/board_object.dart';
import 'package:boardmate/features/board/presentation/providers/board_provider.dart';

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

  group('Stage S6: GeminiAIService Core Capabilities', () {
    const aiService = GeminiAIService();

    test(
      'generateMindmap produces root node, child nodes, and connector arrows',
      () async {
        final objects = await aiService.generateMindmap(
          'Cloud Microservices Architecture',
          origin: const Offset(500, 500),
        );

        expect(objects.isNotEmpty, isTrue);

        // Should have at least 1 root rectangle, 1 root text, multiple child nodes, and connector arrows
        final rects = objects.whereType<RectangleObject>().toList();
        final texts = objects.whereType<TextObject>().toList();
        final arrows = objects
            .whereType<LineObject>()
            .where((l) => l.isArrow)
            .toList();

        expect(rects.length, greaterThanOrEqualTo(4));
        expect(texts.length, greaterThanOrEqualTo(4));
        expect(arrows.length, greaterThanOrEqualTo(3));

        // Root text contains topic
        final rootText = texts.firstWhere(
          (t) => t.text.contains('Cloud Microservices'),
        );
        expect(rootText, isNotNull);
      },
    );

    test('recognizeRoughShape detects a rough straight line and creates an arrow LineObject', () {
      final lineStroke = StrokeObject(
        id: 'stroke-line-1',
        points: const [
          Offset(10, 10),
          Offset(50, 12),
          Offset(100, 11),
          Offset(150, 10),
          Offset(200, 9),
        ],
        color: Colors.blue,
        strokeWidth: 3,
      );

      final recognized = aiService.recognizeRoughShape(lineStroke);
      expect(recognized, isA<LineObject>());
      final line = recognized as LineObject;
      expect(line.isArrow, isTrue);
      expect(line.start, const Offset(10, 10));
      expect(line.end, const Offset(200, 9));
    });

    test('recognizeRoughShape detects a rough square/circle and converts to CircleObject', () {
      // Simulate drawing a closed circle
      final pts = <Offset>[];
      const radius = 50.0;
      const center = Offset(100, 100);
      for (var i = 0; i <= 20; i++) {
        final angle = i * 2 * math.pi / 20;
        pts.add(
          Offset(
            center.dx + radius * math.cos(angle),
            center.dy + radius * math.sin(angle),
          ),
        );
      }

      final circleStroke = StrokeObject(
        id: 'stroke-circle-1',
        points: pts,
        color: Colors.green,
        strokeWidth: 2,
      );

      final recognized = aiService.recognizeRoughShape(circleStroke);
      expect(recognized, isA<CircleObject>());
    });

    test('recognizeRoughShape detects a rough rectangle and converts to RectangleObject', () {
      // 200 x 50 rectangle (aspect ratio = 4.0, clearly not circular)
      final pts = const [
        Offset(0, 0),
        Offset(200, 0),
        Offset(200, 50),
        Offset(0, 50),
        Offset(0, 0), // Closed loop
      ];

      final rectStroke = StrokeObject(
        id: 'stroke-rect-1',
        points: pts,
        color: Colors.purple,
        strokeWidth: 2,
      );

      final recognized = aiService.recognizeRoughShape(rectStroke);
      expect(recognized, isA<RectangleObject>());
      final rect = recognized as RectangleObject;
      expect(rect.rect.width, closeTo(200, 5));
      expect(rect.rect.height, closeTo(50, 5));
    });

    test('generateBoardSummary compiles text and notes into a structured StickyNoteObject', () {
      final objects = <BoardObject>[
        StickyNoteObject(
          id: 'n1',
          rect: const Rect.fromLTWH(0, 0, 100, 100),
          text: 'Ship Beta release on Friday',
          color: Colors.black,
        ),
        TextObject(
          id: 't1',
          position: const Offset(10, 10),
          text: 'Security audit completed',
          color: Colors.black,
        ),
        RectangleObject(
          id: 'r1',
          rect: const Rect.fromLTWH(0, 0, 100, 100),
          color: Colors.blue,
          strokeWidth: 2,
        ),
      ];

      final summary = aiService.generateBoardSummary(objects);
      expect(summary, isA<StickyNoteObject>());
      expect(summary.text, contains('📋 AI Board Summary'));
      expect(summary.text, contains('Ship Beta release'));
      expect(summary.text, contains('Total Elements: 3'));
    });
  });

  group('Gemini REST integration (mocked HTTP)', () {
    String wrap(Map<String, dynamic> inner) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(inner)},
            ],
          },
        },
      ],
    });

    test('mindmap is built from Gemini JSON branches and children', () async {
      late http.Request captured;
      final service = GeminiAIService(
        apiKey: 'test-key',
        client: MockClient((req) async {
          captured = req;
          return http.Response(
            wrap({
              'branches': [
                {
                  'title': 'Frontend',
                  'children': ['Flutter', 'Web'],
                },
                {'title': 'Backend', 'children': <String>[]},
                {
                  'title': 'Data',
                  'children': ['RTDB'],
                },
              ],
            }),
            200,
          );
        }),
      );

      final result = await service.generateMindmapSmart('App Stack');
      expect(result.usedGemini, isTrue);
      expect(captured.headers['x-goog-api-key'], 'test-key');
      expect(captured.url.path, contains(':generateContent'));
      final labels = result.value.whereType<TextObject>().map((t) => t.text);
      expect(labels, containsAll(['App Stack', 'Frontend', 'Flutter', 'RTDB']));
    });

    test(
      'invalid key falls back to offline content with clear message',
      () async {
        final service = GeminiAIService(
          apiKey: 'bad',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': {
                  'message': 'API key not valid. Please pass a valid API key.',
                },
              }),
              400,
            ),
          ),
        );
        final result = await service.generateMindmapSmart('Roadmap');
        expect(result.usedGemini, isFalse);
        expect(result.message, contains('Invalid Gemini API key'));
        expect(result.value, isNotEmpty);
      },
    );

    test('summary uses Gemini summary and action items', () async {
      final service = GeminiAIService(
        apiKey: 'k',
        client: MockClient(
          (_) async => http.Response(
            wrap({
              'summary': 'Team plans beta launch.',
              'actionItems': ['Fix login bug', 'Write release notes'],
            }),
            200,
          ),
        ),
      );
      final result = await service.generateBoardSummarySmart([
        TextObject(
          id: 't',
          position: Offset.zero,
          text: 'Beta launch Friday',
          color: Colors.black,
        ),
      ]);
      expect(result.usedGemini, isTrue);
      expect(result.value.text, contains('Team plans beta launch.'));
      expect(result.value.text, contains('☐ Fix login bug'));
    });
  });

  group('Stage S6: BoardNotifier Gemini AI Integration', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          boardStorageServiceProvider.overrideWithValue(
            InMemoryBoardStorageService(),
          ),
        ],
      );
      container.listen(boardProvider, (_, _) {});
    });

    tearDown(() => container.dispose());

    test(
      'generateMindmapFromPrompt adds mindmap nodes to canvas and enables undo',
      () async {
        final notifier = container.read(boardProvider.notifier);

        await notifier.generateMindmapFromPrompt('Product Strategy 2026');

        final state = container.read(boardProvider);
        expect(state.objects.length, greaterThanOrEqualTo(5));
        expect(state.canUndo, isTrue);
      },
    );

    test('cleanSelectedStrokeWithAI replaces rough hand-drawn stroke with clean shape', () {
      final notifier = container.read(boardProvider.notifier);

      // Draw rough line
      notifier.setTool(BoardTool.pen);
      notifier.startDrawing(const Offset(20, 20));
      notifier.extendDrawing(const Offset(100, 22), 0);
      notifier.extendDrawing(const Offset(200, 21), 0);
      notifier.extendDrawing(const Offset(300, 20), 0);
      notifier.extendDrawing(const Offset(400, 19), 0);
      notifier.endDrawing();

      final strokeId = container.read(boardProvider).objects.first.id;
      notifier.selectById(strokeId);

      notifier.cleanSelectedStrokeWithAI();

      final updatedObjects = container.read(boardProvider).objects;
      expect(updatedObjects.first, isA<LineObject>());
      final line = updatedObjects.first as LineObject;
      expect(line.isArrow, isTrue);
    });

    test('cleanSelectedStrokeWithAI reports when nothing is selected', () {
      final notifier = container.read(boardProvider.notifier);
      final msg = notifier.cleanSelectedStrokeWithAI();
      expect(msg, contains('Select a hand-drawn'));
    });

    test('offline service reports it is not configured', () async {
      const offline = GeminiAIService();
      expect(offline.isConfigured, isFalse);
      final result = await offline.generateMindmapSmart('Launch Plan');
      expect(result.usedGemini, isFalse);
      // Root node + 5 "launch" template branches.
      expect(result.value.whereType<RectangleObject>().length, 6);
    });

    test('generateBoardSummaryWithAI places AI summary card on board and switches tool to select', () async {
      final notifier = container.read(boardProvider.notifier);
      notifier.addTextAt(const Offset(50, 50), 'Implement offline persistence');

      await notifier.generateBoardSummaryWithAI();

      final state = container.read(boardProvider);
      final summaryNote = state.objects.firstWhere(
        (o) => o is StickyNoteObject && o.text.contains('AI Board Summary'),
      );
      expect(summaryNote, isNotNull);
      expect(state.tool, BoardTool.select);
      expect(state.selectedObjectId, summaryNote.id);
    });

    test('generateMindmapFromPrompt assigns shared groupId and moving selected node moves entire mindmap', () async {
      final notifier = container.read(boardProvider.notifier);
      await notifier.generateMindmapFromPrompt('Autonomous Agents');

      final state = container.read(boardProvider);
      expect(state.tool, BoardTool.select);
      expect(state.selectedObjectId, isNotNull);

      final selected = state.selectedObject;
      expect(selected, isNotNull);
      expect(selected!.groupId, isNotNull);

      final mindmapObjects = state.objects
          .where((o) => o.groupId == selected.groupId)
          .toList();
      expect(mindmapObjects.length, greaterThanOrEqualTo(5));

      final initialBounds = {for (final o in mindmapObjects) o.id: o.bounds};

      const delta = Offset(100, 50);
      notifier.moveSelected(delta);
      notifier.commitMove();

      final movedState = container.read(boardProvider);
      for (final o in movedState.objects) {
        if (o.groupId == selected.groupId) {
          final oldBound = initialBounds[o.id]!;
          expect(o.bounds.left, closeTo(oldBound.left + delta.dx, 0.01));
          expect(o.bounds.top, closeTo(oldBound.top + delta.dy, 0.01));
        }
      }
    });
  });
}
