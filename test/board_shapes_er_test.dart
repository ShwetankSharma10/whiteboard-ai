import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boardmate/features/board/data/board_export_service.dart';
import 'package:boardmate/features/board/domain/models/board_object.dart';
import 'package:boardmate/features/board/domain/models/map_projection.dart';
import 'package:boardmate/features/board/presentation/providers/board_provider.dart';

void main() {
  group('Geometric Shapes Model & Serialization', () {
    test(
      'GeometricShapeObject supports all 7 shape types and translates properly',
      () {
        final shapes = [
          ShapeType.triangle,
          ShapeType.diamond,
          ShapeType.star,
          ShapeType.hexagon,
          ShapeType.parallelogram,
          ShapeType.cylinder,
          ShapeType.cloud,
        ];

        for (final type in shapes) {
          final shape = GeometricShapeObject(
            id: 'shape_${type.name}',
            shapeType: type,
            rect: const Rect.fromLTWH(100, 100, 120, 80),
            color: Colors.blue,
            strokeWidth: 3.0,
            label: 'Test ${type.name}',
          );

          expect(shape.bounds, const Rect.fromLTWH(100, 100, 120, 80));
          expect(shape.hitTest(const Offset(150, 140)), isTrue);
          expect(shape.hitTest(const Offset(10, 10)), isFalse);

          final translated = shape.translate(const Offset(20, -10));
          expect(translated.rect, const Rect.fromLTWH(120, 90, 120, 80));

          final resized = shape.resize(const Rect.fromLTWH(50, 50, 200, 150));
          expect(resized.rect, const Rect.fromLTWH(50, 50, 200, 150));

          // JSON roundtrip
          final json = shape.toJson();
          expect(json['type'], 'shape');
          expect(json['shape'], type.name);

          final deserialized =
              BoardObject.fromJson(json) as GeometricShapeObject;
          expect(deserialized.id, shape.id);
          expect(deserialized.shapeType, type);
          expect(deserialized.label, shape.label);
          expect(deserialized.rect, shape.rect);
        }
      },
    );
  });

  group('ER Diagram Models & Serialization', () {
    test(
      'ErTableObject calculates height from columns and roundtrips JSON',
      () {
        final table = ErTableObject(
          id: 'tbl-users',
          position: const Offset(200, 150),
          tableName: 'users',
          columns: const [
            ErColumn(name: 'id', type: 'UUID', isPrimaryKey: true),
            ErColumn(name: 'email', type: 'VARCHAR(255)'),
            ErColumn(name: 'role_id', type: 'UUID', isForeignKey: true),
            ErColumn(name: 'bio', type: 'TEXT', isNullable: true),
          ],
          color: const Color(0xFF2563EB),
        );

        expect(table.tableName, 'users');
        expect(table.columns.length, 4);
        expect(table.columns.first.isPrimaryKey, isTrue);
        expect(table.columns[2].isForeignKey, isTrue);
        expect(table.height, greaterThan(ErTableObject.headerHeight));
        expect(table.bounds.topLeft, const Offset(200, 150));

        final json = table.toJson();
        expect(json['type'], 'er_table');
        expect(json['table'], 'users');

        final deserialized = BoardObject.fromJson(json) as ErTableObject;
        expect(deserialized.id, table.id);
        expect(deserialized.tableName, 'users');
        expect(deserialized.columns.length, 4);
        expect(deserialized.columns[0].name, 'id');
        expect(deserialized.columns[0].isPrimaryKey, isTrue);
      },
    );

    test(
      'ErRelationshipObject supports crow foot cardinality and roundtrips JSON',
      () {
        final rel = ErRelationshipObject(
          id: 'rel-users-orders',
          start: const Offset(100, 100),
          end: const Offset(300, 100),
          color: Colors.green,
          cardinality: ErCardinality.oneToMany,
          fromTableId: 'tbl-users',
          toTableId: 'tbl-orders',
          label: 'places',
        );

        expect(rel.cardinality, ErCardinality.oneToMany);
        expect(rel.hitTest(const Offset(200, 100)), isTrue);

        final json = rel.toJson();
        expect(json['type'], 'er_relationship');
        expect(json['cardinality'], 'oneToMany');
        expect(json['label'], 'places');

        final deserialized = BoardObject.fromJson(json) as ErRelationshipObject;
        expect(deserialized.id, rel.id);
        expect(deserialized.cardinality, ErCardinality.oneToMany);
        expect(deserialized.fromTableId, 'tbl-users');
        expect(deserialized.toTableId, 'tbl-orders');
        expect(deserialized.label, 'places');
      },
    );
  });

  group('BoardNotifier Shapes and ER Integration', () {
    test('addGeometricShapeAt and template insertion work properly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(boardProvider.notifier);

      // Add a Diamond shape
      notifier.addGeometricShapeAt(
        const Offset(100, 100),
        ShapeType.diamond,
        label: 'Is Active?',
      );

      var state = container.read(boardProvider);
      expect(state.objects.length, 1);
      final shape = state.objects.first as GeometricShapeObject;
      expect(shape.shapeType, ShapeType.diamond);
      expect(shape.label, 'Is Active?');

      // Add an ER Table
      notifier.addErTableAt(
        const Offset(300, 100),
        tableName: 'customers',
        columns: const [
          ErColumn(name: 'id', type: 'UUID', isPrimaryKey: true),
          ErColumn(name: 'name', type: 'VARCHAR(100)'),
        ],
      );

      state = container.read(boardProvider);
      expect(state.objects.length, 2);
      expect(state.objects.last, isA<ErTableObject>());

      // Insert E-Commerce Template
      notifier.insertErTemplate('E-Commerce Schema');
      state = container.read(boardProvider);
      // 2 previous + 4 tables + 3 relationships = 9
      expect(state.objects.length, 9);
      expect(state.objects.whereType<ErTableObject>().length, 5);
      expect(state.objects.whereType<ErRelationshipObject>().length, 3);

      // Insert Microservices Flow Template
      notifier.insertErTemplate('Microservices Flow');
      state = container.read(boardProvider);
      expect(
        state.objects.any(
          (o) => o is GeometricShapeObject && o.label == 'API Gateway',
        ),
        isTrue,
      );
    });

    test(
      'duplicateSelected, setColor, and updateText work on new object types',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(boardProvider.notifier);

        // Add a star shape
        notifier.addGeometricShapeAt(
          const Offset(50, 50),
          ShapeType.star,
          label: 'Milestone 1',
        );

        // Duplicate it
        notifier.duplicateSelected();
        var state = container.read(boardProvider);
        expect(state.objects.length, 2);

        // Update text
        final lastId = state.objects.last.id;
        notifier.updateText(lastId, 'Milestone 2 (Updated)');
        state = container.read(boardProvider);
        final updatedShape = state.objects.firstWhere(
          (o) => o.id == lastId,
        ) as GeometricShapeObject;
        expect(updatedShape.label, 'Milestone 2 (Updated)');

        // Set color
        notifier.setColor(Colors.amber);
        state = container.read(boardProvider);
        final coloredShape = state.objects.firstWhere((o) => o.id == lastId);
        expect(coloredShape.color, Colors.amber);
      },
    );
  });

  group('Location Search & Presets Directory', () {
    test(
      'MapLocationPreset contains 50+ presets and search filters correctly',
      () {
        expect(MapLocationPreset.presets.length, greaterThanOrEqualTo(50));

        final techHubs = MapLocationPreset.search('Silicon');
        expect(techHubs.isNotEmpty, isTrue);

        final tokyo = MapLocationPreset.search('Tokyo');
        expect(tokyo.isNotEmpty, isTrue);
        expect(tokyo.first.country, 'Japan');

        final awsRegions = MapLocationPreset.search('AWS');
        expect(awsRegions.length, greaterThanOrEqualTo(4));

        final nearest = MapLocationPreset.findNearest(37.77, -122.41);
        expect(nearest?.name, contains('San Francisco'));
      },
    );
  });

  group('SVG Export of Shapes and ER Diagrams', () {
    test(
      'BoardExportService exports geometric shapes and ER tables to SVG',
      () {
        const exporter = BoardExportService();

        final objects = <BoardObject>[
          GeometricShapeObject(
            id: 'shape-hex',
            shapeType: ShapeType.hexagon,
            rect: const Rect.fromLTWH(50, 50, 100, 80),
            color: Colors.blue,
            label: 'Service Hex',
          ),
          ErTableObject(
            id: 'table-orders',
            position: const Offset(200, 50),
            tableName: 'orders',
            columns: const [
              ErColumn(name: 'id', type: 'UUID', isPrimaryKey: true),
              ErColumn(name: 'amount', type: 'DECIMAL(10,2)'),
            ],
            color: Colors.teal,
          ),
          ErRelationshipObject(
            id: 'rel-1',
            start: const Offset(150, 90),
            end: const Offset(200, 90),
            color: Colors.black,
            cardinality: ErCardinality.oneToMany,
            label: '1..N',
          ),
        ];

        final svg = exporter.exportToSvg(objects);
        expect(svg, contains('<svg'));
        expect(svg, contains('Service Hex'));
        expect(svg, contains('orders'));
        expect(svg, contains('>PK<'));
        expect(svg, contains('DECIMAL(10,2)'));
        expect(svg, contains('1..N'));
        expect(svg, contains('</svg>'));
      },
    );
  });
}
