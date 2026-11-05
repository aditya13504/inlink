# M3.8 — Connectivity awareness and restart recovery

This milestone improves foreground recovery without claiming a guaranteed
always-on service.

## Implemented

- The conversation screen observes Flutter app lifecycle transitions.
- When the app returns to the foreground, it refreshes local state, polls the
  configured relay, then drains the persistent outgoing/receipt queues.
- When a valid non-placeholder relay URL is configured, the app attempts relay
  mailbox polling every 30 seconds while the conversation screen is alive.
- Existing five-second foreground queue draining resumes due outgoing messages
  and receipt work using persisted retry counts, due timestamps and expiry.
- Relay URLs continue to require HTTPS except for loopback development hosts.
- If the relay is unreachable, polling reports an error and the local queue is
  retained for later retries.

## What "connectivity awareness" means here

This version uses an actual relay request as the practical internet-availability
check rather than adding a separate OS connectivity plugin. A request can still
fail because of DNS, TLS, server downtime, or captive portals. The app does not
yet continuously monitor radio/network interfaces or guarantee immediate route
switching. BLE remains event-driven by native GATT readiness/disconnect events.

## Validation required

- Run `flutter pub get`, `flutter analyze`, and `flutter test`.
- Build Android and iOS on their supported toolchains.
- Test app background/resume, force-stop/relaunch, airplane mode, Wi-Fi/mobile
  data changes, relay outages, duplicate polling, and delayed receipts on two
  physical devices.
- Verify no duplicate visible messages and that `DELIVERED` remains receipt-only.

This is foreground recovery, not a background delivery guarantee. OS-managed
background scheduling, power management, durable encrypted database migration,
rate limiting, and independent security review remain outstanding.
