import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/native_network_transport.dart';
import '../../core/network/mesh/native_mesh_runtime.dart';
import 'conversations_page.dart';

/// Creates and disposes the integrated experimental mesh dependency graph.
/// BLE is not auto-started; the user must explicitly start it from the home
/// screen. Only contacts already verified by the identity flow can authenticate.
class NativeMeshConversationsRoute extends StatefulWidget {
  const NativeMeshConversationsRoute({required this.transport, super.key});

  final NativeNetworkTransport transport;

  @override
  State<NativeMeshConversationsRoute> createState() =>
      _NativeMeshConversationsRouteState();
}

class _NativeMeshConversationsRouteState
    extends State<NativeMeshConversationsRoute> {
  NativeMeshRuntime? _runtime;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    NativeMeshRuntime? runtime;
    try {
      runtime = await NativeMeshRuntime.create(native: widget.transport);
      await runtime.start();
      if (!mounted) {
        await runtime.dispose();
        return;
      }
      setState(() {
        _runtime = runtime;
        _loading = false;
      });
    } catch (error) {
      if (runtime != null) await runtime.dispose();
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    final runtime = _runtime;
    if (runtime != null) unawaited(runtime.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Preparing encrypted mesh services…'),
            ],
          ),
        ),
      );
    }
    if (_error != null || runtime == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mesh setup')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Could not initialize the mesh runtime.'),
              const SizedBox(height: 8),
              Text('Details: $_error'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  unawaited(_createRuntime());
                },
                child: const Text('Retry setup'),
              ),
            ],
          ),
        ),
      );
    }
    return ConversationsPage(
      vault: runtime.vault,
      repository: runtime.repository,
      messageService: runtime.verifiedMessages,
      transport: runtime.native,
      meshService: runtime.service,
    );
  }
}
