/// Route selection for the single durable outbound queue.
///
/// A transport accepting bytes is not proof of recipient delivery. The
/// authenticated end-to-end receipt remains the only transition to DELIVERED.
enum DeliveryRoute { ble, internetRelay }

class DeliveryRoutePlanner {
  const DeliveryRoutePlanner();

  /// Prefer an available direct BLE link; use the internet relay when BLE is
  /// unavailable and a non-placeholder relay URL is configured.
  DeliveryRoute? choose({
    required bool bleReady,
    required bool relayConfigured,
  }) {
    if (bleReady) return DeliveryRoute.ble;
    if (relayConfigured) return DeliveryRoute.internetRelay;
    return null;
  }
}
