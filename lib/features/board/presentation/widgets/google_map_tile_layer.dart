import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/board_provider.dart';
import 'map_layer_painter.dart';

/// Optional Google Maps API key passed via `--dart-define=GOOGLE_MAPS_API_KEY=...`
const kGoogleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

/// Supported Google Maps visual layer types.
enum GoogleMapStyle {
  roadmap('Roadmap', 'm', Icons.map_outlined),
  satellite('Satellite', 's', Icons.satellite_alt_outlined),
  hybrid('Hybrid', 'y', Icons.layers_outlined),
  terrain('Terrain', 'p', Icons.terrain_outlined);

  const GoogleMapStyle(this.label, this.lyrsCode, this.icon);

  final String label;

  /// Google Maps tile server `lyrs` parameter (`m`, `s`, `y`, `p`).
  final String lyrsCode;
  final IconData icon;
}

/// Holds the currently selected Google Maps style when Map Mode is active.
class GoogleMapStyleNotifier extends Notifier<GoogleMapStyle> {
  @override
  GoogleMapStyle build() => GoogleMapStyle.roadmap;

  void setStyle(GoogleMapStyle style) => state = style;
}

final googleMapStyleProvider =
    NotifierProvider<GoogleMapStyleNotifier, GoogleMapStyle>(
      GoogleMapStyleNotifier.new,
    );

/// Renders real Google Maps Web Mercator (EPSG:3857) tiles synchronized 1:1
/// with the whiteboard's [pan] and [scale] (where `worldSize = 4096.0`).
///
/// Sits directly beneath the whiteboard strokes, shapes, sticky notes, and
/// geo-anchored [MapPinObject] markers so every canvas element stays locked
/// to its exact latitude/longitude while panning and zooming.
class GoogleMapTileLayer extends ConsumerWidget {
  const GoogleMapTileLayer({
    super.key,
    required this.pan,
    required this.scale,
    required this.isDark,
    this.worldSize = 4096.0,
  });

  final Offset pan;
  final double scale;
  final bool isDark;
  final double worldSize;

  /// Builds the Google Maps tile URL for `(z, x, y)` and [style].
  static String tileUrlFor({
    required int z,
    required int x,
    required int y,
    required GoogleMapStyle style,
    String apiKey = kGoogleMapsApiKey,
  }) {
    final server = (x + y) & 3; // mt0 .. mt3 load balancing
    final keyParam = apiKey.trim().isNotEmpty ? '&key=${apiKey.trim()}' : '';
    return 'https://mt$server.google.com/vt/lyrs=${style.lyrsCode}'
        '&hl=en&x=$x&y=$y&z=$z&scale=2$keyParam';
  }

  /// Computes the optimal Web Mercator tile zoom level `z` for [scale].
  static int zoomForScale(double scale, {double worldSize = 4096.0}) {
    // At z, total world width in pixels (at 256px/tile) is 256 * 2^z.
    // On screen, world width is worldSize * scale.
    final rawZ = (math.log((worldSize * scale) / 256.0) / math.ln2).round();
    return rawZ.clamp(1, 14);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(googleMapStyleProvider);
    final lastEditorLoc = ref.watch(
      boardProvider.select((s) => s.lastEditorLocation),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1280.0;
        final viewportHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 800.0;

        final z = zoomForScale(scale, worldSize: worldSize);
        final n = 1 << z; // 2^z tiles per axis
        final tileSceneSize = worldSize / n;
        final tileScreenSize = tileSceneSize * scale;

        // Visible scene bounds
        final minSceneX = -pan.dx / scale;
        final minSceneY = -pan.dy / scale;
        final maxSceneX = (viewportWidth - pan.dx) / scale;
        final maxSceneY = (viewportHeight - pan.dy) / scale;

        final minTileX = (minSceneX / tileSceneSize).floor().clamp(0, n - 1);
        final maxTileX = (maxSceneX / tileSceneSize).floor().clamp(0, n - 1);
        final minTileY = (minSceneY / tileSceneSize).floor().clamp(0, n - 1);
        final maxTileY = (maxSceneY / tileSceneSize).floor().clamp(0, n - 1);

        final tiles = <Widget>[];

        // Cap maximum concurrent tiles in case of extreme viewport dimensions
        const maxTiles = 64;
        var count = 0;

        for (var ty = minTileY; ty <= maxTileY; ty++) {
          for (var tx = minTileX; tx <= maxTileX; tx++) {
            if (count >= maxTiles) break;
            count++;

            final left = tx * tileScreenSize + pan.dx;
            final top = ty * tileScreenSize + pan.dy;
            final url = tileUrlFor(z: z, x: tx, y: ty, style: style);

            tiles.add(
              Positioned(
                key: ValueKey('gmap_${style.lyrsCode}_${z}_${tx}_$ty'),
                left: left,
                top: top,
                // +0.5px overlap prevents hairlines between tiles during pan/zoom
                width: tileScreenSize + 0.5,
                height: tileScreenSize + 0.5,
                child: Image.network(
                  url,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            );
          }
        }

        final editorScreenPos = lastEditorLoc != null
            ? (lastEditorLoc.scenePosition * scale + pan)
            : null;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Vector fallback base map painted immediately while Google tiles stream
              CustomPaint(
                painter: MapLayerPainter(
                  pan: pan,
                  scale: scale,
                  isDark: isDark,
                ),
              ),
              ...tiles,
              if (lastEditorLoc != null && editorScreenPos != null)
                Positioned(
                  left: editorScreenPos.dx - 16,
                  top: editorScreenPos.dy - 40,
                  child: IgnorePointer(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A73E8),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x401A73E8),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person_pin_circle,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF050038)
                                .withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x26000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Last edited by ${lastEditorLoc.editorName}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                lastEditorLoc.locationName,
                                style: const TextStyle(
                                  color: Color(0xFF93C5FD),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
