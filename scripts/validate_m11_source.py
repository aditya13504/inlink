#!/usr/bin/env python3
"""Source-level contract checks for InLink M11 (not a Dart compiler)."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")

transport = (ROOT / "app/lib/core/network/native_network_transport.dart").read_text()
manager = (ROOT / "app/lib/core/network/mesh/native_mesh_handshake_manager.dart").read_text()
runtime = (ROOT / "app/lib/core/network/mesh/native_mesh_runtime.dart").read_text()
route = (ROOT / "app/lib/features/chat/native_mesh_conversations_route.dart").read_text()
main = (ROOT / "app/lib/main.dart").read_text()
test = (ROOT / "app/test/native_mesh_handshake_manager_test.dart").read_text()
kotlin = (ROOT / "app/android/app/src/main/kotlin/com/example/inlink/MainActivity.kt").read_text()

require("late final Stream<Map<String, Object?>> events" in transport,
        "native event stream must be shared across consumers")
require("_maxControlBytes = 2048" in manager, "handshake control size must be bounded")
require("_isChallenge(Map<String, dynamic> value)" in manager and
        "_isProof(Map<String, dynamic> value)" in manager,
        "handshake control messages must be strictly typed")
require("handshake.verifyAndBind(" in manager,
        "native peer binding must go through signed trusted-contact verification")
require("handshake.cancelChallenge(challenge)" in manager,
        "failed or expired challenges must be cancellable")
require("SqlCipherMeshApplicationMessageStore(repository)" in runtime,
        "mesh and chat must share the same conversation repository")
require("NativeMeshConversationsRoute(transport: native)" in main and
        "capabilities.multiPeerBleImplemented" in main,
        "only transports advertising multi-peer support may construct the integrated runtime")
require("return ConversationsPage(" in route and "meshService: runtime.service" in route,
        "route must inject the runtime service into the chat UI")
require("mutual native handshake binds both addresses" in test,
        "bilateral simulated handshake integration test must be present")
require('"sendBleFrameToPeer"' in kotlin and '"getConnectedPeers"' in kotlin,
        "Android must expose targeted multi-peer transport methods")

for relative in (
    "docs/release/m11-native-mesh-integration-closure.md",
    "docs/testing/m11-native-mesh-integration.md",
    "docs/protocol/native-mesh-identity-control-v1.md",
):
    require((ROOT / relative).is_file(), f"missing {relative}")

print("M11 source contract checks passed. This does not replace Dart/Flutter compilation or device tests.")
