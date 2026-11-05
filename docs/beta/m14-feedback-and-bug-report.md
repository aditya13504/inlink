# Beta Feedback and Bug Report Template

Do not include message text, private keys, passwords, tokens, personal contact lists, or raw databases.

## Bug report

- Report ID:
- Date/time and timezone:
- App version/build:
- Commit (if known):
- Platform/device model/OS:
- Network path: BLE / relay / both / unknown
- Reproduction frequency: always / often / sometimes / once
- Preconditions (test identities only):
- Steps to reproduce:
- Expected behavior:
- Actual behavior:
- Impact: blocker / major / normal / minor
- Does this involve identity, message integrity, privacy, or secrets? yes / no / unsure
- Redacted logs or screenshots:
- Workaround (if any):

## Messaging and delivery report

- Sender test ID:
- Recipient test ID:
- Path used:
- Sender displayed state:
- Authenticated recipient receipt observed? yes / no / unknown
- Duplicate, missing, reordered, or delayed message?:
- Radio/network transitions performed:
- Restart/reconnect behavior:
- Reproduction notes:

## Triage rules

Treat suspected key/plaintext exposure, identity spoofing, message-integrity failure, or false
recipient-delivery confirmation as a private security report and a release-stop trigger. Do not ask
testers to attach databases, key material, or full unredacted protocol traces.
