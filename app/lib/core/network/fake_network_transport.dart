import 'network_transport.dart';

/// Development-only transport used until native networking is implemented.
class FakeNetworkTransport implements NetworkTransport {
  @override
  Future<NetworkCapabilities> getCapabilities() async {
    return const NetworkCapabilities(
      platformName: 'Development placeholder',
      bleSupported: false,
      bleImplemented: false,
      internetRelayImplemented: false,
      note: 'BLE transport is not implemented in the development placeholder.',
    );
  }
}
