import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../domain/models/board_object.dart';
import '../../domain/models/presence.dart';

/// Infinite Miro dot grid drawn in screen space with hardware-accelerated raw points.
class GridPainter extends CustomPainter {
  GridPainter({required this.pan, required this.scale, required this.color});

  final Offset pan;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var spacing = 28.0 * scale;
    while (spacing < 14) {
      spacing *= 2; // thin out dots when zoomed far out
    }
    while (spacing > 56) {
      spacing /= 2;
    }
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0;

    final startX = pan.dx % spacing;
    final startY = pan.dy % spacing;
    final countX = ((size.width - startX) / spacing).ceil() + 1;
    final countY = ((size.height - startY) / spacing).ceil() + 1;
    final totalPoints = countX * countY;
    if (totalPoints <= 0) return;

    final coords = Float32List(totalPoints * 2);
    var idx = 0;
    for (var x = startX; x < size.width; x += spacing) {
      for (var y = startY; y < size.height; y += spacing) {
        if (idx + 1 < coords.length) {
          coords[idx++] = x;
          coords[idx++] = y;
        }
      }
    }
    if (idx > 0) {
      canvas.drawRawPoints(PointMode.points, coords.sublist(0, idx), paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      old.pan != pan || old.scale != scale || old.color != color;
}

/// Paints all whiteboard canvas objects in scene space with frustum culling.
class BoardObjectsPainter extends CustomPainter {
  BoardObjectsPainter({
    required this.objects,
    required this.pan,
    required this.scale,
  });

  final List<BoardObject> objects;
  final Offset pan;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);

    final visible = Rect.fromLTWH(
      -pan.dx / scale,
      -pan.dy / scale,
      size.width / scale,
      size.height / scale,
    );

    for (final obj in objects) {
      if (!obj.bounds.inflate(obj.strokeWidth + 10).overlaps(visible)) {
        continue; // Frustum culling
      }
      paintObject(canvas, obj);
    }

    canvas.restore();
  }

  static void paintObject(Canvas canvas, BoardObject obj) {
    switch (obj) {
      case StrokeObject s:
        _paintStroke(canvas, s);
      case RectangleObject r:
        _paintRectangle(canvas, r);
      case CircleObject c:
        _paintCircle(canvas, c);
      case LineObject l:
        _paintLine(canvas, l);
      case TextObject t:
        _paintText(canvas, t);
      case StickyNoteObject n:
        _paintStickyNote(canvas, n);
      case MapPinObject p:
        _paintMapPin(canvas, p);
      case GeometricShapeObject s:
        _paintGeometricShape(canvas, s);
      case ErTableObject t:
        _paintErTable(canvas, t);
      case ErRelationshipObject r:
        _paintErRelationship(canvas, r);
    }
  }

  static void _paintStroke(Canvas canvas, StrokeObject s) {
    final paint = Paint()
      ..color = s.color
      ..strokeWidth = s.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final pts = s.points;
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      canvas.drawCircle(
        pts.first,
        s.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    // Quadratic Bézier smoothing through segment midpoints
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final prev = pts[i - 1];
      final mid = (prev + pts[i]) / 2;
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(path, paint);
  }

  static void _paintRectangle(Canvas canvas, RectangleObject r) {
    final rrect = RRect.fromRectAndRadius(
      r.rect,
      Radius.circular(r.cornerRadius),
    );

    if (r.isFilled && r.fillColor != null) {
      final fillPaint = Paint()
        ..color = r.fillColor!
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawRRect(rrect, fillPaint);
    }

    final strokePaint = Paint()
      ..color = r.color
      ..strokeWidth = r.strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.drawRRect(rrect, strokePaint);
  }

  static void _paintCircle(Canvas canvas, CircleObject c) {
    if (c.isFilled && c.fillColor != null) {
      final fillPaint = Paint()
        ..color = c.fillColor!
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawOval(c.rect, fillPaint);
    }

    final strokePaint = Paint()
      ..color = c.color
      ..strokeWidth = c.strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.drawOval(c.rect, strokePaint);
  }

  static void _paintLine(Canvas canvas, LineObject l) {
    final paint = Paint()
      ..color = l.color
      ..strokeWidth = l.strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    canvas.drawLine(l.start, l.end, paint);

    if (l.isArrow) {
      _paintArrowHead(canvas, l.start, l.end, l.color, l.strokeWidth);
    }
  }

  static void _paintArrowHead(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double width,
  ) {
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final arrowLength = math.max(14.0, width * 3.5);
    final arrowAngle = math.pi / 6; // 30 degrees

    final p1 = Offset(
      end.dx - arrowLength * math.cos(angle - arrowAngle),
      end.dy - arrowLength * math.sin(angle - arrowAngle),
    );
    final p2 = Offset(
      end.dx - arrowLength * math.cos(angle + arrowAngle),
      end.dy - arrowLength * math.sin(angle + arrowAngle),
    );

    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(path, fillPaint);
  }

  static void _paintText(Canvas canvas, TextObject t) {
    final span = TextSpan(
      text: t.text,
      style: TextStyle(
        color: t.color,
        fontSize: t.fontSize,
        fontWeight: t.isBold ? FontWeight.bold : FontWeight.normal,
        height: 1.3,
      ),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      maxLines: 50,
    )..layout(maxWidth: t.width);

    tp.paint(canvas, t.position);
  }

  static void _paintStickyNote(Canvas canvas, StickyNoteObject n) {
    // Miro soft paper card shadow
    final shadowPaint = Paint()
      ..color = const Color(0x1E000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final rrect = RRect.fromRectAndRadius(n.rect, const Radius.circular(6));
    canvas.drawRRect(rrect.shift(const Offset(0, 4)), shadowPaint);

    // Card background
    final cardPaint = Paint()
      ..color = n.noteColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawRRect(rrect, cardPaint);

    // Subtle paper edge border
    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(rrect, borderPaint);

    // Card Text
    final span = TextSpan(
      text: n.text,
      style: TextStyle(
        color: n.color,
        fontSize: n.fontSize,
        height: 1.35,
        fontWeight: FontWeight.w500,
        fontFamily: 'sans-serif',
      ),
    );
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      maxLines: 25,
    )..layout(maxWidth: n.rect.width - 20);

    tp.paint(canvas, n.rect.topLeft + const Offset(12, 12));
  }

  static void _paintMapPin(Canvas canvas, MapPinObject p) {
    final pos = p.scenePosition;

    // Ground shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(pos.dx, pos.dy + 1), width: 14, height: 5),
      Paint()
        ..color = Colors.black26
        ..isAntiAlias = true,
    );

    // Pin teardrop body
    final pinPath = Path()
      ..moveTo(pos.dx, pos.dy)
      ..cubicTo(
        pos.dx - 14,
        pos.dy - 16,
        pos.dx - 14,
        pos.dy - 32,
        pos.dx,
        pos.dy - 32,
      )
      ..cubicTo(
        pos.dx + 14,
        pos.dy - 32,
        pos.dx + 14,
        pos.dy - 16,
        pos.dx,
        pos.dy,
      )
      ..close();

    // Border & Fill
    canvas.drawPath(
      pinPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      pinPath,
      Paint()
        ..color = p.color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    // Center white dot
    canvas.drawCircle(
      Offset(pos.dx, pos.dy - 22),
      4.0,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    // Label card above pin
    if (p.label.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: p.label,
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const padH = 6.0;
      const padV = 3.0;
      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          pos.dx - (textPainter.width + padH * 2) / 2,
          pos.dy - 52,
          textPainter.width + padH * 2,
          textPainter.height + padV * 2,
        ),
        const Radius.circular(4),
      );

      // Card shadow
      canvas.drawRRect(
        badgeRect.shift(const Offset(1, 1)),
        Paint()
          ..color = Colors.black26
          ..isAntiAlias = true,
      );

      // Card white fill & colored border
      canvas.drawRRect(
        badgeRect,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
      canvas.drawRRect(
        badgeRect,
        Paint()
          ..color = p.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..isAntiAlias = true,
      );

      textPainter.paint(
        canvas,
        Offset(pos.dx - (textPainter.width) / 2, pos.dy - 52 + padV),
      );
    }
  }

  static void _paintGeometricShape(Canvas canvas, GeometricShapeObject s) {
    final rect = s.rect;
    final path = _buildShapePath(s.shapeType, rect);

    if (s.isFilled && s.fillColor != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = s.fillColor!
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
    } else {
      // Default subtle translucent pastel fill
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
    }

    final strokePaint = Paint()
      ..color = s.color
      ..strokeWidth = s.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.drawPath(path, strokePaint);

    // If cylinder, draw top ellipse rim
    if (s.shapeType == ShapeType.cylinder) {
      final rimHeight = rect.height * 0.22;
      canvas.drawOval(
        Rect.fromLTWH(rect.left, rect.top, rect.width, rimHeight),
        strokePaint,
      );
    }

    // Centered label text if provided
    if (s.label.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: s.label,
          style: TextStyle(
            color: s.color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: math.max(20.0, rect.width - 16));
      tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  static Path _buildShapePath(ShapeType type, Rect r) {
    final path = Path();
    switch (type) {
      case ShapeType.triangle:
        path.moveTo(r.center.dx, r.top);
        path.lineTo(r.right, r.bottom);
        path.lineTo(r.left, r.bottom);
        path.close();
      case ShapeType.diamond:
        path.moveTo(r.center.dx, r.top);
        path.lineTo(r.right, r.center.dy);
        path.lineTo(r.center.dx, r.bottom);
        path.lineTo(r.left, r.center.dy);
        path.close();
      case ShapeType.star:
        final cx = r.center.dx;
        final cy = r.center.dy;
        final outerR = math.min(r.width, r.height) / 2;
        final innerR = outerR * 0.38;
        for (var i = 0; i < 10; i++) {
          final rad = i.isEven ? outerR : innerR;
          final angle = (i * math.pi / 5) - (math.pi / 2);
          final x = cx + rad * math.cos(angle);
          final y = cy + rad * math.sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
      case ShapeType.hexagon:
        final dx = r.width * 0.25;
        path.moveTo(r.left + dx, r.top);
        path.lineTo(r.right - dx, r.top);
        path.lineTo(r.right, r.center.dy);
        path.lineTo(r.right - dx, r.bottom);
        path.lineTo(r.left + dx, r.bottom);
        path.lineTo(r.left, r.center.dy);
        path.close();
      case ShapeType.parallelogram:
        final offset = r.width * 0.22;
        path.moveTo(r.left + offset, r.top);
        path.lineTo(r.right, r.top);
        path.lineTo(r.right - offset, r.bottom);
        path.lineTo(r.left, r.bottom);
        path.close();
      case ShapeType.cylinder:
        final rimH = r.height * 0.22;
        path.moveTo(r.left, r.top + rimH / 2);
        path.lineTo(r.left, r.bottom - rimH / 2);
        path.arcTo(
          Rect.fromLTWH(r.left, r.bottom - rimH, r.width, rimH),
          math.pi,
          -math.pi,
          false,
        );
        path.lineTo(r.right, r.top + rimH / 2);
        path.arcTo(
          Rect.fromLTWH(r.left, r.top, r.width, rimH),
          0,
          -math.pi,
          false,
        );
        path.close();
      case ShapeType.cloud:
        final w = r.width;
        final h = r.height;
        path.moveTo(r.left + w * 0.2, r.bottom - h * 0.15);
        path.cubicTo(
          r.left,
          r.bottom - h * 0.15,
          r.left,
          r.center.dy,
          r.left + w * 0.2,
          r.center.dy,
        );
        path.cubicTo(
          r.left + w * 0.15,
          r.top,
          r.center.dx,
          r.top,
          r.center.dx,
          r.top + h * 0.2,
        );
        path.cubicTo(
          r.center.dx + w * 0.15,
          r.top,
          r.right,
          r.top + h * 0.2,
          r.right - w * 0.1,
          r.center.dy + h * 0.1,
        );
        path.cubicTo(
          r.right + w * 0.05,
          r.bottom - h * 0.15,
          r.right - w * 0.2,
          r.bottom - h * 0.15,
          r.right - w * 0.2,
          r.bottom - h * 0.15,
        );
        path.close();
    }
    return path;
  }

  static void _paintErTable(Canvas canvas, ErTableObject t) {
    final bounds = t.bounds;
    final rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(10));

    // Drop shadow
    canvas.drawRRect(
      rrect.shift(const Offset(3, 4)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..isAntiAlias = true,
    );

    // Card background fill
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    // Header bar (accent color)
    final headerRRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        bounds.left,
        bounds.top,
        bounds.width,
        ErTableObject.headerHeight,
      ),
      topLeft: const Radius.circular(10),
      topRight: const Radius.circular(10),
    );
    canvas.drawRRect(
      headerRRect,
      Paint()
        ..color = t.color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    // Table title text (white bold)
    final titlePainter = TextPainter(
      text: TextSpan(
        text: '📊  ${t.tableName.toUpperCase()}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: bounds.width - 24);
    titlePainter.paint(
      canvas,
      Offset(
        bounds.left + 12,
        bounds.top + (ErTableObject.headerHeight - titlePainter.height) / 2,
      ),
    );

    // Column rows
    var currentY = bounds.top + ErTableObject.headerHeight;
    final dividerPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;

    for (var i = 0; i < t.columns.length; i++) {
      final col = t.columns[i];
      // Row separator
      canvas.drawLine(
        Offset(bounds.left, currentY),
        Offset(bounds.right, currentY),
        dividerPaint,
      );

      final rowCenterY = currentY + (ErTableObject.rowHeight / 2);

      // Key Badges [PK] or [FK]
      var textStartX = bounds.left + 12.0;
      if (col.isPrimaryKey) {
        final badgeRRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(textStartX + 12, rowCenterY),
            width: 26,
            height: 16,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(
          badgeRRect,
          Paint()
            ..color = const Color(0xFFF59E0B)
            ..isAntiAlias = true, // Gold Amber
        );
        final pkText = TextPainter(
          text: const TextSpan(
            text: 'PK',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        pkText.paint(
          canvas,
          Offset(
            textStartX + 12 - pkText.width / 2,
            rowCenterY - pkText.height / 2,
          ),
        );
        textStartX += 32.0;
      } else if (col.isForeignKey) {
        final badgeRRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(textStartX + 12, rowCenterY),
            width: 26,
            height: 16,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(
          badgeRRect,
          Paint()
            ..color = const Color(0xFF0EA5E9)
            ..isAntiAlias = true, // Sky Cyan
        );
        final fkText = TextPainter(
          text: const TextSpan(
            text: 'FK',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        fkText.paint(
          canvas,
          Offset(
            textStartX + 12 - fkText.width / 2,
            rowCenterY - fkText.height / 2,
          ),
        );
        textStartX += 32.0;
      }

      // Column name
      final colNamePainter = TextPainter(
        text: TextSpan(
          text: col.name,
          style: TextStyle(
            color: const Color(0xFF0F172A),
            fontSize: 12,
            fontWeight: col.isPrimaryKey ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: bounds.width * 0.5);
      colNamePainter.paint(
        canvas,
        Offset(textStartX, rowCenterY - colNamePainter.height / 2),
      );

      // Column data type (Right-aligned monospace)
      final typePainter = TextPainter(
        text: TextSpan(
          text: col.type,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      typePainter.paint(
        canvas,
        Offset(
          bounds.right - 12 - typePainter.width,
          rowCenterY - typePainter.height / 2,
        ),
      );

      currentY += ErTableObject.rowHeight;
    }

    // Outer card border
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = t.color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = t.strokeWidth
        ..isAntiAlias = true,
    );
  }

  static void _paintErRelationship(Canvas canvas, ErRelationshipObject r) {
    final linePaint = Paint()
      ..color = r.color
      ..strokeWidth = r.strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    canvas.drawLine(r.start, r.end, linePaint);

    final angle = math.atan2(r.end.dy - r.start.dy, r.end.dx - r.start.dx);

    // Draw crow's foot or relationship endpoint at `end`
    if (r.cardinality == ErCardinality.oneToMany ||
        r.cardinality == ErCardinality.manyToMany) {
      _paintCrowsFoot(canvas, r.end, angle + math.pi, r.color, r.strokeWidth);
    } else {
      _paintOneTick(canvas, r.end, angle + math.pi, r.color, r.strokeWidth);
    }

    // Draw crow's foot at `start` if manyToMany
    if (r.cardinality == ErCardinality.manyToMany) {
      _paintCrowsFoot(canvas, r.start, angle, r.color, r.strokeWidth);
    } else {
      // One tick mark on start
      _paintOneTick(canvas, r.start, angle, r.color, r.strokeWidth);
    }

    // Label card in middle of connection
    if (r.label.isNotEmpty || r.cardinality.label.isNotEmpty) {
      final labelText = r.label.isNotEmpty
          ? '${r.label} (${r.cardinality.label})'
          : r.cardinality.label;
      final mid = (r.start + r.end) / 2;
      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final badge = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: mid,
          width: tp.width + 12,
          height: tp.height + 6,
        ),
        const Radius.circular(6),
      );
      canvas.drawRRect(
        badge,
        Paint()
          ..color = Colors.white
          ..isAntiAlias = true,
      );
      canvas.drawRRect(
        badge,
        Paint()
          ..color = r.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..isAntiAlias = true,
      );
      tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
    }
  }

  static void _paintCrowsFoot(
    Canvas canvas,
    Offset pt,
    double angle,
    Color color,
    double width,
  ) {
    const prongLen = 14.0;
    const spread = 0.55;
    final p1 =
        pt +
        Offset(
          prongLen * math.cos(angle - spread),
          prongLen * math.sin(angle - spread),
        );
    final p2 =
        pt +
        Offset(
          prongLen * math.cos(angle + spread),
          prongLen * math.sin(angle + spread),
        );

    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    canvas.drawLine(pt, p1, paint);
    canvas.drawLine(pt, p2, paint);
  }

  static void _paintOneTick(
    Canvas canvas,
    Offset pt,
    double angle,
    Color color,
    double width,
  ) {
    const tickLen = 8.0;
    final perpAngle = angle + math.pi / 2;
    final p1 =
        pt +
        Offset(tickLen * math.cos(perpAngle), tickLen * math.sin(perpAngle));
    final p2 =
        pt -
        Offset(tickLen * math.cos(perpAngle), tickLen * math.sin(perpAngle));

    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(BoardObjectsPainter old) =>
      !identical(old.objects, objects) || old.pan != pan || old.scale != scale;
}

/// Selection bounding box painter with interactive resize corner handles.
class SelectionOverlayPainter extends CustomPainter {
  SelectionOverlayPainter({
    required this.selectedObject,
    required this.pan,
    required this.scale,
    required this.accentColor,
  });

  final BoardObject? selectedObject;
  final Offset pan;
  final double scale;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final obj = selectedObject;
    if (obj == null) return;

    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);

    final b = obj.bounds.inflate(4 / scale);

    // Blue selection frame
    final boxPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale
      ..isAntiAlias = true;
    canvas.drawRect(b, boxPaint);

    // 4 Corner handles
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final handleBorder = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale;

    final handleSize = 8.0 / scale;
    final corners = [b.topLeft, b.topRight, b.bottomLeft, b.bottomRight];

    for (final c in corners) {
      final handleRect = Rect.fromCenter(
        center: c,
        width: handleSize,
        height: handleSize,
      );
      canvas.drawRect(handleRect, handlePaint);
      canvas.drawRect(handleRect, handleBorder);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(SelectionOverlayPainter old) =>
      old.selectedObject != selectedObject ||
      old.pan != pan ||
      old.scale != scale ||
      old.accentColor != accentColor;
}

/// Paints real-time remote collaborator cursors and name badges in screen space.
class RemoteCursorsPainter extends CustomPainter {
  RemoteCursorsPainter({
    required this.collaborators,
    required this.pan,
    required this.scale,
  });

  final List<UserPresence> collaborators;
  final Offset pan;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final col in collaborators) {
      final screenPos = Offset(col.x * scale + pan.dx, col.y * scale + pan.dy);

      // Skip painting cursors far outside visible canvas
      if (screenPos.dx < -50 ||
          screenPos.dx > size.width + 50 ||
          screenPos.dy < -50 ||
          screenPos.dy > size.height + 50) {
        continue;
      }

      final color = col.color;

      // 1. Draw cursor arrow (SVG-style pointer)
      final arrowPath = Path()
        ..moveTo(screenPos.dx, screenPos.dy)
        ..lineTo(screenPos.dx, screenPos.dy + 17)
        ..lineTo(screenPos.dx + 4.5, screenPos.dy + 13)
        ..lineTo(screenPos.dx + 11.5, screenPos.dy + 12.5)
        ..close();

      // White shadow/border
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..isAntiAlias = true;
      canvas.drawPath(arrowPath, borderPaint);

      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawPath(arrowPath, fillPaint);

      // 2. Draw collaborator name badge
      final label = col.userName;
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const badgePadH = 6.0;
      const badgePadV = 3.0;
      final badgeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          screenPos.dx + 10,
          screenPos.dy + 14,
          textPainter.width + badgePadH * 2,
          textPainter.height + badgePadV * 2,
        ),
        const Radius.circular(4),
      );

      // Badge shadow
      canvas.drawRRect(
        badgeRect.shift(const Offset(1, 1)),
        Paint()
          ..color = Colors.black26
          ..isAntiAlias = true,
      );

      // Badge pill
      canvas.drawRRect(badgeRect, fillPaint);

      // Badge text
      textPainter.paint(
        canvas,
        Offset(screenPos.dx + 10 + badgePadH, screenPos.dy + 14 + badgePadV),
      );
    }
  }

  @override
  bool shouldRepaint(RemoteCursorsPainter old) {
    if (old.pan != pan || old.scale != scale) return true;
    if (old.collaborators.length != collaborators.length) return true;
    for (var i = 0; i < collaborators.length; i++) {
      if (collaborators[i] != old.collaborators[i]) return true;
    }
    return false;
  }
}
