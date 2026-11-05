

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/network/native_network_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('inlink/network');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('event stream is a single shared broadcast stream', () {
    final transport = NativeNetworkTransport();
    expect(identical(transport.events, transport.events), isTrue);
  });

  test('parses Android and iOS multi-peer capabilities', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getCapabilities');
      return <String, Object?>{
        'platformName': 'iOS',
        'bleSupported': true,
        'bleImplemented': true,
        'internetRelayImplemented': false,
        'multiPeerBleImplemented': true,
        'maxOutboundPeers': 3,
        'note': 'CoreBluetooth transport',
      };
    });

    final capabilities = await NativeNetworkTransport().getCapabilities();
    expect(capabilities.platformName, 'iOS');
    expect(capabilities.bleSupported, isTrue);
    expect(capabilities.bleImplemented, isTrue);
    expect(capabilities.multiPeerBleImplemented, isTrue);
    expect(capabilities.internetRelayImplemented, isFalse);
  });

  test('targeted sends pass peer handle and exact frame bytes', () async {
    final expected = Uint8List.fromList(<int>[0x49, 0x4c, 1, 1, 7]);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'sendBleFrameToPeer');
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments['peer'], 'IOS-PEER-UUID');
      expect((arguments['frame'] as Uint8List).toList(), expected.toList());
      return <String, Object?>{
        'accepted': true,
        'path': 'gatt-write',
        'peer': 'IOS-PEER-UUID',
      };
    });

    final result = await NativeNetworkTransport().sendBleFrameToPeer(
      peer: 'IOS-PEER-UUID',
      frame: expected,
    );
    expect(result['accepted'], isTrue);
  });

  test('rejects oversized or empty frames before crossing native boundary', () async {
    final transport = NativeNetworkTransport();
    await expectLater(
      transport.sendBleFrame(Uint8List(195)),
      throwsArgumentError,
    );
    await expectLater(
      transport.sendBleFrameToPeer(peer: 'peer', frame: Uint8List(0)),
      throwsArgumentError,
    );
  });

  test('reads connected native peer handles', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getConnectedPeers');
      return <String>['PEER-A', 'PEER-B'];
    });
    expect(await NativeNetworkTransport().getConnectedPeers(),
        <String>['PEER-A', 'PEER-B']);
  });
}
