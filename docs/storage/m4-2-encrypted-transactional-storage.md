# M4.2 — Encrypted transactional message persistence

## Implementation

- Replaces the message JSON blob as the primary store with SQLCipher-backed
  SQLite via `sqflite_sqlcipher`.
- Generates a random 256-bit database key and stores it in platform secure
  storage.
- Adds a unique index on normalized peer fingerprint, direction, and message ID
  to make duplicate insertion idempotent at the database layer.
- Uses transactions for legacy import and bounded-history pruning.
- Keeps the legacy secure-storage JSON value until import commits; if migration
  fails, the old value remains available for retry/recovery.
- Retains the 200-message bound and existing message JSON serialization format
  inside encrypted database rows to minimize migration risk.

## Important operational notes

This is a first migration implementation, not a production-certified database
layer. The `sqflite_sqlcipher` dependency must resolve on both target platforms,
and Android/iOS builds must be checked on their supported toolchains. Back up
and test migration on copies of real legacy data before release. A database
key loss makes the encrypted database unreadable; key recovery policy must be
designed before public beta.

## Validation checklist

From `app/`:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Verify migration from no data, valid legacy JSON, duplicate legacy rows, malformed
legacy JSON, process termination during migration, database key loss, and
reopening after process restart. Ensure malformed legacy data is not deleted.

No Flutter/Dart toolchain or mobile devices were available in the build
environment, so mobile tests/builds have not been run here.
