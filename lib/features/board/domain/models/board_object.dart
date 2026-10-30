import 'dart:ui';

import 'package:flutter/material.dart';

import 'map_projection.dart';

/// Available tools on the whiteboard.
enum BoardTool {
  select,
  pen,
  highlighter,
  eraser,
  rectangle,
  circle,
  triangle,
  diamond,
  star,
  hexagon,
  parallelogram,
  cylinder,
  cloud,
  line,
  arrow,
  text,
  stickyNote,
  erTable,
  erRelationship,
  mapPin,
  hand,
}

/// Abstract base class for all elements rendered on the whiteboard canvas.
sealed class BoardObject {
  const BoardObject({
    required this.id,
    required this.color,
    required this.strokeWidth,
    this.zIndex = 0,
    this.isMapObject = false,
    this.groupId,
  });

  final String id;
  final Color color;
  final double strokeWidth;
  final double zIndex;
  final bool isMapObject;
  final String? groupId;

  /// Bounding rectangle in scene coordinates used for spatial culling and hit testing.
  Rect get bounds;

  /// Tests if a scene-coordinate point hits this object within a given tolerance.
  bool hitTest(Offset point, {double padding = 8.0});

  /// Translates the object by a scene delta offset.
  BoardObject translate(Offset delta);

  /// Resizes the object into new bounding coordinates.
  BoardObject resize(Rect newBounds);

  /// Serializes the object to JSON matching the flattened RTDB schema.
  Map<String, dynamic> toJson();

  /// Deserializes a BoardObject from JSON.
  static BoardObject fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'stroke';
    switch (type) {
      case 'stroke':
        return StrokeObject.fromJson(json);
      case 'rectangle':
        return RectangleObject.fromJson(json);
      case 'circle':
        return CircleObject.fromJson(json);
      case 'shape':
        return GeometricShapeObject.fromJson(json);
      case 'line':
        return LineObject.fromJson(json);
      case 'text':
        return TextObject.fromJson(json);
      case 'sticky_note':
        return StickyNoteObject.fromJson(json);
      case 'er_table':
        return ErTableObject.fromJson(json);
      case 'er_relationship':
        return ErRelationshipObject.fromJson(json);
      case 'map_pin':
        return MapPinObject.fromJson(json);
      default:
        throw ArgumentError('Unknown BoardObject type: $type');
    }
  }
}

// ---------------------------------------------------------------------------
// 1. StrokeObject (Freehand pen & highlighter)
// ---------------------------------------------------------------------------

class StrokeObject extends BoardObject {
  StrokeObject({
    required super.id,
    required this.points,
    required super.color,
    required super.strokeWidth,
    this.isHighlighter = false,
    super.zIndex,
    super.isMapObject = false,
    super.groupId,
  });

  final List<Offset> points;
  final bool isHighlighter;

  @override
  late final Rect bounds = _computeBounds();

  Rect _computeBounds() {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx, maxX = minX;
    var minY = points.first.dy, maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @override
  bool hitTest(Offset point, {double padding = 8.0}) {
    if (!bounds.inflate(strokeWidth / 2 + padding).contains(point)) {
      return false;
    }
    final r = strokeWidth / 2 + padding;
    return points.any((p) => (p - point).distance <= r);
  }

  @override
  StrokeObject translate(Offset delta) => StrokeObject(
    id: id,
    points: points.map((p) => p + delta).toList(),
    color: color,
    strokeWidth: strokeWidth,
    isHighlighter: isHighlighter,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  @override
  StrokeObject resize(Rect newBounds) {
    if (bounds.width == 0 || bounds.height == 0) return this;
    final scaleX = newBounds.width / bounds.width;
    final scaleY = newBounds.height / bounds.height;
    return StrokeObject(
      id: id,
      points: points
          .map(
            (p) => Offset(
              newBounds.left + (p.dx - bounds.left) * scaleX,
              newBounds.top + (p.dy - bounds.top) * scaleY,
            ),
          )
          .toList(),
      color: color,
      strokeWidth: strokeWidth,
      isHighlighter: isHighlighter,
      zIndex: zIndex,
      isMapObject: isMapObject,
      groupId: groupId,
    );
  }

  StrokeObject copyWith({
    String? id,
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
    bool? isHighlighter,
    double? zIndex,
    bool? isMapObject,
    String? groupId,
  }) => StrokeObject(
    id: id ?? this.id,
    points: points ?? this.points,
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    isHighlighter: isHighlighter ?? this.isHighlighter,
    zIndex: zIndex ?? this.zIndex,
    isMapObject: isMapObject ?? this.isMapObject,
    groupId: groupId ?? this.groupId,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'stroke',
    'id': id,
    'color': color.toARGB32(),
    'width': strokeWidth,
    'hl': isHighlighter,
    'zIndex': zIndex,
    if (isMapObject) 'isMap': true,
    if (groupId != null) 'groupId': groupId,
    'pts': [
      for (final p in points) ...[p.dx, p.dy],
    ],
  };

  factory StrokeObject.fromJson(Map<String, dynamic> json) {
    final raw = (json['pts'] as List).cast<num>();
    return StrokeObject(
      id: json['id'] as String,
      color: Color(json['color'] as int),
      strokeWidth: (json['width'] as num).toDouble(),
      isHighlighter: json['hl'] as bool? ?? false,
      zIndex: (json['zIndex'] as num?)?.toDouble() ?? 0,
      isMapObject: json['isMap'] as bool? ?? false,
      groupId: json['groupId'] as String?,
      points: [
        for (var i = 0; i + 1 < raw.length; i += 2)
          Offset(raw[i].toDouble(), raw[i + 1].toDouble()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2. RectangleObject
// ---------------------------------------------------------------------------

class RectangleObject extends BoardObject {
  const RectangleObject({
    required super.id,
    required this.rect,
    required super.color,
    required super.strokeWidth,
    this.isFilled = false,
    this.fillColor,
    this.cornerRadius = 8.0,
    super.zIndex,
    super.isMapObject = false,
    super.groupId,
  });

  final Rect rect;
  final bool isFilled;
  final Color? fillColor;
  final double cornerRadius;

  @override
  Rect get bounds => rect;

  @override
  bool hitTest(Offset point, {double padding = 8.0}) =>
      rect.inflate(strokeWidth / 2 + padding).contains(point);

  @override
  RectangleObject translate(Offset delta) => RectangleObject(
    id: id,
    rect: rect.shift(delta),
    color: color,
    strokeWidth: strokeWidth,
    isFilled: isFilled,
    fillColor: fillColor,
    cornerRadius: cornerRadius,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  @override
  RectangleObject resize(Rect newBounds) => RectangleObject(
    id: id,
    rect: newBounds,
    color: color,
    strokeWidth: strokeWidth,
    isFilled: isFilled,
    fillColor: fillColor,
    cornerRadius: cornerRadius,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  RectangleObject copyWith({
    String? id,
    Rect? rect,
    Color? color,
    double? strokeWidth,
    bool? isFilled,
    Color? fillColor,
    double? cornerRadius,
    double? zIndex,
    bool? isMapObject,
    String? groupId,
  }) => RectangleObject(
    id: id ?? this.id,
    rect: rect ?? this.rect,
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    isFilled: isFilled ?? this.isFilled,
    fillColor: fillColor ?? this.fillColor,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    zIndex: zIndex ?? this.zIndex,
    isMapObject: isMapObject ?? this.isMapObject,
    groupId: groupId ?? this.groupId,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'rectangle',
    'id': id,
    'rect': [rect.left, rect.top, rect.width, rect.height],
    'color': color.toARGB32(),
    'width': strokeWidth,
    'filled': isFilled,
    if (fillColor != null) 'fillColor': fillColor!.toARGB32(),
    'radius': cornerRadius,
    'zIndex': zIndex,
    if (isMapObject) 'isMap': true,
    if (groupId != null) 'groupId': groupId,
  };

  factory RectangleObject.fromJson(Map<String, dynamic> json) {
    final r = (json['rect'] as List).cast<num>();
    return RectangleObject(
      id: json['id'] as String,
      rect: Rect.fromLTWH(
        r[0].toDouble(),
        r[1].toDouble(),
        r[2].toDouble(),
        r[3].toDouble(),
      ),
      color: Color(json['color'] as int),
      strokeWidth: (json['width'] as num).toDouble(),
      isFilled: json['filled'] as bool? ?? false,
      fillColor: json['fillColor'] != null
          ? Color(json['fillColor'] as int)
          : null,
      cornerRadius: (json['radius'] as num?)?.toDouble() ?? 8.0,
      zIndex: (json['zIndex'] as num?)?.toDouble() ?? 0,
      isMapObject: json['isMap'] as bool? ?? false,
      groupId: json['groupId'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// 3. CircleObject
// ---------------------------------------------------------------------------

class CircleObject extends BoardObject {
  const CircleObject({
    required super.id,
    required this.rect,
    required super.color,
    required super.strokeWidth,
    this.isFilled = false,
    this.fillColor,
    super.zIndex,
    super.isMapObject = false,
    super.groupId,
  });

  final Rect rect;
  final bool isFilled;
  final Color? fillColor;

  @override
  Rect get bounds => rect;

  @override
  bool hitTest(Offset point, {double padding = 8.0}) {
    final center = rect.center;
    final rx = rect.width / 2 + strokeWidth / 2 + padding;
    final ry = rect.height / 2 + strokeWidth / 2 + padding;
    if (rx <= 0 || ry <= 0) return false;
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    return (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1.0;
  }

  @override
  CircleObject translate(Offset delta) => CircleObject(
    id: id,
    rect: rect.shift(delta),
    color: color,
    strokeWidth: strokeWidth,
    isFilled: isFilled,
    fillColor: fillColor,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  @override
  CircleObject resize(Rect newBounds) => CircleObject(
    id: id,
    rect: newBounds,
    color: color,
    strokeWidth: strokeWidth,
    isFilled: isFilled,
    fillColor: fillColor,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  CircleObject copyWith({
    String? id,
    Rect? rect,
    Color? color,
    double? strokeWidth,
    bool? isFilled,
    Color? fillColor,
    double? zIndex,
    bool? isMapObject,
    String? groupId,
  }) => CircleObject(
    id: id ?? this.id,
    rect: rect ?? this.rect,
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    isFilled: isFilled ?? this.isFilled,
    fillColor: fillColor ?? this.fillColor,
    zIndex: zIndex ?? this.zIndex,
    isMapObject: isMapObject ?? this.isMapObject,
    groupId: groupId ?? this.groupId,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'circle',
    'id': id,
    'rect': [rect.left, rect.top, rect.width, rect.height],
    'color': color.toARGB32(),
    'width': strokeWidth,
    'filled': isFilled,
    if (fillColor != null) 'fillColor': fillColor!.toARGB32(),
    'zIndex': zIndex,
    if (isMapObject) 'isMap': true,
    if (groupId != null) 'groupId': groupId,
  };

  factory CircleObject.fromJson(Map<String, dynamic> json) {
    final r = (json['rect'] as List).cast<num>();
    return CircleObject(
      id: json['id'] as String,
      rect: Rect.fromLTWH(
        r[0].toDouble(),
        r[1].toDouble(),
        r[2].toDouble(),
        r[3].toDouble(),
      ),
      color: Color(json['color'] as int),
      strokeWidth: (json['width'] as num).toDouble(),
      isFilled: json['filled'] as bool? ?? false,
      fillColor: json['fillColor'] != null
          ? Color(json['fillColor'] as int)
          : null,
      zIndex: (json['zIndex'] as num?)?.toDouble() ?? 0,
      isMapObject: json['isMap'] as bool? ?? false,
      groupId: json['groupId'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// 4. LineObject (Straight line & Arrow)
// ---------------------------------------------------------------------------

class LineObject extends BoardObject {
  LineObject({
    required super.id,
    required this.start,
    required this.end,
    required super.color,
    required super.strokeWidth,
    this.isArrow = false,
    super.zIndex,
    super.isMapObject = false,
    super.groupId,
  });

  final Offset start;
  final Offset end;
  final bool isArrow;

  @override
  late final Rect bounds = Rect.fromPoints(start, end).inflate(strokeWidth / 2);

  @override
  bool hitTest(Offset point, {double padding = 8.0}) {
    if (!bounds.inflate(padding).contains(point)) return false;
    // Distance from point to line segment
    final l2 = (start - end).distanceSquared;
    if (l2 == 0) return (point - start).distance <= strokeWidth / 2 + padding;
    final t =
        ((point.dx - start.dx) * (end.dx - start.dx) +
            (point.dy - start.dy) * (end.dy - start.dy)) /
        l2;
    final clampedT = t.clamp(0.0, 1.0);
    final projection = Offset(
      start.dx + clampedT * (end.dx - start.dx),
      start.dy + clampedT * (end.dy - start.dy),
    );
    return (point - projection).distance <= strokeWidth / 2 + padding;
  }

  @override
  LineObject translate(Offset delta) => LineObject(
    id: id,
    start: start + delta,
    end: end + delta,
    color: color,
    strokeWidth: strokeWidth,
    isArrow: isArrow,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  @override
  LineObject resize(Rect newBounds) {
    return LineObject(
      id: id,
      start: newBounds.topLeft,
      end: newBounds.bottomRight,
      color: color,
      strokeWidth: strokeWidth,
      isArrow: isArrow,
      zIndex: zIndex,
      isMapObject: isMapObject,
      groupId: groupId,
    );
  }

  LineObject copyWith({
    String? id,
    Offset? start,
    Offset? end,
    Color? color,
    double? strokeWidth,
    bool? isArrow,
    double? zIndex,
    bool? isMapObject,
    String? groupId,
  }) => LineObject(
    id: id ?? this.id,
    start: start ?? this.start,
    end: end ?? this.end,
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    isArrow: isArrow ?? this.isArrow,
    zIndex: zIndex ?? this.zIndex,
    isMapObject: isMapObject ?? this.isMapObject,
    groupId: groupId ?? this.groupId,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'line',
    'id': id,
    'start': [start.dx, start.dy],
    'end': [end.dx, end.dy],
    'color': color.toARGB32(),
    'width': strokeWidth,
    'arrow': isArrow,
    'zIndex': zIndex,
    if (isMapObject) 'isMap': true,
    if (groupId != null) 'groupId': groupId,
  };

  factory LineObject.fromJson(Map<String, dynamic> json) {
    final s = (json['start'] as List).cast<num>();
    final e = (json['end'] as List).cast<num>();
    return LineObject(
      id: json['id'] as String,
      start: Offset(s[0].toDouble(), s[1].toDouble()),
      end: Offset(e[0].toDouble(), e[1].toDouble()),
      color: Color(json['color'] as int),
      strokeWidth: (json['width'] as num).toDouble(),
      isArrow: json['arrow'] as bool? ?? false,
      zIndex: (json['zIndex'] as num?)?.toDouble() ?? 0,
      isMapObject: json['isMap'] as bool? ?? false,
      groupId: json['groupId'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// 5. TextObject
// ---------------------------------------------------------------------------

class TextObject extends BoardObject {
  const TextObject({
    required super.id,
    required this.position,
    required this.text,
    required super.color,
    this.fontSize = 18.0,
    this.isBold = false,
    this.width = 200.0,
    super.strokeWidth = 1.0,
    super.zIndex,
    super.isMapObject = false,
    super.groupId,
  });

  final Offset position;
  final String text;
  final double fontSize;
  final bool isBold;
  final double width;

  @override
  Rect get bounds => Rect.fromLTWH(
    position.dx,
    position.dy,
    width,
    (text.split('\n').length * fontSize * 1.4).clamp(32.0, 500.0),
  );

  @override
  bool hitTest(Offset point, {double padding = 8.0}) =>
      bounds.inflate(padding).contains(point);

  @override
  TextObject translate(Offset delta) => TextObject(
    id: id,
    position: position + delta,
    text: text,
    color: color,
    fontSize: fontSize,
    isBold: isBold,
    width: width,
    strokeWidth: strokeWidth,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  @override
  TextObject resize(Rect newBounds) => TextObject(
    id: id,
    position: newBounds.topLeft,
    text: text,
    color: color,
    fontSize: fontSize,
    isBold: isBold,
    width: newBounds.width.clamp(60.0, 1000.0),
    strokeWidth: strokeWidth,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  TextObject copyWith({
    String? id,
    Offset? position,
    String? text,
    Color? color,
    double? fontSize,
    bool? isBold,
    double? width,
    double? strokeWidth,
    double? zIndex,
    bool? isMapObject,
    String? groupId,
  }) => TextObject(
    id: id ?? this.id,
    position: position ?? this.position,
    text: text ?? this.text,
    color: color ?? this.color,
    fontSize: fontSize ?? this.fontSize,
    isBold: isBold ?? this.isBold,
    width: width ?? this.width,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    zIndex: zIndex ?? this.zIndex,
    isMapObject: isMapObject ?? this.isMapObject,
    groupId: groupId ?? this.groupId,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'text',
    'id': id,
    'pos': [position.dx, position.dy],
    'text': text,
    'color': color.toARGB32(),
    'fontSize': fontSize,
    'bold': isBold,
    'width': width,
    'zIndex': zIndex,
    if (isMapObject) 'isMap': true,
    if (groupId != null) 'groupId': groupId,
  };

  factory TextObject.fromJson(Map<String, dynamic> json) {
    final p = (json['pos'] as List).cast<num>();
    return TextObject(
      id: json['id'] as String,
      position: Offset(p[0].toDouble(), p[1].toDouble()),
      text: json['text'] as String,
      color: Color(json['color'] as int),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
      isBold: json['bold'] as bool? ?? false,
      width: (json['width'] as num?)?.toDouble() ?? 200.0,
      zIndex: (json['zIndex'] as num?)?.toDouble() ?? 0,
      isMapObject: json['isMap'] as bool? ?? false,
      groupId: json['groupId'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// 6. StickyNoteObject
// ---------------------------------------------------------------------------

class StickyNoteObject extends BoardObject {
  const StickyNoteObject({
    required super.id,
    required this.rect,
    required this.text,
    required super.color,
    this.noteColor = const Color(0xFFFEF3C7), // warm pastel yellow
    this.fontSize = 16.0,
    super.strokeWidth = 1.0,
    super.zIndex,
    super.isMapObject = false,
    super.groupId,
  });

  final Rect rect;
  final String text;
  final Color noteColor;
  final double fontSize;

  @override
  Rect get bounds => rect;

  @override
  bool hitTest(Offset point, {double padding = 8.0}) =>
      rect.inflate(padding).contains(point);

  @override
  StickyNoteObject translate(Offset delta) => StickyNoteObject(
    id: id,
    rect: rect.shift(delta),
    text: text,
    color: color,
    noteColor: noteColor,
    fontSize: fontSize,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  @override
  StickyNoteObject resize(Rect newBounds) => StickyNoteObject(
    id: id,
    rect: newBounds,
    text: text,
    color: color,
    noteColor: noteColor,
    fontSize: fontSize,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  StickyNoteObject copyWith({
    String? id,
    Rect? rect,
    String? text,
    Color? color,
    Color? noteColor,
    double? fontSize,
    double? zIndex,
    bool? isMapObject,
    String? groupId,
  }) => StickyNoteObject(
    id: id ?? this.id,
    rect: rect ?? this.rect,
    text: text ?? this.text,
    color: color ?? this.color,
    noteColor: noteColor ?? this.noteColor,
    fontSize: fontSize ?? this.fontSize,
    zIndex: zIndex ?? this.zIndex,
    isMapObject: isMapObject ?? this.isMapObject,
    groupId: groupId ?? this.groupId,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'sticky_note',
    'id': id,
    'rect': [rect.left, rect.top, rect.width, rect.height],
    'text': text,
    'color': color.toARGB32(),
    'noteColor': noteColor.toARGB32(),
    'fontSize': fontSize,
    'zIndex': zIndex,
    if (isMapObject) 'isMap': true,
    if (groupId != null) 'groupId': groupId,
  };

  factory StickyNoteObject.fromJson(Map<String, dynamic> json) {
    final r = (json['rect'] as List).cast<num>();
    return StickyNoteObject(
      id: json['id'] as String,
      rect: Rect.fromLTWH(
        r[0].toDouble(),
        r[1].toDouble(),
        r[2].toDouble(),
        r[3].toDouble(),
      ),
      text: json['text'] as String,
      color: Color(json['color'] as int),
      noteColor: Color(json['noteColor'] as int? ?? 0xFFFEF3C7),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16.0,
      zIndex: (json['zIndex'] as num?)?.toDouble() ?? 0,
      isMapObject: json['isMap'] as bool? ?? false,
      groupId: json['groupId'] as String?,
    );
  }
}
// ---------------------------------------------------------------------------
// 7. MapPinObject (Geospatial interactive pin on whiteboard)
// ---------------------------------------------------------------------------

class MapPinObject extends BoardObject {
  MapPinObject({
    required super.id,
    required this.latitude,
    required this.longitude,
    required this.label,
    this.description = '',
    required super.color,
    this.category = 'destination',
    super.strokeWidth = 2.0,
    super.zIndex,
    super.isMapObject = true,
    super.groupId,
  }) : scenePosition = const MercatorProjection().latLngToScene(
         latitude,
         longitude,
       );

  final double latitude;
  final double longitude;
  final String label;
  final String description;
  final String category;
  final Offset scenePosition;

  @override
  Rect get bounds {
    // Pin icon anchor at bottom-center (scenePosition)
    return Rect.fromCenter(
      center: Offset(scenePosition.dx, scenePosition.dy - 18),
      width: 80,
      height: 48,
    );
  }

  @override
  bool hitTest(Offset point, {double padding = 8.0}) {
    return bounds.inflate(padding).contains(point);
  }

  @override
  MapPinObject translate(Offset delta) {
    final newScene = scenePosition + delta;
    final (newLat, newLng) = const MercatorProjection().sceneToLatLng(newScene);
    return copyWith(latitude: newLat, longitude: newLng);
  }

  @override
  MapPinObject resize(Rect newBounds) {
    final (newLat, newLng) = const MercatorProjection().sceneToLatLng(
      newBounds.bottomCenter,
    );
    return copyWith(latitude: newLat, longitude: newLng);
  }

  MapPinObject copyWith({
    String? id,
    double? latitude,
    double? longitude,
    String? label,
    String? description,
    Color? color,
    String? category,
    double? strokeWidth,
    double? zIndex,
    bool? isMapObject,
    String? groupId,
  }) => MapPinObject(
    id: id ?? this.id,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    label: label ?? this.label,
    description: description ?? this.description,
    color: color ?? this.color,
    category: category ?? this.category,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    zIndex: zIndex ?? this.zIndex,
    isMapObject: isMapObject ?? this.isMapObject,
    groupId: groupId ?? this.groupId,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'map_pin',
    'id': id,
    'lat': latitude,
    'lng': longitude,
    'label': label,
    'desc': description,
    'category': category,
    'color': color.toARGB32(),
    'width': strokeWidth,
    'zIndex': zIndex,
    if (isMapObject) 'isMap': true,
    if (groupId != null) 'groupId': groupId,
  };

  factory MapPinObject.fromJson(Map<String, dynamic> json) {
    return MapPinObject(
      id: json['id'] as String,
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      label: json['label'] as String? ?? 'Pin',
      description: json['desc'] as String? ?? '',
      category: json['category'] as String? ?? 'destination',
      color: Color(json['color'] as int),
      strokeWidth: (json['width'] as num?)?.toDouble() ?? 2.0,
      zIndex: (json['zIndex'] as num?)?.toDouble() ?? 0,
      isMapObject: json['isMap'] as bool? ?? true,
      groupId: json['groupId'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// 8. GeometricShapeObject (Triangle, Diamond, Star, Hexagon, Parallelogram, Cylinder, Cloud)
// ---------------------------------------------------------------------------

enum ShapeType {
  triangle('Triangle'),
  diamond('Diamond / Decision'),
  star('Star'),
  hexagon('Hexagon'),
  parallelogram('Data / Parallelogram'),
  cylinder('Database / Cylinder'),
  cloud('Cloud Service');

  const ShapeType(this.label);
  final String label;
}

class GeometricShapeObject extends BoardObject {
  const GeometricShapeObject({
    required super.id,
    required this.rect,
    required this.shapeType,
    required super.color,
    super.strokeWidth = 2.0,
    this.isFilled = false,
    this.fillColor,
    this.label = '',
    super.zIndex,
    super.isMapObject = false,
    super.groupId,
  });

  final Rect rect;
  final ShapeType shapeType;
  final bool isFilled;
  final Color? fillColor;
  final String label;

  @override
  Rect get bounds => rect;

  @override
  bool hitTest(Offset point, {double padding = 8.0}) =>
      rect.inflate(strokeWidth / 2 + padding).contains(point);

  @override
  GeometricShapeObject translate(Offset delta) => GeometricShapeObject(
    id: id,
    rect: rect.shift(delta),
    shapeType: shapeType,
    color: color,
    strokeWidth: strokeWidth,
    isFilled: isFilled,
    fillColor: fillColor,
    label: label,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  @override
  GeometricShapeObject resize(Rect newBounds) => GeometricShapeObject(
    id: id,
    rect: newBounds,
    shapeType: shapeType,
    color: color,
    strokeWidth: strokeWidth,
    isFilled: isFilled,
    fillColor: fillColor,
    label: label,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  GeometricShapeObject copyWith({
    String? id,
    Rect? rect,
    ShapeType? shapeType,
    Color? color,
    double? strokeWidth,
    bool? isFilled,
    Color? fillColor,
    String? label,
    double? zIndex,
    bool? isMapObject,
    String? groupId,
  }) => GeometricShapeObject(
    id: id ?? this.id,
    rect: rect ?? this.rect,
    shapeType: shapeType ?? this.shapeType,
    color: color ?? this.color,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    isFilled: isFilled ?? this.isFilled,
    fillColor: fillColor ?? this.fillColor,
    label: label ?? this.label,
    zIndex: zIndex ?? this.zIndex,
    isMapObject: isMapObject ?? this.isMapObject,
    groupId: groupId ?? this.groupId,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'shape',
    'id': id,
    'shape': shapeType.name,
    'rect': [rect.left, rect.top, rect.width, rect.height],
    'color': color.toARGB32(),
    'width': strokeWidth,
    'filled': isFilled,
    if (fillColor != null) 'fillColor': fillColor!.toARGB32(),
    if (label.isNotEmpty) 'label': label,
    'zIndex': zIndex,
    if (isMapObject) 'isMap': true,
    if (groupId != null) 'groupId': groupId,
  };

  factory GeometricShapeObject.fromJson(Map<String, dynamic> json) {
    final r = (json['rect'] as List).cast<num>();
    return GeometricShapeObject(
      id: json['id'] as String,
      rect: Rect.fromLTWH(
        r[0].toDouble(),
        r[1].toDouble(),
        r[2].toDouble(),
        r[3].toDouble(),
      ),
      shapeType: ShapeType.values.firstWhere(
        (t) => t.name == json['shape'],
        orElse: () => ShapeType.triangle,
      ),
      color: Color(json['color'] as int),
      strokeWidth: (json['width'] as num).toDouble(),
      isFilled: json['filled'] as bool? ?? false,
      fillColor: json['fillColor'] != null
          ? Color(json['fillColor'] as int)
          : null,
      label: json['label'] as String? ?? '',
      zIndex: (json['zIndex'] as num?)?.toDouble() ?? 0,
      isMapObject: json['isMap'] as bool? ?? false,
      groupId: json['groupId'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// 9. ErColumn & ErTableObject (Entity-Relationship Database Tables)
// ---------------------------------------------------------------------------

class ErColumn {
  const ErColumn({
    required this.name,
    required this.type,
    this.isPrimaryKey = false,
    this.isForeignKey = false,
    this.isNullable = false,
  });

  final String name;
  final String type;
  final bool isPrimaryKey;
  final bool isForeignKey;
  final bool isNullable;

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'pk': isPrimaryKey,
    'fk': isForeignKey,
    'null': isNullable,
  };

  factory ErColumn.fromJson(Map<String, dynamic> json) => ErColumn(
    name: json['name'] as String? ?? 'id',
    type: json['type'] as String? ?? 'UUID',
    isPrimaryKey: json['pk'] as bool? ?? false,
    isForeignKey: json['fk'] as bool? ?? false,
    isNullable: json['null'] as bool? ?? false,
  );
}

class ErTableObject extends BoardObject {
  const ErTableObject({
    required super.id,
    required this.position,
    required this.tableName,
    required this.columns,
    required super.color,
    this.width = 240.0,
    super.strokeWidth = 2.0,
    super.zIndex,
    super.isMapObject = false,
    super.groupId,
  });

  final Offset position;
  final String tableName;
  final List<ErColumn> columns;
  final double width;

  static const double headerHeight = 38.0;
  static const double rowHeight = 28.0;

  double get height =>
      headerHeight + (columns.isEmpty ? 1 : columns.length) * rowHeight + 12.0;

  @override
  Rect get bounds => Rect.fromLTWH(position.dx, position.dy, width, height);

  @override
  bool hitTest(Offset point, {double padding = 8.0}) =>
      bounds.inflate(padding).contains(point);

  @override
  ErTableObject translate(Offset delta) => ErTableObject(
    id: id,
    position: position + delta,
    tableName: tableName,
    columns: columns,
    color: color,
    width: width,
    strokeWidth: strokeWidth,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  @override
  ErTableObject resize(Rect newBounds) => ErTableObject(
    id: id,
    position: newBounds.topLeft,
    tableName: tableName,
    columns: columns,
    color: color,
    width: newBounds.width.clamp(160.0, 600.0),
    strokeWidth: strokeWidth,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  ErTableObject copyWith({
    String? id,
    Offset? position,
    String? tableName,
    List<ErColumn>? columns,
    Color? color,
    double? width,
    double? strokeWidth,
    double? zIndex,
    bool? isMapObject,
    String? groupId,
  }) => ErTableObject(
    id: id ?? this.id,
    position: position ?? this.position,
    tableName: tableName ?? this.tableName,
    columns: columns ?? this.columns,
    color: color ?? this.color,
    width: width ?? this.width,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    zIndex: zIndex ?? this.zIndex,
    isMapObject: isMapObject ?? this.isMapObject,
    groupId: groupId ?? this.groupId,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'er_table',
    'id': id,
    'pos': [position.dx, position.dy],
    'table': tableName,
    'columns': columns.map((c) => c.toJson()).toList(),
    'color': color.toARGB32(),
    'width': width,
    'strokeWidth': strokeWidth,
    'zIndex': zIndex,
    if (isMapObject) 'isMap': true,
    if (groupId != null) 'groupId': groupId,
  };

  factory ErTableObject.fromJson(Map<String, dynamic> json) {
    final p = (json['pos'] as List).cast<num>();
    final rawCols = json['columns'] as List? ?? [];
    return ErTableObject(
      id: json['id'] as String,
      position: Offset(p[0].toDouble(), p[1].toDouble()),
      tableName: json['table'] as String? ?? 'table_name',
      columns: rawCols
          .map((c) => ErColumn.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList(),
      color: Color(json['color'] as int? ?? 0xFF3B82F6),
      width: (json['width'] as num?)?.toDouble() ?? 240.0,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      zIndex: (json['zIndex'] as num?)?.toDouble() ?? 0,
      isMapObject: json['isMap'] as bool? ?? false,
      groupId: json['groupId'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// 10. ErRelationshipObject (Cardinality connectors: 1:1, 1:N, N:M)
// ---------------------------------------------------------------------------

enum ErCardinality {
  oneToOne('1 : 1'),
  oneToMany('1 : N'),
  manyToMany('N : M');

  const ErCardinality(this.label);
  final String label;
}

class ErRelationshipObject extends BoardObject {
  ErRelationshipObject({
    required super.id,
    required this.start,
    required this.end,
    required super.color,
    this.label = '',
    this.cardinality = ErCardinality.oneToMany,
    this.fromTableId,
    this.toTableId,
    super.strokeWidth = 2.0,
    super.zIndex,
    super.isMapObject = false,
    super.groupId,
  });

  final Offset start;
  final Offset end;
  final String label;
  final ErCardinality cardinality;
  final String? fromTableId;
  final String? toTableId;

  @override
  late final Rect bounds = Rect.fromPoints(start, end).inflate(16.0);

  @override
  bool hitTest(Offset point, {double padding = 8.0}) {
    if (!bounds.inflate(padding).contains(point)) return false;
    final l2 = (start - end).distanceSquared;
    if (l2 == 0) return (point - start).distance <= strokeWidth / 2 + padding;
    final t =
        ((point.dx - start.dx) * (end.dx - start.dx) +
            (point.dy - start.dy) * (end.dy - start.dy)) /
        l2;
    final clampedT = t.clamp(0.0, 1.0);
    final projection = Offset(
      start.dx + clampedT * (end.dx - start.dx),
      start.dy + clampedT * (end.dy - start.dy),
    );
    return (point - projection).distance <= strokeWidth / 2 + padding;
  }

  @override
  ErRelationshipObject translate(Offset delta) => ErRelationshipObject(
    id: id,
    start: start + delta,
    end: end + delta,
    color: color,
    label: label,
    cardinality: cardinality,
    fromTableId: fromTableId,
    toTableId: toTableId,
    strokeWidth: strokeWidth,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  @override
  ErRelationshipObject resize(Rect newBounds) => ErRelationshipObject(
    id: id,
    start: newBounds.topLeft,
    end: newBounds.bottomRight,
    color: color,
    label: label,
    cardinality: cardinality,
    fromTableId: fromTableId,
    toTableId: toTableId,
    strokeWidth: strokeWidth,
    zIndex: zIndex,
    isMapObject: isMapObject,
    groupId: groupId,
  );

  ErRelationshipObject copyWith({
    String? id,
    Offset? start,
    Offset? end,
    Color? color,
    String? label,
    ErCardinality? cardinality,
    String? fromTableId,
    String? toTableId,
    double? strokeWidth,
    double? zIndex,
    bool? isMapObject,
    String? groupId,
  }) => ErRelationshipObject(
    id: id ?? this.id,
    start: start ?? this.start,
    end: end ?? this.end,
    color: color ?? this.color,
    label: label ?? this.label,
    cardinality: cardinality ?? this.cardinality,
    fromTableId: fromTableId ?? this.fromTableId,
    toTableId: toTableId ?? this.toTableId,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    zIndex: zIndex ?? this.zIndex,
    isMapObject: isMapObject ?? this.isMapObject,
    groupId: groupId ?? this.groupId,
  );

  @override
  Map<String, dynamic> toJson() => {
    'type': 'er_relationship',
    'id': id,
    'start': [start.dx, start.dy],
    'end': [end.dx, end.dy],
    'label': label,
    'cardinality': cardinality.name,
    if (fromTableId != null) 'fromTable': fromTableId,
    if (toTableId != null) 'toTable': toTableId,
    'color': color.toARGB32(),
    'width': strokeWidth,
    'zIndex': zIndex,
    if (isMapObject) 'isMap': true,
    if (groupId != null) 'groupId': groupId,
  };

  factory ErRelationshipObject.fromJson(Map<String, dynamic> json) {
    final s = (json['start'] as List).cast<num>();
    final e = (json['end'] as List).cast<num>();
    return ErRelationshipObject(
      id: json['id'] as String,
      start: Offset(s[0].toDouble(), s[1].toDouble()),
      end: Offset(e[0].toDouble(), e[1].toDouble()),
      label: json['label'] as String? ?? '',
      cardinality: ErCardinality.values.firstWhere(
        (c) => c.name == json['cardinality'],
        orElse: () => ErCardinality.oneToMany,
      ),
      fromTableId: json['fromTable'] as String?,
      toTableId: json['toTable'] as String?,
      color: Color(json['color'] as int? ?? 0xFF64748B),
      strokeWidth: (json['width'] as num?)?.toDouble() ?? 2.0,
      zIndex: (json['zIndex'] as num?)?.toDouble() ?? 0,
      isMapObject: json['isMap'] as bool? ?? false,
      groupId: json['groupId'] as String?,
    );
  }
}
