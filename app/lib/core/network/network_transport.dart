/// Platform-neutral network capability and transport contract.
///
/// Implementations must not claim that a transport is available until the
/// platform confirms that capability. This interface is not a security layer.
class NetworkCapabilities {
  const NetworkCapabilities({
    required this.platformName,
    required this.bleSupported,
    required this.bleImplemented,
    required this.internetRelayImplemented,
    this.multiPeerBleImplemented = false,
    required this.note,
  });

  final String platformName;
  final bool bleSupported;
  final bool bleImplemented;
  final bool internetRelayImplemented;
  final bool multiPeerBleImplemented;
  final String note;
}

abstract interface class NetworkTransport {
  Future<NetworkCapabilities> getCapabilities();
}
