# M4.4 — Storage lifecycle reliability

## Change in this milestone

`LocalMessageRepository.close()` now enters the same serialized mutation queue
as `add()` and `update()`. A mutation accepted before `close()` therefore
finishes before the connection is closed, rather than racing the close call.
Operations queued after close may reopen the database.

## Required executable test cases

These tests require Flutter/Dart plus a compatible SQLCipher test environment;
they are specified here but have **not** been executed in this packaging
environment.

1. **Queued add then close:** pause the insert transaction, call `close()`,
   release the insert, and assert close completes afterward.
2. **Queued update then close:** assert status/retry metadata is committed
   before close resolves.
3. **Reopen after close:** add a record, close, list after reopen, and compare
   the full persisted record.
4. **Duplicate concurrent add:** concurrently add equal peer/direction/ID
   records; assert one visible row.
5. **Same ID, different peer:** add records for two peers with the same ID;
   assert both remain visible.
6. **Migration rollback:** force one legacy record to fail conversion; assert
   no partial import is visible and the legacy secure-storage key remains.
7. **Key loss / wrong key:** assert the repository reports an error and never
   silently replaces an existing encrypted database with an empty database.
8. **Retention cap:** insert beyond `maxMessages`; assert the cap is respected.

## Run on a configured Flutter host

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

A SQLCipher integration test should use a disposable database path and a
test-only secure-storage implementation. If native SQLCipher cannot run in the
unit-test environment, keep pure Dart record tests separate from on-device
integration tests and do not label the latter as passed.

## Status

- [x] Serialize database close with repository mutations.
- [x] Document the lifecycle/migration regression test matrix.
- [ ] Add and run database-backed Flutter tests.
- [ ] Resolve dependencies and run analyzer/test/build on a configured host.
- [ ] Verify lifecycle behavior on Android and iOS devices.
