# Protocol test vectors

Add cross-platform test vectors before implementing production packet serialization.

Vectors should cover:
- valid envelope encode/decode;
- maximum and over-limit fields;
- unknown protocol versions;
- malformed encodings;
- duplicate message IDs;
- expired messages;
- invalid/tampered authentication tags;
- mismatched recipient keys;
- authenticated delivery receipts.
