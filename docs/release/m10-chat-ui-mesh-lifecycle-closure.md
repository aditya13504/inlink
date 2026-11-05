> **Superseded in part by M11:** M11 adds an Android runtime composition and a challenge/proof identity control channel. Its device-level acceptance gates remain open; see `m11-native-mesh-integration-closure.md`.

# M10 Closure — Chat UI and Mesh Application Lifecycle Integration

## Delivered in this package

- `ConversationsPage` accepts an optional `MeshApplicationService` dependency. The page subscribes to its event stream, starts it once during page initialization, restores the durable mesh outbox through the service, and disposes the service when the page is disposed.
- Added a mesh status row and explicit retry/start control when a service is injected.
- Added a distinct mesh-send action. It calls `MeshApplicationService.sendText`, which encrypts for the selected verified contact and persists the outgoing record before attempting mesh routing. It does not silently fall back to the legacy transport.
- Mesh application events refresh the durable conversation list. The UI distinguishes queued, authenticated inbound, delivered receipt, forwarding, duplicate, rejection and recovery states.
- The existing legacy BLE/relay queue/send controls remain in place and are labelled separately; the new path does not reinterpret legacy outbox rows as mesh messages.
- Added this integration and acceptance checklist to make remaining composition and device gates explicit.

## Important boundary

The app's default composition root does **not** inject a mesh service yet. The current native BLE transport still does not implement the stable-ID, multi-peer `MeshPeerTransport` boundary needed for safe default construction, and the identity-to-peer binding requires physical-device validation. Therefore the mesh action remains disabled in the default app and is enabled only when a caller injects a correctly configured `MeshApplicationService`. This milestone is a UI/lifecycle integration seam, not a claim of working live multi-hop delivery.

## Not verified in this environment

- Flutter/Dart SDK availability and dependency resolution.
- `dart format`, `flutter analyze`, `flutter test`, Android Gradle build.
- Physical Android peer authentication, fragmentation/reassembly, reconnect, inbound receipt, and multi-hop delivery.
- iOS BLE transport, which remains unimplemented.
- Independent cryptographic review.

## Validation checklist on a Flutter-enabled host

1. Run `dart format lib test`, `flutter pub get`, `flutter analyze`, and `flutter test` from `app/`.
2. Build Android debug and launch the existing legacy chat flow to confirm no regression.
3. Inject a configured test/fake `MeshApplicationService`; confirm start/recovery status, retry action, and mesh send action.
4. Confirm a queued event refreshes local history and a valid signed recipient receipt alone moves a mesh message to `delivered`.
5. Confirm a failed transport attempt leaves the durable message in the outbox and the composer reports the condition without falling back to plaintext or legacy routing.
6. Confirm widget disposal cancels the event subscription and disposes the injected service.
7. On physical devices, validate two-node delivery and then three-node forwarding with stable authenticated node IDs. Do not treat a BLE address as an identity.
