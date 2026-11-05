#!/usr/bin/env python3
"""Focused repository guardrails for InLink M13; not a general-purpose security scanner."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []

def require(condition: bool, message: str) -> None:
    if not condition:
        ERRORS.append(message)

security = (ROOT / "SECURITY.md").read_text(encoding="utf-8")
baseline = (ROOT / "docs/security/m13-security-baseline.md").read_text(encoding="utf-8")
closure = (ROOT / "docs/release/m13-security-release-hardening-closure.md").read_text(encoding="utf-8")
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/security.yml").read_text(encoding="utf-8")
relay = (ROOT / "relay/app/main.py").read_text(encoding="utf-8")

for phrase in (
    "Do not use it for emergency",
    "independent security review",
    "production release is blocked",
    "private channel",
):
    require(phrase.lower() in security.lower(), f"SECURITY.md must include: {phrase}")

for phrase in (
    "NOT APPROVED for production",
    "physical",
    "independent security review",
    "pip-audit",
    "Bandit",
):
    require(phrase.lower() in baseline.lower(), f"Security baseline must include: {phrase}")

for pattern in (r"(?m)^permissions:\s*$", r"contents:\s*read", r"validate_m13_security\.py",
                r"bandit .*relay/app", r"pip-audit -r relay/requirements\.txt",
                r"python -m pytest -q relay/tests"):
    require(re.search(pattern, workflow) is not None, f"Security workflow missing guard: {pattern}")

for entry in (".env", "*.jks", "*.keystore", "*.p12", "*.mobileprovision", "secrets/"):
    require(entry in gitignore, f".gitignore must exclude {entry}")

# Guard against accidentally removing relay bounds while evolving this source.
for token in ("MAX_ENVELOPE_BYTES", "MAX_MAILBOX_ITEMS", "MAX_TTL_SECONDS",
              "CLOCK_SKEW_SECONDS", "reserve_request_nonce", "InvalidSignature"):
    require(token in relay, f"Relay security invariant marker missing: {token}")

for rel in (
    "docs/security/m13-security-baseline.md",
    "docs/testing/m13-security-release-hardening.md",
    "docs/release/m13-security-release-hardening-closure.md",
    ".github/workflows/security.yml",
):
    require((ROOT / rel).is_file(), f"Required M13 file missing: {rel}")

require("No production or public-beta security approval" in closure, "M13 closure must state production is not approved")
require("No production or public-beta security approval" in closure,
        "M13 closure must avoid implying security certification")

if ERRORS:
    print("M13 security baseline: FAIL")
    for error in ERRORS:
        print(f" - {error}")
    sys.exit(1)

print("M13 security baseline: PASS")
print("Note: focused source guardrails only; not a security audit or secret scanner.")
