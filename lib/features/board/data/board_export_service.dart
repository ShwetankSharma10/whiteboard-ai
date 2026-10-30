import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/models/board_object.dart';
import '../presentation/widgets/painters.dart';

/// Access level for board sharing links.
enum ShareAccess {
  readWrite('Full Collaborator (Edit & Draw)'),
  readOnly('Presenter (View Only)');

  const ShareAccess(this.label);
  final String label;
}

/// Service providing multi-format exporting and link sharing for whiteboard boards.
class BoardExportService {
  const BoardExportService();

  /// Computes the union bounding box enclosing all provided board objects.
  Rect computeBoundingBox(List<BoardObject> objects, {double padding = 40.0}) {
    if (objects.isEmpty) {
      return const Rect.fromLTWH(0, 0, 800, 600);
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;

    for (final obj in objects) {
      final b = obj.bounds.inflate(obj.strokeWidth + 4);
      if (b.left < minX) minX = b.left;
      if (b.top < minY) minY = b.top;
      if (b.right > maxX) maxX = b.right;
      if (b.bottom > maxY) maxY = b.bottom;
    }

    final width = math.max(100.0, maxX - minX);
    final height = math.max(100.0, maxY - minY);

    return Rect.fromLTWH(
      minX - padding,
      minY - padding,
      width + (padding * 2),
      height + (padding * 2),
    );
  }

  /// Exports whiteboard objects to a high-resolution raster PNG image.
  ///
  /// [pixelRatio] scales the output resolution (e.g. 2.0 = Retina 2x quality).
  Future<Uint8List> exportToPng(
    List<BoardObject> objects, {
    double pixelRatio = 2.0,
    Color backgroundColor = Colors.white,
    double padding = 40.0,
  }) async {
    final bounds = computeBoundingBox(objects, padding: padding);
    final outWidth = (bounds.width * pixelRatio).round().clamp(100, 8192);
    final outHeight = (bounds.height * pixelRatio).round().clamp(100, 8192);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Fill background
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, outWidth.toDouble(), outHeight.toDouble()),
      bgPaint,
    );

    canvas.save();
    canvas.scale(pixelRatio, pixelRatio);
    // Translate scene origin so bounds.topLeft sits at (0, 0)
    canvas.translate(-bounds.left, -bounds.top);

    for (final obj in objects) {
      BoardObjectsPainter.paintObject(canvas, obj);
    }

    canvas.restore();

    final picture = recorder.endRecording();
    final img = await picture.toImage(outWidth, outHeight);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw StateError('Failed to encode raster canvas into PNG bytes');
    }

    return byteData.buffer.asUint8List();
  }

  /// Exports whiteboard objects to standard standalone SVG vector markup.
  String exportToSvg(
    List<BoardObject> objects, {
    Color backgroundColor = Colors.white,
    double padding = 40.0,
  }) {
    final bounds = computeBoundingBox(objects, padding: padding);
    final w = bounds.width.toStringAsFixed(1);
    final h = bounds.height.toStringAsFixed(1);
    final viewBox =
        '${bounds.left.toStringAsFixed(1)} ${bounds.top.toStringAsFixed(1)} $w $h';

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$viewBox" width="$w" height="$h">',
    );

    // Background rect
    buffer.writeln(
      '  <rect x="${bounds.left}" y="${bounds.top}" width="$w" height="$h" fill="${_colorToHex(backgroundColor)}" />',
    );

    for (final obj in objects) {
      switch (obj) {
        case StrokeObject s:
          _writeStrokeSvg(buffer, s);
        case RectangleObject r:
          _writeRectangleSvg(buffer, r);
        case CircleObject c:
          _writeCircleSvg(buffer, c);
        case LineObject l:
          _writeLineSvg(buffer, l);
        case TextObject t:
          _writeTextSvg(buffer, t);
        case StickyNoteObject n:
          _writeStickyNoteSvg(buffer, n);
        case MapPinObject p:
          _writeMapPinSvg(buffer, p);
        case GeometricShapeObject sh:
          _writeGeometricShapeSvg(buffer, sh);
        case ErTableObject et:
          _writeErTableSvg(buffer, et);
        case ErRelationshipObject er:
          _writeErRelationshipSvg(buffer, er);
      }
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  /// Exports board objects to a formatted JSON backup document.
  String exportToJson(
    List<BoardObject> objects, {
    String boardId = 'board',
    String title = 'Whiteboard Backup',
  }) {
    final data = {
      'boardId': boardId,
      'title': title,
      'exportedAt': DateTime.now().toIso8601String(),
      'version': 1,
      'objectCount': objects.length,
      'objects': objects.map((o) => o.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Imports and parses board objects from a JSON backup string.
  List<BoardObject> importFromJson(String jsonString) {
    final decoded = json.decode(jsonString);
    final List<dynamic> list;
    if (decoded is Map<String, dynamic> && decoded.containsKey('objects')) {
      list = decoded['objects'] as List<dynamic>;
    } else if (decoded is List<dynamic>) {
      list = decoded;
    } else {
      throw const FormatException('Invalid board JSON structure');
    }

    return list
        .map((item) => BoardObject.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Generates a sharable deep-link with access permissions.
  String generateShareLink(
    String boardId, {
    ShareAccess access = ShareAccess.readWrite,
    String domain = 'https://boardmate.ai',
  }) {
    return '$domain/b/$boardId?access=${access.name}';
  }

  // ---- SVG Element Builders ----

  void _writeStrokeSvg(StringBuffer buf, StrokeObject s) {
    if (s.points.isEmpty) return;
    final colorHex = _colorToHex(s.color);
    final opacity = s.color.a.toStringAsFixed(2);

    if (s.points.length == 1) {
      final p = s.points.first;
      buf.writeln(
        '  <circle cx="${p.dx.toStringAsFixed(1)}" cy="${p.dy.toStringAsFixed(1)}" '
        'r="${(s.strokeWidth / 2).toStringAsFixed(1)}" fill="$colorHex" opacity="$opacity" />',
      );
      return;
    }

    final d = StringBuffer(
      'M ${s.points.first.dx.toStringAsFixed(1)} ${s.points.first.dy.toStringAsFixed(1)}',
    );
    for (var i = 1; i < s.points.length; i++) {
      final prev = s.points[i - 1];
      final curr = s.points[i];
      final mid = (prev + curr) / 2;
      d.write(
        ' Q ${prev.dx.toStringAsFixed(1)} ${prev.dy.toStringAsFixed(1)} '
        '${mid.dx.toStringAsFixed(1)} ${mid.dy.toStringAsFixed(1)}',
      );
    }
    d.write(
      ' L ${s.points.last.dx.toStringAsFixed(1)} ${s.points.last.dy.toStringAsFixed(1)}',
    );

    buf.writeln(
      '  <path d="$d" fill="none" stroke="$colorHex" stroke-width="${s.strokeWidth.toStringAsFixed(1)}" '
      'stroke-linecap="round" stroke-linejoin="round" opacity="$opacity" />',
    );
  }

  void _writeRectangleSvg(StringBuffer buf, RectangleObject r) {
    final strokeHex = _colorToHex(r.color);
    final fillHex = r.isFilled && r.fillColor != null
        ? _colorToHex(r.fillColor!)
        : 'none';
    final rx = r.cornerRadius.toStringAsFixed(1);

    buf.writeln(
      '  <rect x="${r.rect.left.toStringAsFixed(1)}" y="${r.rect.top.toStringAsFixed(1)}" '
      'width="${r.rect.width.toStringAsFixed(1)}" height="${r.rect.height.toStringAsFixed(1)}" '
      'rx="$rx" ry="$rx" fill="$fillHex" stroke="$strokeHex" stroke-width="${r.strokeWidth.toStringAsFixed(1)}" />',
    );
  }

  void _writeCircleSvg(StringBuffer buf, CircleObject c) {
    final strokeHex = _colorToHex(c.color);
    final fillHex = c.isFilled && c.fillColor != null
        ? _colorToHex(c.fillColor!)
        : 'none';
    final cx = c.rect.center.dx.toStringAsFixed(1);
    final cy = c.rect.center.dy.toStringAsFixed(1);
    final rx = (c.rect.width / 2).toStringAsFixed(1);
    final ry = (c.rect.height / 2).toStringAsFixed(1);

    buf.writeln(
      '  <ellipse cx="$cx" cy="$cy" rx="$rx" ry="$ry" '
      'fill="$fillHex" stroke="$strokeHex" stroke-width="${c.strokeWidth.toStringAsFixed(1)}" />',
    );
  }

  void _writeLineSvg(StringBuffer buf, LineObject l) {
    final strokeHex = _colorToHex(l.color);
    buf.writeln(
      '  <line x1="${l.start.dx.toStringAsFixed(1)}" y1="${l.start.dy.toStringAsFixed(1)}" '
      'x2="${l.end.dx.toStringAsFixed(1)}" y2="${l.end.dy.toStringAsFixed(1)}" '
      'stroke="$strokeHex" stroke-width="${l.strokeWidth.toStringAsFixed(1)}" stroke-linecap="round" />',
    );

    if (l.isArrow) {
      final angle = math.atan2(l.end.dy - l.start.dy, l.end.dx - l.start.dx);
      final arrowLen = math.max(12.0, l.strokeWidth * 3.5);
      const arrowAngle = 28 * math.pi / 180;

      final p1 =
          l.end -
          Offset(
            arrowLen * math.cos(angle - arrowAngle),
            arrowLen * math.sin(angle - arrowAngle),
          );
      final p2 =
          l.end -
          Offset(
            arrowLen * math.cos(angle + arrowAngle),
            arrowLen * math.sin(angle + arrowAngle),
          );

      buf.writeln(
        '  <polygon points="${l.end.dx.toStringAsFixed(1)},${l.end.dy.toStringAsFixed(1)} '
        '${p1.dx.toStringAsFixed(1)},${p1.dy.toStringAsFixed(1)} '
        '${p2.dx.toStringAsFixed(1)},${p2.dy.toStringAsFixed(1)}" fill="$strokeHex" />',
      );
    }
  }

  void _writeTextSvg(StringBuffer buf, TextObject t) {
    final fillHex = _colorToHex(t.color);
    buf.writeln(
      '  <text x="${t.position.dx.toStringAsFixed(1)}" y="${(t.position.dy + t.fontSize).toStringAsFixed(1)}" '
      'font-family="system-ui, -apple-system, sans-serif" font-size="${t.fontSize.toStringAsFixed(1)}" '
      'fill="$fillHex">${_escapeXml(t.text)}</text>',
    );
  }

  void _writeStickyNoteSvg(StringBuffer buf, StickyNoteObject n) {
    final noteHex = _colorToHex(n.noteColor);
    final textHex = _colorToHex(n.color);
    final lines = n.text.split('\n');

    buf.writeln('  <g>');
    // Drop shadow
    buf.writeln(
      '    <rect x="${(n.rect.left + 4).toStringAsFixed(1)}" y="${(n.rect.top + 4).toStringAsFixed(1)}" '
      'width="${n.rect.width.toStringAsFixed(1)}" height="${n.rect.height.toStringAsFixed(1)}" '
      'rx="8" ry="8" fill="rgba(0,0,0,0.12)" />',
    );
    // Note body
    buf.writeln(
      '    <rect x="${n.rect.left.toStringAsFixed(1)}" y="${n.rect.top.toStringAsFixed(1)}" '
      'width="${n.rect.width.toStringAsFixed(1)}" height="${n.rect.height.toStringAsFixed(1)}" '
      'rx="8" ry="8" fill="$noteHex" stroke="#e0e0e0" stroke-width="1" />',
    );
    // Note text
    buf.writeln(
      '    <text x="${(n.rect.left + 12).toStringAsFixed(1)}" y="${(n.rect.top + 26).toStringAsFixed(1)}" '
      'font-family="system-ui, -apple-system, sans-serif" font-size="${n.fontSize.toStringAsFixed(1)}" fill="$textHex">',
    );
    for (var i = 0; i < lines.length; i++) {
      final dy = i == 0 ? '0' : '1.3em';
      buf.writeln(
        '      <tspan x="${(n.rect.left + 12).toStringAsFixed(1)}" dy="$dy">${_escapeXml(lines[i])}</tspan>',
      );
    }
    buf.writeln('    </text>');
    buf.writeln('  </g>');
  }

  void _writeMapPinSvg(StringBuffer buf, MapPinObject p) {
    final px = p.scenePosition.dx.toStringAsFixed(1);
    final pinHex = _colorToHex(p.color);

    buf.writeln(
      '  <g transform="translate(${(p.scenePosition.dx - 16).toStringAsFixed(1)}, ${(p.scenePosition.dy - 36).toStringAsFixed(1)})">',
    );
    buf.writeln(
      '    <path d="M16 0C7.16 0 0 7.16 0 16c0 12 16 20 16 20s16-8 16-20c0-8.84-7.16-16-16-16z" fill="$pinHex" />',
    );
    buf.writeln('    <circle cx="16" cy="14" r="5" fill="#FFFFFF" />');
    buf.writeln('  </g>');
    buf.writeln(
      '  <text x="$px" y="${(p.scenePosition.dy + 16).toStringAsFixed(1)}" '
      'font-family="system-ui, -apple-system, sans-serif" font-size="12" font-weight="bold" '
      'text-anchor="middle" fill="#212121">${_escapeXml(p.label)}</text>',
    );
  }

  void _writeGeometricShapeSvg(StringBuffer buf, GeometricShapeObject s) {
    final strokeHex = _colorToHex(s.color);
    final fillHex = s.isFilled && s.fillColor != null
        ? _colorToHex(s.fillColor!)
        : '${strokeHex}15'; // 8% opacity fill
    final r = s.rect;

    switch (s.shapeType) {
      case ShapeType.triangle:
        final p =
            '${r.center.dx.toStringAsFixed(1)},${r.top.toStringAsFixed(1)} '
            '${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)} '
            '${r.left.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}';
        buf.writeln(
          '  <polygon points="$p" fill="$fillHex" stroke="$strokeHex" stroke-width="${s.strokeWidth.toStringAsFixed(1)}" />',
        );
      case ShapeType.diamond:
        final p =
            '${r.center.dx.toStringAsFixed(1)},${r.top.toStringAsFixed(1)} '
            '${r.right.toStringAsFixed(1)},${r.center.dy.toStringAsFixed(1)} '
            '${r.center.dx.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)} '
            '${r.left.toStringAsFixed(1)},${r.center.dy.toStringAsFixed(1)}';
        buf.writeln(
          '  <polygon points="$p" fill="$fillHex" stroke="$strokeHex" stroke-width="${s.strokeWidth.toStringAsFixed(1)}" />',
        );
      case ShapeType.star:
        final cx = r.center.dx;
        final cy = r.center.dy;
        final outerR = math.min(r.width, r.height) / 2;
        final innerR = outerR * 0.38;
        final pts = <String>[];
        for (var i = 0; i < 10; i++) {
          final rad = i.isEven ? outerR : innerR;
          final angle = (i * math.pi / 5) - (math.pi / 2);
          final x = cx + rad * math.cos(angle);
          final y = cy + rad * math.sin(angle);
          pts.add('${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}');
        }
        buf.writeln(
          '  <polygon points="${pts.join(' ')}" fill="$fillHex" stroke="$strokeHex" stroke-width="${s.strokeWidth.toStringAsFixed(1)}" />',
        );
      case ShapeType.hexagon:
        final dx = r.width * 0.25;
        final pts = [
          '${(r.left + dx).toStringAsFixed(1)},${r.top.toStringAsFixed(1)}',
          '${(r.right - dx).toStringAsFixed(1)},${r.top.toStringAsFixed(1)}',
          '${r.right.toStringAsFixed(1)},${r.center.dy.toStringAsFixed(1)}',
          '${(r.right - dx).toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}',
          '${(r.left + dx).toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}',
          '${r.left.toStringAsFixed(1)},${r.center.dy.toStringAsFixed(1)}',
        ];
        buf.writeln(
          '  <polygon points="${pts.join(' ')}" fill="$fillHex" stroke="$strokeHex" stroke-width="${s.strokeWidth.toStringAsFixed(1)}" />',
        );
      case ShapeType.parallelogram:
        final off = r.width * 0.22;
        final pts = [
          '${(r.left + off).toStringAsFixed(1)},${r.top.toStringAsFixed(1)}',
          '${r.right.toStringAsFixed(1)},${r.top.toStringAsFixed(1)}',
          '${(r.right - off).toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}',
          '${r.left.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}',
        ];
        buf.writeln(
          '  <polygon points="${pts.join(' ')}" fill="$fillHex" stroke="$strokeHex" stroke-width="${s.strokeWidth.toStringAsFixed(1)}" />',
        );
      case ShapeType.cylinder:
        buf.writeln('  <g>');
        buf.writeln(
          '    <rect x="${r.left.toStringAsFixed(1)}" y="${(r.top + r.height * 0.11).toStringAsFixed(1)}" width="${r.width.toStringAsFixed(1)}" height="${(r.height * 0.78).toStringAsFixed(1)}" fill="$fillHex" stroke="$strokeHex" stroke-width="${s.strokeWidth.toStringAsFixed(1)}" />',
        );
        buf.writeln(
          '    <ellipse cx="${r.center.dx.toStringAsFixed(1)}" cy="${r.top.toStringAsFixed(1)}" rx="${(r.width / 2).toStringAsFixed(1)}" ry="${(r.height * 0.11).toStringAsFixed(1)}" fill="$fillHex" stroke="$strokeHex" stroke-width="${s.strokeWidth.toStringAsFixed(1)}" />',
        );
        buf.writeln(
          '    <ellipse cx="${r.center.dx.toStringAsFixed(1)}" cy="${r.bottom.toStringAsFixed(1)}" rx="${(r.width / 2).toStringAsFixed(1)}" ry="${(r.height * 0.11).toStringAsFixed(1)}" fill="$fillHex" stroke="$strokeHex" stroke-width="${s.strokeWidth.toStringAsFixed(1)}" />',
        );
        buf.writeln('  </g>');
      case ShapeType.cloud:
        buf.writeln(
          '  <rect x="${r.left.toStringAsFixed(1)}" y="${r.top.toStringAsFixed(1)}" width="${r.width.toStringAsFixed(1)}" height="${r.height.toStringAsFixed(1)}" rx="20" fill="$fillHex" stroke="$strokeHex" stroke-width="${s.strokeWidth.toStringAsFixed(1)}" />',
        );
    }

    if (s.label.isNotEmpty) {
      buf.writeln(
        '  <text x="${r.center.dx.toStringAsFixed(1)}" y="${(r.center.dy + 4).toStringAsFixed(1)}" '
        'font-family="system-ui, sans-serif" font-size="12" font-weight="bold" '
        'text-anchor="middle" fill="$strokeHex">${_escapeXml(s.label)}</text>',
      );
    }
  }

  void _writeErTableSvg(StringBuffer buf, ErTableObject t) {
    final b = t.bounds;
    final strokeHex = _colorToHex(t.color);

    buf.writeln('  <g id="er-${t.id}">');
    // Main card
    buf.writeln(
      '    <rect x="${b.left.toStringAsFixed(1)}" y="${b.top.toStringAsFixed(1)}" '
      'width="${b.width.toStringAsFixed(1)}" height="${b.height.toStringAsFixed(1)}" '
      'rx="10" fill="#FFFFFF" stroke="$strokeHex" stroke-width="${t.strokeWidth.toStringAsFixed(1)}" />',
    );
    // Header
    buf.writeln(
      '    <rect x="${b.left.toStringAsFixed(1)}" y="${b.top.toStringAsFixed(1)}" '
      'width="${b.width.toStringAsFixed(1)}" height="38" rx="10" fill="$strokeHex" />',
    );
    buf.writeln(
      '    <text x="${(b.left + 12).toStringAsFixed(1)}" y="${(b.top + 24).toStringAsFixed(1)}" '
      'font-family="system-ui, sans-serif" font-size="13" font-weight="bold" fill="#FFFFFF">'
      '${_escapeXml(t.tableName.toUpperCase())}</text>',
    );

    // Columns
    var y = b.top + 38.0;
    for (final col in t.columns) {
      buf.writeln(
        '    <line x1="${b.left.toStringAsFixed(1)}" y1="${y.toStringAsFixed(1)}" x2="${b.right.toStringAsFixed(1)}" y2="${y.toStringAsFixed(1)}" stroke="#E2E8F0" stroke-width="1" />',
      );
      final textY = (y + 18).toStringAsFixed(1);
      var x = b.left + 12.0;

      if (col.isPrimaryKey) {
        buf.writeln(
          '    <rect x="${x.toStringAsFixed(1)}" y="${(y + 6).toStringAsFixed(1)}" width="24" height="15" rx="3" fill="#F59E0B" />',
        );
        buf.writeln(
          '    <text x="${(x + 12).toStringAsFixed(1)}" y="${(y + 17).toStringAsFixed(1)}" font-family="sans-serif" font-size="9" font-weight="bold" text-anchor="middle" fill="#FFFFFF">PK</text>',
        );
        x += 30;
      } else if (col.isForeignKey) {
        buf.writeln(
          '    <rect x="${x.toStringAsFixed(1)}" y="${(y + 6).toStringAsFixed(1)}" width="24" height="15" rx="3" fill="#0EA5E9" />',
        );
        buf.writeln(
          '    <text x="${(x + 12).toStringAsFixed(1)}" y="${(y + 17).toStringAsFixed(1)}" font-family="sans-serif" font-size="9" font-weight="bold" text-anchor="middle" fill="#FFFFFF">FK</text>',
        );
        x += 30;
      }

      buf.writeln(
        '    <text x="${x.toStringAsFixed(1)}" y="$textY" font-family="sans-serif" font-size="12" fill="#0F172A">${_escapeXml(col.name)}</text>',
      );
      buf.writeln(
        '    <text x="${(b.right - 12).toStringAsFixed(1)}" y="$textY" font-family="monospace" font-size="11" text-anchor="end" fill="#64748B">${_escapeXml(col.type)}</text>',
      );

      y += 28.0;
    }
    buf.writeln('  </g>');
  }

  void _writeErRelationshipSvg(StringBuffer buf, ErRelationshipObject r) {
    final strokeHex = _colorToHex(r.color);
    buf.writeln(
      '  <line x1="${r.start.dx.toStringAsFixed(1)}" y1="${r.start.dy.toStringAsFixed(1)}" x2="${r.end.dx.toStringAsFixed(1)}" y2="${r.end.dy.toStringAsFixed(1)}" stroke="$strokeHex" stroke-width="${r.strokeWidth.toStringAsFixed(1)}" />',
    );

    if (r.label.isNotEmpty || r.cardinality.label.isNotEmpty) {
      final label = r.label.isNotEmpty
          ? '${r.label} (${r.cardinality.label})'
          : r.cardinality.label;
      final mid = (r.start + r.end) / 2;
      buf.writeln(
        '  <rect x="${(mid.dx - 30).toStringAsFixed(1)}" y="${(mid.dy - 10).toStringAsFixed(1)}" width="60" height="20" rx="4" fill="#FFFFFF" stroke="$strokeHex" stroke-width="1" />',
      );
      buf.writeln(
        '  <text x="${mid.dx.toStringAsFixed(1)}" y="${(mid.dy + 4).toStringAsFixed(1)}" font-family="sans-serif" font-size="10" font-weight="bold" text-anchor="middle" fill="#0F172A">${_escapeXml(label)}</text>',
      );
    }
  }

  String _colorToHex(Color c) {
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
