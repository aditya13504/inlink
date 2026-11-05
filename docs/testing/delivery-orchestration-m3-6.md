# M3.6 — Automatic delivery orchestration

This milestone adds a route-selection seam to the shared durable outgoing queue.
The queue prefers BLE while a GATT session is ready and attempts the configured
internet relay when BLE is unavailable. The five-second foreground timer drains
due messages and uses existing bounded exponential retry metadata. The relay
URL placeholder ending in `.invalid` is deliberately treated as unconfigured.

## Current behavior

- Outgoing messages are persisted before transport attempts.
- Relay submissions reuse the stable application message ID and are idempotent
  while the server still retains the matching queue record.
- Accepted/duplicate relay submissions become `IN_TRANSIT`, never `DELIVERED`.
- Retry attempts, next-attempt time, and last-attempt time are persisted.
- Expired messages become `EXPIRED`; the retry count remains bounded.
- Recipient polling and authenticated envelope acceptance remain separate from
  outgoing route selection.
- Receipts still travel over BLE only in this milestone; relay-based receipt
  delivery is not yet implemented.
- Route selection is foreground/app-timer based, not an OS background service.
- This milestone does not probe connectivity independently; a relay request is
  the practical availability check. When BLE is ready it is preferred, so a
  failing BLE session may delay relay fallback until BLE readiness changes.

## Validation

Added pure unit tests for BLE preference, relay fallback, and no-route behavior.
Flutter tests/analyzer and Android/iOS builds must be run on a configured
Flutter toolchain. Test on two physical devices with BLE unavailable, relay
online/offline, app restart during submission, duplicate relay responses, and
recipient receipts before treating this as reliable delivery.

This remains a prototype. Production readiness requires transport-aware receipt
routing, connectivity monitoring, encrypted database storage, protocol review,
and platform background execution/battery testing.
