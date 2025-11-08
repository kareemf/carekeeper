# Open-Sourcing Plan (Updated)

## 1. Scope & Goals
- Publish the full CareKeeper codebase (iOS + watch targets, shared services, docs) while keeping only non-sensitive build metadata (e.g., team ID, bundle IDs) so contributors can compile existing targets.
- Present the project as a portfolio-quality showcase that highlights the watch caching strategy, selective CloudKit queries, and diagnostics/logging work.
- Explicitly exclude only sensitive artifacts (credentials, private logs, personal media)—icon assets are safe to keep.

## 2. Sanitize Current Workspace
- Run automated scanners on both working tree and entire history:
  - `git-secrets --scan`
  - `gitleaks detect --report-format sarif --report-path build/gitleaks.sarif`
  - `trufflehog git file://. --json` (or latest CLI syntax)
- Manually inspect files likely to hold secrets: Swift sources, scripts, `.xcconfig`, `.plist`, `technical/` logs.
- Remove/ignore local-only artifacts before history work: `.claude/settings.local.json`, `DerivedData/`, `build/`, `*.ipa`, `*.xcarchive`, crash logs, `.xcworkspace/xcuserdata`, provisioning profiles, `.env`/`.mobileprovision`, diagnostic dumps.
- Verify unit/UI tests only use fabricated data (current state confirmed) and keep it that way.

## 3. History Hygiene
- ✅ Ran `git filter-repo --invert-paths --path .claude/settings.local.json` (2025-??-??) to scrub the Claude settings file from history. Remote `origin` was re-added afterward.
- Next: re-clone into a temp directory, re-run the secret scanners, and then force-push (`git push --force-with-lease --all` + `git push --force --tags`) once validated. Communicate the rewrite to any collaborators.

## 4. Configuration Strategy
- Keep non-sensitive build metadata (team ID, bundle IDs) in repo so existing targets build out of the box.
- Add `.xcconfig` templates for CloudKit container ID, App Group ID, and any other environment-specific values; ship them with placeholder/sample values plus instructions on how to create personal containers.
- Document in README that CloudKit/App Group IDs must be replaced locally; do not publish production IDs even if the template contains sample strings.

- Confirm icon/font/licensed assets are cleared (only built-in icon used today).
- Adopt the MIT License (per latest guidance) and add LICENSE, headers/NOTICE where required.
- Ensure no private SDK references remain; stub or document any optional integrations.

- Refresh README with: feature overview, architecture summary, watch caching/log streaming highlights, screenshots/GIFs, and onboarding steps (including hook setup, CloudKit/App Group instructions). Capture sanitized simulator screenshots if possible; otherwise leave placeholders for manual capture.
- Link out to ADRs/specs in `technical/` and add a privacy statement clarifying the sample/demo data.

## 7. Security & Privacy Review
- Strip crash logs or diagnostics that contain device IDs/account info.
- Reconfirm sample fixtures contain only fictional data.
- Document how public bundle IDs/team IDs relate to personal setups (why they compile but still require developer accounts).

## 8. Testing & Build Instructions
- Verify `xcodebuild` commands succeed from a clean clone; script them (and simulator install steps) in README.
- Add GitHub Actions CI that runs: unit tests + `git-secrets`, `gitleaks`, `trufflehog` scans (matching the initial audit tooling). If we later add a linter, ensure it’s both a pre-commit step and documented in README.

## 9. Community & Governance
- Add CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md, and PR/issue templates; include instructions to run hooks (`git config core.hooksPath .githooks`).
- Tag a few "good first issue" tasks after launch to show community readiness.

- Final secret scan across history (git-secrets, gitleaks, trufflehog) on a clean re-clone.
- Tag release (e.g., `v1.0.0-oss`) with notes about requirements (Apple Dev account, personal CloudKit container).
- Monitor issues for 24–48h post-launch.

## Pitfalls to Avoid
- Accidentally shipping production CloudKit/App Group IDs, provisioning profiles, or archived builds.
- Including personal `.xcuserstate`/DerivedData/log files or screenshots with real people.
- Forgetting to scrub any future secrets after history rewrite.

## Portfolio Polish
- Highlight the selective CloudKit + watch caching approach, log streaming/diagnostics, and ADR-driven architecture decisions.
- Include short demo video/GIFs if possible to showcase UX.
- Maintain a tidy issue tracker to demonstrate stewardship.

---

### Outstanding Inputs / Clarifications
- ✅ History rewrite approval received; initial scrub completed. Need to re-clone + verify before force-push.
- ✅ License: MIT.
- ✅ Screenshots: I’ll capture via simulators if feasible; otherwise you’ll take over (TBD once tooling is ready).
- ✅ CI scope: run unit tests plus git-secrets/gitleaks/trufflehog in GitHub Actions. No linter today; if one is added it must run in pre-commit + README.
- Remaining: confirm whether you want me to proceed with simulator screenshot capture now or leave it pending; also confirm timing for force-pushing the rewritten history after validation.
