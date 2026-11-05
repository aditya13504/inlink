# M4.3 — Storage migration validation and recovery

This milestone fixes two source-level hazards found while preparing storage
validation: SQLCipher/path imports were positioned after Dart declarations, and
a failed database open/migration could leave a cached failed future or open
database handle. Imports now live in the directive section; failed opens reset
the cached future and close the database while preserving the legacy JSON blob.

## Manual migration test matrix

Use a disposable app install and test data only. Record OS, device, package
versions, app version, and whether the process was force-stopped.

| Case | Setup | Expected result |
|---|---|---|
| Fresh install | No DB and no legacy blob | Encrypted DB opens and message list is empty |
| Legacy migration | Valid v1/v2/v3 JSON message records | All valid records migrate and preserve status, expiry, retry metadata and envelope |
| Duplicate legacy rows | Same peer/direction/message ID more than once | Unique DB index keeps one visible record |
| Invalid JSON | Legacy blob is malformed | Open fails safely; legacy blob remains; repair/reinstall path is documented |
| Invalid record | One record fails validation | Transaction rolls back; legacy blob remains intact |
| Interrupted migration | Force-stop during import on a test build | Next open retries; no partial visible migration or legacy deletion |
| Concurrent add | Submit same message from two async calls | One DB row for the peer/direction/message ID |
| Concurrent update | Update retry/status metadata while listing | No lost committed update |
| Restart | Close and reopen DB | Messages and delivery metadata persist |
| Wrong key | Test-only wrong DB key | Open fails; app must not silently replace key or create an empty DB |
| Retention bound | Insert over maxMessages | Only newest configured count remains |

## Validation commands

From `app/` on a configured Flutter machine:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

For a release candidate, repeat on supported iOS tooling and real devices. Add
automated database tests with an isolated temporary database and a mock secure
storage implementation before treating this milestone as complete.

## Status

Source-level fixes and this test matrix are included. The environment used to
package this milestone does not provide Flutter/Dart, so Flutter analysis,
automated mobile tests, dependency resolution, and builds remain **not run**.
