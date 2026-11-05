#!/usr/bin/env python3
"""M14 beta readiness source guardrails; intentionally does not claim a release is ready."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []

def require(ok, message):
    if not ok:
        errors.append(message)

required_files = [
    "docs/beta/m14-beta-deployment-plan.md",
    "docs/beta/m14-android-beta-distribution.md",
    "docs/beta/m14-ios-testflight-runbook.md",
    "docs/beta/m14-tester-consent-and-privacy.md",
    "docs/beta/m14-feedback-and-bug-report.md",
    "docs/beta/m14-operations-and-monitoring.md",
    "docs/beta/m14-release-record-template.md",
    "docs/release/m14-beta-deployment-closure.md",
]
for rel in required_files:
    require((ROOT / rel).is_file(), f"Required M14 file missing: {rel}")

plan = (ROOT / "docs/beta/m14-beta-deployment-plan.md").read_text(encoding="utf-8")
ios = (ROOT / "docs/beta/m14-ios-testflight-runbook.md").read_text(encoding="utf-8")
privacy = (ROOT / "docs/beta/m14-tester-consent-and-privacy.md").read_text(encoding="utf-8")
ops = (ROOT / "docs/beta/m14-operations-and-monitoring.md").read_text(encoding="utf-8")
closure = (ROOT / "docs/release/m14-beta-deployment-closure.md").read_text(encoding="utf-8")

for phrase in ("Do not invite external testers", "authenticated delivery receipt",
               "critical/high", "Rollback / pause triggers"):
    require((phrase.lower() in plan.lower()) or (phrase == "authenticated delivery receipt" and "recipient receipt" in plan.lower()), f"Beta plan missing safety gate: {phrase}")
require("complete generated Xcode project/workspace" in ios,
        "iOS runbook must state the Xcode project/workspace blocker")
require("not a claim that testflight" in ios.lower(),
        "iOS runbook must not imply TestFlight readiness")
require("physical ios" in ios.lower(),
        "iOS runbook must require testing on physical iOS devices")
for phrase in ("not been independently audited", "Feedback/security contact", "stop testing"):
    require(phrase.lower() in privacy.lower(), f"Tester notice missing: {phrase}")
for phrase in ("Never log", "Pause beta expansion", "rollback"):
    require(phrase.lower() in ops.lower(), f"Operations guide missing: {phrase}")
require("NOT APPROVED" in closure, "M14 closure must state beta deployment is not yet approved")
require("does not publish a build" in closure.lower(), "M14 closure must not imply an actual store release")

# Ensure security CI continues to run M13 gate and M14 guardrail.
workflow_path = ROOT / ".github/workflows/security.yml"
require(workflow_path.exists(), "Security workflow missing")
if workflow_path.exists():
    workflow = workflow_path.read_text(encoding="utf-8")
    require("validate_m13_security.py" in workflow, "Security workflow dropped M13 validator")

# The source validator intentionally does not inspect or claim store credentials, signing, or builds.
if errors:
    print("M14 beta readiness source checks: FAIL")
    for e in errors:
        print(f" - {e}")
    sys.exit(1)

print("M14 beta readiness source checks: PASS")
print("This is a documentation/source guardrail, not proof of build, store, device, or security readiness.")
