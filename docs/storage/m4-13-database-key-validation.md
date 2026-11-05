# M4.13 — Database key validation and fail-closed behavior

## Problem

The repository previously treated any malformed non-null SQLCipher key as if no
key existed. It then generated and persisted a replacement key. If a database
already existed, silently replacing the key could make it unreadable and obscure
the original storage/key problem.

## Change

- Added `validateExistingDatabaseKey`, a small pure validator.
- A missing key still means first launch and permits secure random key creation.
- A present key must be 43 base64url characters (the unpadded encoding of 32 bytes).
- A malformed present key raises `FormatException`; it is not overwritten.
- Added unit tests for missing, valid, short, padded, and invalid-character keys.

## Validation status

The Flutter unit tests are added but cannot be executed in this environment because
Flutter and Dart are not installed. Run `./scripts/verify_flutter.sh` or the
`Flutter checks` GitHub Actions workflow to compile and execute them. The relay
suite and source-level checks are run separately when packaging this milestone.

## Recovery guidance

Do not automatically reset or delete the encrypted database after a key error.
Preserve the database and secure-storage state for diagnosis; recovery may require
a backup or user-confirmed reset and can otherwise cause irreversible message loss.
