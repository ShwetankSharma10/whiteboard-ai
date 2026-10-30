import 'package:flutter/material.dart';

/// Represents a collaborator's real-time presence on a whiteboard.
@immutable
class UserPresence {
  const UserPresence({
    required this.userId,
    required this.userName,
    required this.colorValue,
    required this.x,
    required this.y,
    required this.lastActive,
    this.toolName = 'pen',
  });

  final String userId;
  final String userName;
  final int colorValue;
  final double x;
  final double y;
  final int lastActive;
  final String toolName;

  Color get color => Color(colorValue);
  Offset get position => Offset(x, y);

  /// Returns true if this presence received a heartbeat within the last [timeoutMs].
  bool isOnline({int timeoutMs = 30000}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastActive) <= timeoutMs;
  }

  UserPresence copyWith({
    String? userId,
    String? userName,
    int? colorValue,
    double? x,
    double? y,
    int? lastActive,
    String? toolName,
  }) => UserPresence(
    userId: userId ?? this.userId,
    userName: userName ?? this.userName,
    colorValue: colorValue ?? this.colorValue,
    x: x ?? this.x,
    y: y ?? this.y,
    lastActive: lastActive ?? this.lastActive,
    toolName: toolName ?? this.toolName,
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'userName': userName,
    'colorValue': colorValue,
    'x': x,
    'y': y,
    'lastActive': lastActive,
    'toolName': toolName,
  };

  factory UserPresence.fromJson(Map<String, dynamic> json) {
    return UserPresence(
      userId: json['userId'] as String? ?? '',
      userName: json['userName'] as String? ?? 'Collaborator',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF3B82F6,
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      lastActive:
          (json['lastActive'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      toolName: json['toolName'] as String? ?? 'pen',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserPresence &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          userName == other.userName &&
          colorValue == other.colorValue &&
          x == other.x &&
          y == other.y &&
          lastActive == other.lastActive &&
          toolName == other.toolName;

  @override
  int get hashCode =>
      Object.hash(userId, userName, colorValue, x, y, lastActive, toolName);
}
