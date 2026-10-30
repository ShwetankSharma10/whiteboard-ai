import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Classifying device interaction kinds for S-Pen and capacitive touch.
enum StylusInteractionType {
  stylusDraw,
  invertedStylusErase,
  touchDrawOrPan,
  rejectedPalm,
}

/// Hardware palm rejection and stylus pressure calculation engine tailored for
/// Android tablets, Samsung Galaxy Tab / S-Pen, Pixel Fold, and Chromebooks.
class StylusService {
  StylusService({
    this.palmLockDurationMs = 400,
    this.palmRadiusThreshold = 25.0,
  });

  final int palmLockDurationMs;
  final double palmRadiusThreshold;

  int _lastStylusEventTimestamp = 0;

  /// Records stylus activity timestamp.
  void recordStylusActivity([int? timestampMs]) {
    _lastStylusEventTimestamp =
        timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  }

  /// Evaluates an incoming [PointerDownEvent] or [PointerMoveEvent] and classifies
  /// whether it is valid stylus drawing, inverted eraser, standard touch, or an accidental palm touch.
  StylusInteractionType classifyPointerEvent(
    PointerEvent event, {
    int activePointersCount = 1,
    int? currentTimestampMs,
  }) {
    final now = currentTimestampMs ?? DateTime.now().millisecondsSinceEpoch;

    // 1. Inverted Stylus (Physical eraser tip on S-Pen or stylus tail)
    if (event.kind == PointerDeviceKind.invertedStylus) {
      recordStylusActivity(now);
      return StylusInteractionType.invertedStylusErase;
    }

    // 2. Active Stylus Tip
    if (event.kind == PointerDeviceKind.stylus) {
      recordStylusActivity(now);
      return StylusInteractionType.stylusDraw;
    }

    // 3. Capacitive Touch (Fingers or Palm)
    if (event.kind == PointerDeviceKind.touch) {
      // Rule A: If stylus was used within [palmLockDurationMs], reject single-finger touch
      // as accidental palm rest (unless 2+ fingers are present for intentional pinch/zoom)
      final timeSinceStylus = now - _lastStylusEventTimestamp;
      if (timeSinceStylus < palmLockDurationMs && activePointersCount <= 1) {
        return StylusInteractionType.rejectedPalm;
      }

      // Rule B: High contact area typical of palm heel / fleshy part of hand.
      // Only enforce when a physical stylus has been used in the session (or for
      // explicit radiusMajor synthetic events where size == 0.0), so Android
      // Emulator mouse-to-touch clicks (which report size ~ 0.5) are never blocked.
      if (event.radiusMajor > palmRadiusThreshold &&
          (_lastStylusEventTimestamp > 0 || event.size == 0.0)) {
        return StylusInteractionType.rejectedPalm;
      }

      return StylusInteractionType.touchDrawOrPan;
    }

    // Mouse or trackpad
    return StylusInteractionType.touchDrawOrPan;
  }

  /// Calculates dynamic stroke thickness based on S-Pen / stylus pressure.
  /// Normalized pressure typically ranges from 0.0 (feather touch) to 1.0 (heavy press).
  static double calculateDynamicWidth({
    required double baseWidth,
    required double pressure,
    required PointerDeviceKind kind,
  }) {
    if (kind != PointerDeviceKind.stylus &&
        kind != PointerDeviceKind.invertedStylus) {
      return baseWidth;
    }

    // Clamp pressure to [0.05, 1.0] to prevent invisible strokes on feather touch
    final clampedPressure = pressure <= 0.0 ? 0.5 : pressure.clamp(0.08, 1.0);

    // Dynamic curve: 40% width at light touch, up to 160% width at full pressure
    final dynamicFactor = 0.4 + (1.2 * clampedPressure);
    return (baseWidth * dynamicFactor).clamp(1.0, baseWidth * 2.5);
  }

  /// Evaluates whether the device is in a foldable table-top / half-opened posture.
  static bool isFoldableTableTop(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    for (final feature in mediaQuery.displayFeatures) {
      if (feature.type == DisplayFeatureType.hinge ||
          feature.type == DisplayFeatureType.fold) {
        // Horizontal hinge splitting top and bottom screen
        if (feature.bounds.width > feature.bounds.height) {
          return true;
        }
      }
    }
    return false;
  }
}
