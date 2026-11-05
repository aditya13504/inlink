#!/usr/bin/env python3
"""Source-level M12 contract checks; not a substitute for Flutter/iOS builds."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

def require(ok: bool, message: str) -> None:
    if not ok:
        raise SystemExit(f"FAIL: {message}")

swift = (ROOT / "app/ios/Runner/AppDelegate.swift").read_text()
plist = (ROOT / "app/ios/Runner/Info.plist").read_text()
dart = (ROOT / "app/lib/core/network/native_network_transport.dart").read_text()
network = (ROOT / "app/lib/core/network/network_transport.dart").read_text()
tests = (ROOT / "app/test/native_network_transport_test.dart").read_text()
kotlin = (ROOT / "app/android/app/src/main/kotlin/com/example/inlink/MainActivity.kt").read_text()

for method in ("getCapabilities", "startBle", "stopBle", "getConnectedPeers",
                "sendBleFrame", "sendBleFrameToPeer"):
    require(f'"{method}"' in swift, f"iOS missing method-channel method {method}")
    require(f'"{method}"' in kotlin, f"Android missing method-channel method {method}")

require("CBCentralManagerDelegate" in swift and "CBPeripheralManagerDelegate" in swift,
        "iOS must implement central and peripheral roles")
require("9F3A1000-7B4D-4F3C-9A12-2F6E1A000001" in swift and
        "9f3a1000-7b4d-4f3c-9a12-2f6e1a000001" in kotlin,
        "service UUIDs must match across platforms")
require("9F3A1001-7B4D-4F3C-9A12-2F6E1A000001" in swift and
        "9f3a1001-7b4d-4f3c-9a12-2f6e1a000001" in kotlin,
        "frame characteristic UUIDs must match across platforms")
require("<key>NSBluetoothAlwaysUsageDescription</key>" in plist,
        "iOS Bluetooth usage description must be present")
require('"multiPeerBleImplemented": true' in swift,
        "iOS capabilities must match the implemented CoreBluetooth source")
require("late final Stream<Map<String, Object?>> events" in dart,
        "Dart native event stream must be shared")
require("multiPeerBleImplemented" in network,
        "cross-platform capability contract must expose multi-peer support")
require("event stream is a single shared broadcast stream" in tests and
        "targeted sends pass peer handle" in tests and
        "rejects oversized or empty frames" in tests,
        "native transport contract tests are missing")
for relative in (
    "docs/release/m12-cross-platform-transport-closure.md",
    "docs/testing/m12-cross-platform-transport.md",
    "docs/protocol/native-transport-contract-v1.md",
):
    require((ROOT / relative).is_file(), f"missing {relative}")
print("M12 source-contract checks passed. This does not replace type-checking, builds, or device tests.")
