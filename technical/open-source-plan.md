# Open-Sourcing Plan (Updated)

_Last refreshed: 2025-11-11_

## Status Snapshot
- ✅ CI/CD (GitHub Actions + Xcode Cloud) now green with `scripts/ensure-config.sh` generating `Config.plist`.
- ✅ Contribution collateral (CONTRIBUTING, Code of Conduct, Security policy, issue/PR templates) drafted and moved to the `contribution-guides` branch for review before landing on `main`.
- ⏳ Screenshots/demo assets still outstanding; capture workflow documented but final images/videos not yet produced.
- ⏳ History re-clone + full secret scan still pending before any public tag/release.
- ⏳ Public “v1.0.0-oss” release checklist (tagging, announcement, issue triage) still to be completed after docs/assets settle.

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
- ⏳ Next: re-clone into a temp directory, re-run the secret scanners on history, and then force-push (`git push --force-with-lease --all` + `git push --force --tags`) once validated. Communicate the rewrite to any collaborators.

## 4. Configuration Strategy
- ✅ Keep non-sensitive build metadata (team ID, bundle IDs) in repo so existing targets build out of the box.
- ✅ Provide `CareKeeper/Shared/Config.default.plist` plus `scripts/ensure-config.sh` to materialize `Config.plist` from env vars (CI already wired).
- 💤 Optional: add `.xcconfig` templates for additional per-environment values if new secrets ever emerge (none outstanding today).
- ✅ README now calls out the need to replace CloudKit/App Group IDs locally and documents the generation script.

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
- ✅ SwiftFormat + SwiftLint configs added, pre-commit hook + README updated.
- ✅ GitHub Actions workflow (`.github/workflows/ci.yml`) now runs `swiftformat --lint`, `swiftlint --strict`, `git secrets --scan`, `gitleaks detect`, `trufflehog filesystem`, and `xcodebuild clean build test` on every push/PR, and it generates `Config.plist` from env vars via `scripts/ensure-config.sh`.

## 9. Community & Governance
- ✅ Drafted CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md, and PR/issue templates (present on `contribution-guides` branch awaiting review). Includes instructions to run hooks (`git config core.hooksPath .githooks`).
- 💤 Optional: tag “good first issue” tickets if we ever expect outside contributors. Currently deprioritized because the repo is still largely a solo effort.

- Final secret scan across history (git-secrets, gitleaks, trufflehog) on a clean re-clone.
- Tag release (e.g., `v1.0.0-oss`) with notes about requirements (Apple Dev account, personal CloudKit container).
- Monitor issues for 24–48h post-launch.

## Pitfalls to Avoid
- Accidentally shipping production CloudKit/App Group IDs, provisioning profiles, or archived builds.
- Including personal `.xcuserstate`/DerivedData/log files or screenshots with real people.
- Forgetting to scrub any future secrets after history rewrite.

## 11. Visual Assets & Screenshots
- ✅ Documented the simulator capture workflow in `technical/screenshot-workflow.md` (boot commands, status bar overrides, `simctl io screenshot`, watch capture tips).
- ⏳ Capture the final set of iOS + watch screenshots/GIFs once demo data/story copy is locked and add them to README/docs. Also consider a short demo video for the README landing section.

## Portfolio Polish
- Highlight the selective CloudKit + watch caching approach, log streaming/diagnostics, and ADR-driven architecture decisions.
- Include short demo video/GIFs if possible to showcase UX.
- Maintain a tidy issue tracker to demonstrate stewardship.

---

### Outstanding Inputs / Clarifications
- ✅ History rewrite approval received; initial scrub completed.
- ✅ License: MIT.
- ✅ CI scope implemented via GitHub Actions workflow.
- ⏳ Screenshots/GIF capture timeline—confirm when to capture the final assets (per `technical/screenshot-workflow.md`) or whether to leave placeholders for now.
- ⏳ Release/announcement plan once contributions + screenshots merge back to `main`.
