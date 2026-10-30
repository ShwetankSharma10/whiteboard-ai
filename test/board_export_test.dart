import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boardmate/features/board/data/board_export_service.dart';
import 'package:boardmate/features/board/data/board_storage_service.dart';
import 'package:boardmate/features/board/data/board_sync_repository.dart';
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

  late BoardExportService exportService;

  setUp(() {
    exportService = const BoardExportService();
  });

  group('Stage S8: BoardExportService Vector SVG Generation', () {
    test('exportToSvg produces standard SVG header and viewBox', () {
      final objects = <BoardObject>[
        StrokeObject(
          id: 'stroke-1',
          points: const [Offset(10, 10), Offset(50, 50)],
          color: const Color(0xFF1E88E5),
          strokeWidth: 4,
          isHighlighter: false,
        ),
      ];

      final svg = exportService.exportToSvg(objects);

      expect(svg, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(svg, contains('<svg xmlns="http://www.w3.org/2000/svg"'));
      expect(svg, contains('viewBox='));
      expect(svg, contains('</svg>'));
      expect(svg, contains('<path'));
      expect(svg, contains('stroke="#1e88e5"'));
    });

    test(
      'exportToSvg renders RectangleObject with rounded corners and fill',
      () {
        final objects = <BoardObject>[
          RectangleObject(
            id: 'rect-1',
            rect: const Rect.fromLTWH(100, 100, 200, 150),
            color: const Color(0xFFE53935),
            strokeWidth: 3,
            isFilled: true,
            fillColor: const Color(0xFFFFEBEE),
            cornerRadius: 12,
          ),
        ];

        final svg = exportService.exportToSvg(objects);

        expect(svg, contains('<rect'));
        expect(svg, contains('x="100.0"'));
        expect(svg, contains('y="100.0"'));
        expect(svg, contains('width="200.0"'));
        expect(svg, contains('height="150.0"'));
        expect(svg, contains('rx="12.0"'));
        expect(svg, contains('fill="#ffebee"'));
        expect(svg, contains('stroke="#e53935"'));
      },
    );

    test('exportToSvg renders CircleObject as SVG ellipse', () {
      final objects = <BoardObject>[
        CircleObject(
          id: 'circle-1',
          rect: const Rect.fromLTWH(50, 50, 100, 100),
          color: const Color(0xFF43A047),
          strokeWidth: 2,
          isFilled: false,
        ),
      ];

      final svg = exportService.exportToSvg(objects);

      expect(svg, contains('<ellipse'));
      expect(svg, contains('cx="100.0"'));
      expect(svg, contains('cy="100.0"'));
      expect(svg, contains('rx="50.0"'));
      expect(svg, contains('ry="50.0"'));
      expect(svg, contains('stroke="#43a047"'));
    });

    test('exportToSvg renders LineObject with arrow polygon head', () {
      final objects = <BoardObject>[
        LineObject(
          id: 'arrow-1',
          start: const Offset(20, 20),
          end: const Offset(120, 120),
          color: const Color(0xFF8E24AA),
          strokeWidth: 4,
          isArrow: true,
        ),
      ];

      final svg = exportService.exportToSvg(objects);

      expect(svg, contains('<line'));
      expect(svg, contains('x1="20.0" y1="20.0" x2="120.0" y2="120.0"'));
      expect(svg, contains('<polygon points="120.0,120.0'));
      expect(svg, contains('fill="#8e24aa"'));
    });

    test('exportToSvg escapes XML special characters in TextObject and StickyNoteObject', () {
      final objects = <BoardObject>[
        TextObject(
          id: 'text-1',
          position: const Offset(30, 40),
          text: 'Architecture <Auth & Sync> "Fast"',
          color: const Color(0xFF212121),
          fontSize: 18,
        ),
        StickyNoteObject(
          id: 'note-1',
          rect: const Rect.fromLTWH(200, 200, 160, 120),
          text: 'Notes & Tasks\nLine 2 <Pending>',
          color: const Color(0xFFFEF3C7),
          noteColor: const Color(0xFFFEF3C7),
        ),
      ];

      final svg = exportService.exportToSvg(objects);

      // Verify XML character escaping
      expect(
        svg,
        contains('Architecture &lt;Auth &amp; Sync&gt; &quot;Fast&quot;'),
      );
      expect(svg, contains('Notes &amp; Tasks'));
      expect(svg, contains('Line 2 &lt;Pending&gt;'));
      expect(svg, contains('<tspan'));
    });

    test('exportToSvg renders MapPinObject with teardrop pin and label', () {
      final objects = <BoardObject>[
        MapPinObject(
          id: 'pin-1',
          latitude: 48.8566,
          longitude: 2.3522,
          label: 'Paris Office',
          description: 'Central HQ',
          color: const Color(0xFFE53935),
        ),
      ];

      final svg = exportService.exportToSvg(objects);

      expect(
        svg,
        contains(
          '<path d="M16 0C7.16 0 0 7.16 0 16c0 12 16 20 16 20s16-8 16-20c0-8.84-7.16-16-16-16z"',
        ),
      );
      expect(svg, contains('Paris Office'));
    });
  });

  group('Stage S8: BoardExportService PNG Raster Canvas Export', () {
    test(
      'exportToPng generates valid PNG byte stream with correct magic header',
      () async {
        final objects = <BoardObject>[
          RectangleObject(
            id: 'rect-1',
            rect: const Rect.fromLTWH(20, 20, 100, 60),
            color: const Color(0xFF000000),
            strokeWidth: 2,
          ),
        ];

        final pngBytes = await exportService.exportToPng(
          objects,
          pixelRatio: 1.0,
        );

        expect(pngBytes, isNotEmpty);
        // PNG Magic Header: 0x89 0x50 0x4E 0x47 (‰PNG)
        expect(pngBytes[0], 0x89);
        expect(pngBytes[1], 0x50);
        expect(pngBytes[2], 0x4E);
        expect(pngBytes[3], 0x47);
      },
    );

    test('exportToPng handles empty board gracefully', () async {
      final pngBytes = await exportService.exportToPng([]);
      expect(pngBytes, isNotEmpty);
      expect(pngBytes[0], 0x89);
    });
  });

  group('Stage S8: JSON Backup & Share Link Generation', () {
    test(
      'exportToJson and importFromJson round-trip preserves all objects',
      () {
        final original = <BoardObject>[
          StrokeObject(
            id: 's1',
            points: const [Offset(0, 0), Offset(10, 10)],
            color: const Color(0xFF000000),
            strokeWidth: 2,
            isHighlighter: false,
          ),
          StickyNoteObject(
            id: 'n1',
            rect: const Rect.fromLTWH(50, 50, 150, 120),
            text: 'Backup Test Note',
            color: const Color(0xFFFEF3C7),
            noteColor: const Color(0xFFFEF3C7),
          ),
        ];

        final jsonStr = exportService.exportToJson(
          original,
          boardId: 'test-board',
          title: 'Sprint Planning',
        );

        final decoded = json.decode(jsonStr) as Map<String, dynamic>;
        expect(decoded['boardId'], 'test-board');
        expect(decoded['title'], 'Sprint Planning');
        expect(decoded['objectCount'], 2);

        final restored = exportService.importFromJson(jsonStr);
        expect(restored.length, 2);
        expect(restored.first, isA<StrokeObject>());
        expect(restored.last, isA<StickyNoteObject>());
        expect((restored.last as StickyNoteObject).text, 'Backup Test Note');
      },
    );

    test('generateShareLink constructs proper deep-link with permissions', () {
      final editorLink = exportService.generateShareLink(
        'board-xyz',
        access: ShareAccess.readWrite,
      );
      final viewerLink = exportService.generateShareLink(
        'board-xyz',
        access: ShareAccess.readOnly,
      );

      expect(editorLink, 'https://boardmate.ai/b/board-xyz?access=readWrite');
      expect(viewerLink, 'https://boardmate.ai/b/board-xyz?access=readOnly');
    });
  });

  group('Stage S8: Riverpod Integration with BoardNotifier', () {
    test('exportSvg, exportJson, importJson, and getShareLink work via BoardNotifier', () {
      final container = ProviderContainer(
        overrides: [
          boardStorageServiceProvider.overrideWithValue(
            InMemoryBoardStorageService(),
          ),
          boardSyncRepositoryProvider.overrideWithValue(
            BroadcastBoardSyncRepository.instance,
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(boardProvider.notifier);
      notifier.initBoard('demo');

      // Add a note
      notifier.addStickyNoteAt(const Offset(100, 100), text: 'Shared Idea');

      // Verify SVG export
      final svg = notifier.exportSvg();
      expect(svg, contains('<svg'));
      expect(svg, contains('Shared Idea'));

      // Verify Share Link
      final link = notifier.getShareLink(access: ShareAccess.readOnly);
      expect(link, contains('/b/demo?access=readOnly'));

      // Verify JSON export and import
      final jsonBackup = notifier.exportJson(title: 'Exported Demo');
      expect(jsonBackup, contains('Shared Idea'));

      // Import an extra note
      final extraJson = json.encode({
        'objects': [
          StickyNoteObject(
            id: 'imported-note',
            rect: const Rect.fromLTWH(300, 300, 150, 120),
            text: 'Imported Idea',
            color: const Color(0xFFFEF3C7),
            noteColor: const Color(0xFFFEF3C7),
          ).toJson(),
        ],
      });

      notifier.importJson(extraJson);

      final state = container.read(boardProvider);
      expect(state.objects.length, 2);
      expect(state.objects.any((o) => o.id == 'imported-note'), isTrue);
    });
  });
}
