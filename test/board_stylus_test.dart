import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boardmate/features/board/data/stylus_service.dart';

void main() {
  group('Stage S7: StylusService & S-Pen Interaction Engine', () {
    late StylusService stylusService;

    setUp(() {
      stylusService = StylusService(
        palmLockDurationMs: 400,
        palmRadiusThreshold: 25.0,
      );
    });

    test('Stylus tip pointer down is classified as stylusDraw', () {
      const event = PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        pressure: 0.7,
      );

      final classification = stylusService.classifyPointerEvent(event);
      expect(classification, StylusInteractionType.stylusDraw);
    });

    test(
      'Inverted stylus (tail eraser) is classified as invertedStylusErase',
      () {
        const event = PointerDownEvent(
          pointer: 2,
          kind: PointerDeviceKind.invertedStylus,
        );

        final classification = stylusService.classifyPointerEvent(event);
        expect(classification, StylusInteractionType.invertedStylusErase);
      },
    );

    test(
      'Single-finger touch within 400ms of stylus activity is rejected as palm',
      () {
        const timestamp = 1000000;
        // Record stylus usage at t=1000000
        stylusService.recordStylusActivity(timestamp);

        // Stray touch arrives at t=1000150 (150ms later) with 1 pointer
        const touchEvent = PointerDownEvent(
          pointer: 3,
          kind: PointerDeviceKind.touch,
        );

        final classification = stylusService.classifyPointerEvent(
          touchEvent,
          activePointersCount: 1,
          currentTimestampMs: timestamp + 150,
        );

        expect(classification, StylusInteractionType.rejectedPalm);
      },
    );

    test('Multi-touch pinch gesture within lock window is accepted for zoom navigation', () {
      const timestamp = 1000000;
      stylusService.recordStylusActivity(timestamp);

      // 2 fingers on screen at t=1000150
      const touchEvent = PointerDownEvent(
        pointer: 4,
        kind: PointerDeviceKind.touch,
      );

      final classification = stylusService.classifyPointerEvent(
        touchEvent,
        activePointersCount: 2,
        currentTimestampMs: timestamp + 150,
      );

      expect(classification, StylusInteractionType.touchDrawOrPan);
    });

    test(
      'Touch with large contact radius (> 25px) is rejected as palm heel',
      () {
        const largeTouchEvent = PointerDownEvent(
          pointer: 5,
          kind: PointerDeviceKind.touch,
          radiusMajor: 32.0, // Large palm heel footprint
        );

        final classification = stylusService.classifyPointerEvent(
          largeTouchEvent,
        );
        expect(classification, StylusInteractionType.rejectedPalm);
      },
    );

    test(
      'calculateDynamicWidth scales thickness smoothly with stylus pressure',
      () {
        const baseWidth = 4.0;

        // Feather touch (pressure = 0.1) -> ~52% of base width
        final lightWidth = StylusService.calculateDynamicWidth(
          baseWidth: baseWidth,
          pressure: 0.1,
          kind: PointerDeviceKind.stylus,
        );
        expect(lightWidth, closeTo(baseWidth * 0.52, 0.1));
        expect(lightWidth, lessThan(baseWidth));

        // Medium touch (pressure = 0.5) -> 100% of base width
        final medWidth = StylusService.calculateDynamicWidth(
          baseWidth: baseWidth,
          pressure: 0.5,
          kind: PointerDeviceKind.stylus,
        );
        expect(medWidth, closeTo(baseWidth * 1.0, 0.1));

        // Heavy press (pressure = 1.0) -> 160% of base width
        final heavyWidth = StylusService.calculateDynamicWidth(
          baseWidth: baseWidth,
          pressure: 1.0,
          kind: PointerDeviceKind.stylus,
        );
        expect(heavyWidth, closeTo(baseWidth * 1.6, 0.1));
        expect(heavyWidth, greaterThan(baseWidth));

        // Non-stylus (mouse / capacitive touch) retains unchanged base width
        final mouseWidth = StylusService.calculateDynamicWidth(
          baseWidth: baseWidth,
          pressure: 0.9,
          kind: PointerDeviceKind.mouse,
        );
        expect(mouseWidth, baseWidth);
      },
    );
  });
}
