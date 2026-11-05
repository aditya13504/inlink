import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/network/fake_network_transport.dart';

void main() {
  group('FakeNetworkTransport', () {
    test('does not claim unimplemented capabilities', () async {
      final capabilities =
          await FakeNetworkTransport().getCapabilities();

      expect(capabilities.bleSupported, isFalse);
      expect(capabilities.bleImplemented, isFalse);
      expect(capabilities.internetRelayImplemented, isFalse);
      expect(capabilities.note, contains('not implemented'));
    });
  });
}
