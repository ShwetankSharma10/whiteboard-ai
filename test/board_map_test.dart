import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boardmate/features/board/data/board_storage_service.dart';
import 'package:boardmate/features/board/domain/models/board_object.dart';
import 'package:boardmate/features/board/domain/models/map_projection.dart';
import 'package:boardmate/features/board/presentation/providers/board_provider.dart';
import 'package:boardmate/features/board/presentation/widgets/google_map_tile_layer.dart';

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

  group('Stage S5: Web Mercator Projection & Geodesic Math', () {
    const projection = MercatorProjection(worldSize: 4096.0);

    test('Equator and Prime Meridian (0, 0) map to world center', () {
      final sceneCenter = projection.latLngToScene(0.0, 0.0);
      expect(sceneCenter.dx, closeTo(2048.0, 0.01));
      expect(sceneCenter.dy, closeTo(2048.0, 0.01));

      final (lat, lng) = projection.sceneToLatLng(sceneCenter);
      expect(lat, closeTo(0.0, 0.001));
      expect(lng, closeTo(0.0, 0.001));
    });

    test('Antimeridian (-180 and 180) map to x=0 and x=4096', () {
      final left = projection.latLngToScene(0.0, -180.0);
      final right = projection.latLngToScene(0.0, 180.0);

      expect(left.dx, closeTo(0.0, 0.01));
      expect(right.dx, closeTo(4096.0, 0.01));
    });

    test('Round-trip coordinate conversion preserves lat/lng accuracy', () {
      for (final city in MapLocationPreset.presets) {
        final scenePos = projection.latLngToScene(
          city.latitude,
          city.longitude,
        );
        final (lat, lng) = projection.sceneToLatLng(scenePos);

        expect(lat, closeTo(city.latitude, 0.001));
        expect(lng, closeTo(city.longitude, 0.001));
      }
    });

    test('Haversine distance calculation is accurate (London to Paris)', () {
      // London: (51.5074, -0.1278), Paris: (48.8566, 2.3522)
      final distance = MercatorProjection.distanceBetweenKm(
        51.5074,
        -0.1278,
        48.8566,
        2.3522,
      );
      // Distance is ~343 km
      expect(distance, inInclusiveRange(340.0, 350.0));
    });
  });

  group('Stage S5: MapPinObject Model & Serialization', () {
    test('MapPinObject JSON serialization and deserialization round-trip', () {
      final pin = MapPinObject(
        id: 'pin-hq',
        latitude: 37.7749,
        longitude: -122.4194,
        label: 'San Francisco HQ',
        description: 'Main collaborative innovation hub',
        color: const Color(0xFFEF4444),
        category: 'destination',
      );

      final json = pin.toJson();
      expect(json['type'], 'map_pin');
      expect(json['lat'], closeTo(37.7749, 0.0001));
      expect(json['lng'], closeTo(-122.4194, 0.0001));
      expect(json['label'], 'San Francisco HQ');

      final roundTrip = BoardObject.fromJson(json) as MapPinObject;
      expect(roundTrip.id, pin.id);
      expect(roundTrip.latitude, closeTo(pin.latitude, 0.0001));
      expect(roundTrip.longitude, closeTo(pin.longitude, 0.0001));
      expect(roundTrip.label, pin.label);
      expect(roundTrip.description, pin.description);
      expect(roundTrip.color, pin.color);
    });

    test(
      'Translating a MapPinObject updates its GPS coordinates dynamically',
      () {
        final pin = MapPinObject(
          id: 'pin-move',
          latitude: 0.0,
          longitude: 0.0,
          label: 'Equator Center',
          color: Colors.blue,
        );

        final initialScene = pin.scenePosition;
        expect(initialScene.dx, closeTo(2048.0, 0.1));

        // Translate 100 units east and 50 units north
        final moved = pin.translate(const Offset(100, -50));
        expect(moved.scenePosition.dx, closeTo(initialScene.dx + 100, 0.1));
        expect(moved.scenePosition.dy, closeTo(initialScene.dy - 50, 0.1));

        // Longitude should have shifted east (> 0)
        expect(moved.longitude, greaterThan(0.0));
        // Latitude should have shifted north (> 0)
        expect(moved.latitude, greaterThan(0.0));
      },
    );

    test('MapPinObject hitTest detects touch on pin bounds', () {
      final pin = MapPinObject(
        id: 'pin-hit',
        latitude: 40.7128,
        longitude: -74.0060,
        label: 'New York City',
        color: Colors.red,
      );

      final pos = pin.scenePosition;
      // Anchor hit
      expect(pin.hitTest(pos), isTrue);
      // Head hit
      expect(pin.hitTest(Offset(pos.dx, pos.dy - 20)), isTrue);
      // Far point miss
      expect(pin.hitTest(Offset(pos.dx + 200, pos.dy + 200)), isFalse);
    });
  });

  group('Stage S5: BoardNotifier Map Mode Integration', () {
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

    test('toggleMapMode switches map whiteboard mode', () {
      final notifier = container.read(boardProvider.notifier);
      expect(container.read(boardProvider).isMapMode, isFalse);

      notifier.toggleMapMode();
      expect(container.read(boardProvider).isMapMode, isTrue);

      notifier.toggleMapMode();
      expect(container.read(boardProvider).isMapMode, isFalse);
    });

    test('addMapPinAt drops a geo-anchored pin into objects list', () {
      final notifier = container.read(boardProvider.notifier);

      notifier.addMapPinAt(
        const Offset(2048, 2048),
        label: 'Null Island',
        description: 'Where Prime Meridian meets Equator',
      );

      final objects = container.read(boardProvider).objects;
      expect(objects.length, 1);
      expect(objects.first, isA<MapPinObject>());

      final pin = objects.first as MapPinObject;
      expect(pin.label, 'Null Island');
      expect(pin.latitude, closeTo(0.0, 0.01));
      expect(pin.longitude, closeTo(0.0, 0.01));
    });

    test('panToLocation centers viewport camera on city preset', () {
      final notifier = container.read(boardProvider.notifier);
      final tokyo = MapLocationPreset.presets.firstWhere(
        (p) => p.name == 'Tokyo',
      );

      notifier.panToLocation(tokyo, screenSize: const Size(1000, 800));

      final vp = container.read(viewportProvider);
      final tokyoScene = const MercatorProjection().latLngToScene(
        tokyo.latitude,
        tokyo.longitude,
      );

      // In centerOn: pan = screenSize/2 - scene * scale
      final expectedPan = const Offset(500, 400) - tokyoScene * vp.scale;
      expect(vp.pan.dx, closeTo(expectedPan.dx, 0.1));
      expect(vp.pan.dy, closeTo(expectedPan.dy, 0.1));
    });

    test('GoogleMapTileLayer computes Web Mercator tile zoom and URLs', () {
      expect(GoogleMapTileLayer.zoomForScale(1.0), 4);
      expect(GoogleMapTileLayer.zoomForScale(2.0), 5);

      final url = GoogleMapTileLayer.tileUrlFor(
        z: 4,
        x: 8,
        y: 5,
        style: GoogleMapStyle.hybrid,
      );
      expect(url, contains('google.com/vt/lyrs=y'));
      expect(url, contains('x=8&y=5&z=4'));

      expect(container.read(googleMapStyleProvider), GoogleMapStyle.roadmap);
      container
          .read(googleMapStyleProvider.notifier)
          .setStyle(GoogleMapStyle.satellite);
      expect(container.read(googleMapStyleProvider), GoogleMapStyle.satellite);
    });

    test('editing board records lastEditorLocation and toggleMapMode centers on it', () {
      final notifier = container.read(boardProvider.notifier);
      notifier.setEditorLocation(
        latitude: 18.5204,
        longitude: 73.8567,
        locationName: 'Pune, India',
      );
      notifier.addStickyNoteAt(
        const Offset(200, 200),
        text: 'Sprint planning note',
      );

      final loc = container.read(boardProvider).lastEditorLocation;
      expect(loc, isNotNull);
      expect(loc!.locationName, 'Pune, India');
      expect(loc.latitude, closeTo(18.5204, 0.001));
      expect(loc.longitude, closeTo(73.8567, 0.001));

      notifier.toggleMapMode(screenSize: const Size(1000, 800));
      final vp = container.read(viewportProvider);
      final expectedPan = const Offset(500, 400) - loc.scenePosition * vp.scale;
      expect(vp.pan.dx, closeTo(expectedPan.dx, 0.1));
      expect(vp.pan.dy, closeTo(expectedPan.dy, 0.1));
    });

    test(
      'Whiteboard objects and Map objects are segregated and do not overlap',
      () {
        final notifier = container.read(boardProvider.notifier);

        // Create whiteboard objects
        notifier.addStickyNoteAt(
          const Offset(100, 100),
          text: 'Whiteboard Note',
        );
        notifier.addTextAt(const Offset(300, 100), 'Whiteboard Diagram Text');

        final whiteboardNote = container
            .read(boardProvider)
            .objects
            .firstWhere((o) => o is StickyNoteObject);
        expect(whiteboardNote.isMapObject, isFalse);

        // Switch to Map Mode
        notifier.toggleMapMode();
        expect(container.read(boardProvider).isMapMode, isTrue);
        expect(container.read(boardProvider).selectedObjectId, isNull);

        // Whiteboard note cannot be selected while in Map Mode
        notifier.selectAt(const Offset(110, 110));
        expect(container.read(boardProvider).selectedObjectId, isNull);

        // Erasing at whiteboard note position in Map Mode preserves whiteboard note
        notifier.eraseAt(const Offset(110, 110), 30.0);
        expect(
          container
              .read(boardProvider)
              .objects
              .any((o) => o.id == whiteboardNote.id),
          isTrue,
        );

        // Add a map pin in Map Mode
        notifier.addMapPinAt(const Offset(500, 500), label: 'Map Location Pin');
        final mapPin = container
            .read(boardProvider)
            .objects
            .firstWhere((o) => o is MapPinObject);
        expect(mapPin.isMapObject, isTrue);

        // Can select map pin in Map Mode
        notifier.selectAt(const Offset(500, 485));
        expect(container.read(boardProvider).selectedObjectId, mapPin.id);

        // Switch back to Whiteboard Mode
        notifier.toggleMapMode();
        expect(container.read(boardProvider).isMapMode, isFalse);
        expect(container.read(boardProvider).selectedObjectId, isNull);

        // Can now select whiteboard note again
        notifier.selectAt(const Offset(110, 110));
        expect(
          container.read(boardProvider).selectedObjectId,
          whiteboardNote.id,
        );

        // Cannot select map pin in Whiteboard Mode
        notifier.selectAt(const Offset(500, 485));
        expect(container.read(boardProvider).selectedObjectId, isNull);
      },
    );
  });
}
