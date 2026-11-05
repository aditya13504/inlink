# M2.6 — First local conversation flow

## Included
- Conversation screen accessible from the home toolbar.
- Select from verified contacts.
- Outgoing text is encrypted using `VerifiedMessageService` and stored as a local `QUEUED` message with its encoded envelope.
- Incoming envelope can be pasted for prototype testing; sender key pinning, signature verification, decryption and replay rejection run before plaintext is stored.
- Message records persist through the platform secure-storage plugin with a 200-message cap.
- Outgoing envelope can be viewed for manual transfer between test devices.
- Local message model serialization tests.

## Explicit limitations
- No transport delivery is wired. `QUEUED` is truthful; the UI must not claim sent/delivered.
- This is manual envelope transfer, not a functional chat network.
- Secure storage is not a scalable message database. It may have platform-specific size limits; use a proper encrypted database for a larger history.
- Outgoing message text is stored locally in OS-backed secure storage, but no database-level transaction with envelope creation exists.
- Message IDs in this prototype are local identifiers, not protocol-level message IDs.
- Incoming import is manual; background inbound delivery and ordered processing are not implemented.
- The E2EE design is still a prototype and needs independent review / reviewed protocol adoption before production.

## Validation
From `app/` run `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build apk --debug`.
On two physical devices, independently verify fingerprints, exchange an encrypted envelope through a separate channel, import it under the sender contact, and verify the same envelope is rejected on a second import.
