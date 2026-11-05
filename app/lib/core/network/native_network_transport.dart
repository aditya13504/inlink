import 'package:flutter/services.dart';

import 'network_transport.dart';

/// Native BLE method-channel adapter for the experimental Android transport.
///
/// The transport moves opaque frames and offers targeted multi-peer GATT sends.
/// It does not itself encrypt, authenticate, or persist application messages.
class NativeNetworkTransport implements NetworkTransport {
  static const MethodChannel _channel = MethodChannel('inlink/network');
  static const EventChannel _events = EventChannel('inlink/network-events');

  /// One shared broadcast subscription is important: the home screen, mesh
  /// handshake manager, frame receiver, and chat UI all observe the same native
  /// event channel. Recreating the EventChannel stream per getter can replace
  /// the platform sink and silently starve another consumer.
  late final Stream<Map<String, Object?>> events = _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Map<String, Object?>.from(event as Map));

  @override
  Future<NetworkCapabilities> getCapabilities() async {
    final result = await _channel.invokeMapMethod<String, Object?>('getCapabilities');
    if (result == null) {
      throw PlatformException(
        code: 'empty_capabilities',
        message: 'Native networking returned no capability information.',
      );
    }
    return NetworkCapabilities(
      platformName: result['platformName'] as String? ?? 'Unknown platform',
      bleSupported: result['bleSupported'] as bool? ?? false,
      bleImplemented: result['bleImplemented'] as bool? ?? false,
      internetRelayImplemented: result['internetRelayImplemented'] as bool? ?? false,
      multiPeerBleImplemented: result['multiPeerBleImplemented'] as bool? ?? false,
      note: result['note'] as String? ?? 'No implementation note provided.',
    );
  }

  Future<void> startBle() async {
    await _channel.invokeMethod<void>('startBle');
  }

  Future<void> stopBle() async {
    await _channel.invokeMethod<void>('stopBle');
  }

  /// Returns transport handles for currently connected BLE peers.
  /// These are platform addresses, NOT authenticated InLink node identities.
  Future<List<String>> getConnectedPeers() async {
    final peers = await _channel.invokeListMethod<Object?>('getConnectedPeers');
    return (peers ?? const <Object?>[]).whereType<String>().toList(growable: false);
  }

  /// Sends a frame to one explicitly selected connected peer. The [peer]
  /// value is a temporary BLE transport handle, not a cryptographic identity.
  Future<Map<String, Object?>> sendBleFrameToPeer({
    required String peer,
    required Uint8List frame,
  }) async {
    if (peer.isEmpty || frame.isEmpty || frame.length > 194) {
      throw ArgumentError('Expected a non-empty peer and a 1-194 byte frame.');
    }
    final result = await _channel.invokeMapMethod<String, Object?>(
      'sendBleFrameToPeer',
      <String, Object?>{'peer': peer, 'frame': frame},
    );
    if (result == null) {
      throw PlatformException(code: 'empty_send_result', message: 'Native BLE returned no send result.');
    }
    return result;
  }

  /// Sends one complete encoded InLink BLE frame.
  ///
  /// Keep frames <= 194 bytes (14-byte header + up to 180-byte payload).
  Future<Map<String, Object?>> sendBleFrame(Uint8List frame) async {
    if (frame.isEmpty || frame.length > 194) {
      throw ArgumentError.value(frame.length, 'frame.length', 'Expected 1-194 bytes');
    }
    final result = await _channel.invokeMapMethod<String, Object?>(
      'sendBleFrame',
      <String, Object?>{'frame': frame},
    );
    if (result == null) {
      throw PlatformException(code: 'empty_send_result', message: 'Native BLE returned no send result.');
    }
    return result;
  }
}
