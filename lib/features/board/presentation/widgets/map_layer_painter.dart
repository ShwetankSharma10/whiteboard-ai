import 'package:flutter/material.dart';

import '../../domain/models/map_projection.dart';

/// Renders a vector cartographic basemap in scene space beneath whiteboard strokes.
class MapLayerPainter extends CustomPainter {
  MapLayerPainter({
    required this.pan,
    required this.scale,
    required this.isDark,
    this.worldSize = 4096.0,
  }) : projection = MercatorProjection(worldSize: worldSize);

  final Offset pan;
  final double scale;
  final bool isDark;
  final double worldSize;
  final MercatorProjection projection;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);

    final oceanColor = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFE2E8F0);
    final landColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);
    final landBorderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFCBD5E1);
    final gridLineColor = isDark
        ? const Color(0x1A94A3B8)
        : const Color(0x1E64748B);
    final textCityColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF475569);

    final worldRect = Rect.fromLTWH(0, 0, worldSize, worldSize);

    // 1. Ocean background
    canvas.drawRect(worldRect, Paint()..color = oceanColor);

    // 2. Latitude and Longitude Grid Lines
    final gridPaint = Paint()
      ..color = gridLineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Meridians every 30 degrees (-180 to 180)
    for (var lng = -180.0; lng <= 180.0; lng += 30.0) {
      final top = projection.latLngToScene(80.0, lng);
      final bottom = projection.latLngToScene(-80.0, lng);
      canvas.drawLine(top, bottom, gridPaint);
    }

    // Parallels every 30 degrees (-60 to 60) + Equator
    for (var lat = -60.0; lat <= 60.0; lat += 30.0) {
      final left = projection.latLngToScene(lat, -180.0);
      final right = projection.latLngToScene(lat, 180.0);
      canvas.drawLine(left, right, gridPaint);
    }

    // Equator highlight
    final eqLeft = projection.latLngToScene(0.0, -180.0);
    final eqRight = projection.latLngToScene(0.0, 180.0);
    final equatorPaint = Paint()
      ..color = isDark ? const Color(0x3338BDF8) : const Color(0x330284C7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(eqLeft, eqRight, equatorPaint);

    // 3. Simplified Vector Continents / Major Landmasses
    final landPaint = Paint()
      ..color = landColor
      ..style = PaintingStyle.fill;
    final landBorderPaint = Paint()
      ..color = landBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    _drawLandmasses(canvas, landPaint, landBorderPaint);

    // 4. Reference Cities / Landmarks
    final cityDotPaint = Paint()
      ..color = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)
      ..style = PaintingStyle.fill;

    for (final city in MapLocationPreset.presets) {
      final pos = projection.latLngToScene(city.latitude, city.longitude);

      // Glowing dot
      canvas.drawCircle(pos, 3.5, cityDotPaint);
      canvas.drawCircle(
        pos,
        6.5,
        Paint()
          ..color = (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7))
              .withValues(alpha: 0.25)
          ..style = PaintingStyle.fill,
      );

      // City label
      final textPainter = TextPainter(
        text: TextSpan(
          text: city.name,
          style: TextStyle(
            color: textCityColor,
            fontSize: 9.0,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(pos.dx + 6, pos.dy - 5));
    }

    // World border
    canvas.drawRect(
      worldRect,
      Paint()
        ..color = landBorderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    canvas.restore();
  }

  void _drawLandmasses(Canvas canvas, Paint fill, Paint stroke) {
    // North America
    final naCoords = [
      (65.0, -165.0),
      (70.0, -130.0),
      (60.0, -80.0),
      (50.0, -55.0),
      (40.0, -70.0),
      (25.0, -80.0),
      (20.0, -105.0),
      (30.0, -115.0),
      (50.0, -125.0),
      (60.0, -145.0),
    ];
    _drawPolygon(canvas, naCoords, fill, stroke);

    // South America
    final saCoords = [
      (10.0, -75.0),
      (5.0, -50.0),
      (-10.0, -35.0),
      (-25.0, -45.0),
      (-55.0, -65.0),
      (-50.0, -75.0),
      (-15.0, -75.0),
      (0.0, -80.0),
    ];
    _drawPolygon(canvas, saCoords, fill, stroke);

    // Eurasia (Europe + Asia)
    final eurasiaCoords = [
      (70.0, 10.0),
      (75.0, 60.0),
      (70.0, 130.0),
      (60.0, 170.0),
      (45.0, 140.0),
      (30.0, 120.0),
      (20.0, 110.0),
      (10.0, 105.0),
      (10.0, 80.0),
      (25.0, 60.0),
      (30.0, 35.0),
      (40.0, 25.0),
      (45.0, 0.0),
      (55.0, 5.0),
      (60.0, 25.0),
    ];
    _drawPolygon(canvas, eurasiaCoords, fill, stroke);

    // Africa
    final africaCoords = [
      (35.0, -5.0),
      (35.0, 30.0),
      (10.0, 50.0),
      (-10.0, 40.0),
      (-35.0, 20.0),
      (-30.0, 15.0),
      (5.0, 10.0),
      (15.0, -15.0),
    ];
    _drawPolygon(canvas, africaCoords, fill, stroke);

    // Australia
    final ausCoords = [
      (-15.0, 130.0),
      (-15.0, 145.0),
      (-25.0, 150.0),
      (-38.0, 145.0),
      (-35.0, 115.0),
      (-20.0, 115.0),
    ];
    _drawPolygon(canvas, ausCoords, fill, stroke);
  }

  void _drawPolygon(
    Canvas canvas,
    List<(double, double)> latLngs,
    Paint fill,
    Paint stroke,
  ) {
    if (latLngs.isEmpty) return;
    final path = Path();
    final first = projection.latLngToScene(latLngs[0].$1, latLngs[0].$2);
    path.moveTo(first.dx, first.dy);

    for (var i = 1; i < latLngs.length; i++) {
      final pt = projection.latLngToScene(latLngs[i].$1, latLngs[i].$2);
      path.lineTo(pt.dx, pt.dy);
    }
    path.close();

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(MapLayerPainter old) =>
      old.pan != pan ||
      old.scale != scale ||
      old.isDark != isDark ||
      old.worldSize != worldSize;
}
