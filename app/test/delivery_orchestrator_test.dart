import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/messaging/delivery_orchestrator.dart';

void main() {
  group('DeliveryRoutePlanner', () {
    const planner = DeliveryRoutePlanner();

    test('prefers direct BLE when both transports are available', () {
      expect(
        planner.choose(bleReady: true, relayConfigured: true),
        DeliveryRoute.ble,
      );
    });

    test('falls back to relay when BLE is not ready', () {
      expect(
        planner.choose(bleReady: false, relayConfigured: true),
        DeliveryRoute.internetRelay,
      );
    });

    test('returns no route when neither transport is usable', () {
      expect(
        planner.choose(bleReady: false, relayConfigured: false),
        isNull,
      );
    });
  });
}
