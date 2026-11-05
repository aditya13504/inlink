import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'core/network/ble/ble_frame.dart';
import 'core/network/native_network_transport.dart';
import 'core/network/network_transport.dart';
import 'features/identity/identity_contacts_page.dart';
import 'features/chat/conversations_page.dart';
import 'features/chat/native_mesh_conversations_route.dart';

void main() {
  runApp(InLinkApp(transport: NativeNetworkTransport()));
}

class InLinkApp extends StatelessWidget {
  const InLinkApp({required this.transport, super.key});

  final NetworkTransport transport;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InLink',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5267D8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: InLinkHomePage(transport: transport),
    );
  }
}

class InLinkHomePage extends StatefulWidget {
  const InLinkHomePage({required this.transport, super.key});

  final NetworkTransport transport;

  @override
  State<InLinkHomePage> createState() => _InLinkHomePageState();
}

class _InLinkHomePageState extends State<InLinkHomePage> {
  String _status = 'BLE experiment not started';
  String _details = 'Start BLE on two nearby Android devices to test discovery.';
  bool _bleStarted = false;
  bool _busy = false;
  final List<String> _eventLog = <String>[];
  dynamic _eventSubscription;

  NativeNetworkTransport? get _nativeTransport =>
      widget.transport is NativeNetworkTransport
          ? widget.transport as NativeNetworkTransport
          : null;

  @override
  void initState() {
    super.initState();
    final native = _nativeTransport;
    if (native != null) {
      _eventSubscription = native.events.listen(
        _onNativeEvent,
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _status = 'BLE event stream error';
            _details = error.toString();
          });
        },
      );
    }
  }

  void _onNativeEvent(Map<String, Object?> event) {
    if (!mounted) return;
    final type = event['type']?.toString() ?? 'event';
    final summary = switch (type) {
      'peerFound' => 'Found peer ${event['peer']} (RSSI ${event['rssi']})',
      'peerConnected' => 'Connected to ${event['peer']} (${event['role']})',
      'peerDisconnected' => 'Disconnected from ${event['peer']}',
      'recovery' => 'BLE recovery: ${event['reason'] ?? event['action'] ?? 'reconnecting'}',
      'readyToSend' => 'GATT service ready for ${event['peer']}',
      'frameReceived' => 'Received ${((event['frame'] as List?) ?? const []).length} frame bytes',
      'frameSent' => 'Frame write callback: status ${event['status']}',
      'mtuChanged' => 'Negotiated MTU ${event['mtu']} (status ${event['status']})',
      'error' => 'BLE error: ${event['message'] ?? event['operation'] ?? event['code']}',
      _ => '$type ${event.entries.where((entry) => entry.key != 'type').map((entry) => '${entry.key}=${entry.value}').join(' ')}',
    };
    setState(() {
      _status = switch (type) {
        'started' => 'BLE running — searching for peers',
        'peerFound' => 'Peer discovered',
        'peerConnected' => 'BLE peer connected',
        'recovery' => 'BLE recovering — scanning again',
        'readyToSend' => 'Peer ready for test frames',
        'frameReceived' => 'Test frame received',
        'stopped' => 'BLE stopped',
        'error' => 'BLE error',
        'permissionDenied' => 'Bluetooth permission denied',
        _ => _status,
      };
      _eventLog.insert(0, '${DateTime.now().toLocal().toIso8601String().substring(11, 19)}  $summary');
      if (_eventLog.length > 12) _eventLog.removeLast();
      _details = _eventLog.join('\n');
    });
  }

  Future<void> _openConversations() async {
    final native = _nativeTransport;
    Widget page = ConversationsPage(transport: widget.transport);
    if (native != null) {
      try {
        final capabilities = await widget.transport.getCapabilities();
        if (!mounted) return;
        if (capabilities.multiPeerBleImplemented) {
          page = NativeMeshConversationsRoute(transport: native);
        }
      } catch (_) {
        // Keep the existing non-mesh conversation path available when native
        // capability discovery fails on an unsupported platform.
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  Future<void> _checkCapabilities() async {
    setState(() {
      _status = 'Checking transport';
      _details = 'Reading capabilities from the configured transport...';
    });
    try {
      final capabilities = await widget.transport.getCapabilities();
      if (!mounted) return;
      setState(() {
        _status = capabilities.platformName;
        _details = [
          'BLE supported: ${capabilities.bleSupported}',
          'BLE implemented: ${capabilities.bleImplemented}',
          'Internet relay implemented: ${capabilities.internetRelayImplemented}',
          capabilities.note,
        ].join('\n');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Transport unavailable';
        _details = error.toString();
      });
    }
  }

  Future<void> _startBle() async {
    final native = _nativeTransport;
    if (native == null) return;
    setState(() => _busy = true);
    try {
      await native.startBle();
      if (!mounted) return;
      setState(() {
        _bleStarted = true;
        _status = 'Starting BLE discovery';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not start BLE';
        _details = error.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopBle() async {
    final native = _nativeTransport;
    if (native == null) return;
    setState(() => _busy = true);
    try {
      await native.stopBle();
      if (!mounted) return;
      setState(() => _bleStarted = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not stop BLE';
        _details = error.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendTestFrame() async {
    final native = _nativeTransport;
    if (native == null) return;
    setState(() => _busy = true);
    try {
      final random = Random.secure();
      final transferId = random.nextInt(0x100000000);
      final payload = utf8.encode(
        'INLINK SYNTHETIC TEST ${DateTime.now().toUtc().toIso8601String()}',
      );
      final frame = BleFrame(
        transferId: transferId,
        fragmentIndex: 0,
        fragmentCount: 1,
        payload: payload,
      );
      final result = await native.sendBleFrame(frame.encode());
      if (!mounted) return;
      setState(() {
        _eventLog.insert(0, 'Send accepted by Android: ${result['path']}');
        if (_eventLog.length > 12) _eventLog.removeLast();
        _details = _eventLog.join('\n');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Test frame was not sent';
        _details = error.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    // EventChannel stream subscription is cancelled through its subscription API.
    final subscription = _eventSubscription;
    if (subscription != null) subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNative = _nativeTransport != null;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Conversations',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: _openConversations,
          ),
          IconButton(
            tooltip: 'Identity & contacts',
            icon: const Icon(Icons.contacts_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const IdentityContactsPage(),
                ),
              );
            },
          ),
        ],
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('InLink'),
            Text(
              'Private by design. Connected when possible.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.hub_outlined, size: 64),
            const SizedBox(height: 20),
            Text(
              'Communication without a single point of dependence.',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'M1 is a direct-link experiment. Start BLE on two nearby Android '
              'devices and exchange synthetic test frames. This is not secure messaging.',
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Network status', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(_status),
                    const SizedBox(height: 8),
                    SelectableText(_details),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _checkCapabilities,
                      icon: const Icon(Icons.network_check),
                      label: const Text('Check network capabilities'),
                    ),
                    if (isNative) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _busy ? null : (_bleStarted ? _stopBle : _startBle),
                        icon: Icon(_bleStarted ? Icons.bluetooth_disabled : Icons.bluetooth_searching),
                        label: Text(_bleStarted ? 'Stop BLE' : 'Start BLE discovery'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy || !_bleStarted ? null : _sendTestFrame,
                        icon: const Icon(Icons.send),
                        label: const Text('Send synthetic test frame'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (isNative) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recent BLE events', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(_eventLog.isEmpty ? 'No events yet.' : _eventLog.join('\n')),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Development build only. The BLE prototype has not been '
                        'compiled or tested on physical devices. Do not use for sensitive '
                        'communication. No encryption, identity, durable delivery or relay is implemented.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
