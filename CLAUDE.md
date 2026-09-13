# Overcoil — agent/developer guide

`AGENTS.md` is a relative symlink to this file. Keep guidance here, not in duplicate files.
Public source: https://github.com/robbarry/overcoil. No user photos/data or credentials belong in Git.

## Product invariants

Native iPhone, SwiftUI + AVFoundation. The collection is **Watch Box**. `docs/PRODUCT.md`
is the behavioral contract; `docs/ARCHITECTURE.md` and `docs/TESTING.md` cover implementation/proof.
- A timing reading requires in-app capture. Image + actual capture timestamp form one immutable draft.
  Never substitute tap, callback, save, or confirmation time. Capture clock maps through host time
  to a bracketed wall-clock anchor; no uptime comparisons across suspension/reboot/device contexts.
- First successful photo becomes the cover only when no cover exists. Cover crop is independent
  of measurement evidence. Retake/cancel must not create a run or replace a saved cover.
- First reading has offset, not rate. Later pickers suggest last offset plus known drift, frozen
  at capture. Hours/minutes/seconds wrap **independently**—no carrying between fields.
- One active run per watch. Reset/stopped hands start a new run; winding alone doesn't.
- Overall watch rate pools within-run offset changes over summed measured elapsed time. Never
  bridge reset offsets or average run rates without duration weighting. Show evidence counts,
  duration and measurement date on detail screens, not an invented confidence percentage.
  **Watch Box cards stay minimal: photo, name/model, one timing value.** No counts, dates,
  quality badges, active dots, run prompts or “no rate yet” placeholders on the grid.
  Servicing epochs are future work.
- Save stays pinned above the Add/Edit Watch form. Reference cropping has top Save too.
  Watch Box grid items are top-aligned; unequal text lengths must not vertically center the photos.

## Data safety — mandatory

Rob is actively using this app. **Never uninstall, reset, seed fixtures into, or clear his library.**
- Local store: app container `Library/Application Support/Overcoil/store.json` + `images/`.
  `Core/Repository.swift` is the transaction boundary. Files precede atomic manifest commit.
  Failed writes keep prior state. Corrupt/missing data must not silently become an empty library.
- Before updates affecting persistence/sync, take a private backup and verify every referenced
  original/thumbnail plus manifest checksum. Do not commit the backup or copy it into a synced notes vault.
- Existing verified Mac backup is under `~/Library/Application Support/OvercoilDevelopmentBackups/`.
  This checkout's `.build/latest-private-backup-path.txt` points to the exact private directory.
  `.build/backup-phone-library.py` can copy per-photo if directory transfer fails. Do not assume
  those gitignored helpers exist in another clone. No real names/images in public test artifacts.
- Verify retained reading/watch IDs and immutable capture/photo evidence after an update. If no
  concurrent user edits occurred, compare the store byte-for-byte. Never mistake a deliberate new
  reading for a failed equality test. Versions 7 and 8 preserved the existing store byte-for-byte.

## Current delivery state

Installed on the phone: **build 9**, source `ff30d597c736`, including iCloud and the clean grid.
The iCloud worktree/branch is still separate pending the live restore check. Root `main` has the
UI/statistics/docs changes but not iCloud runtime; **do not accidentally downgrade the phone by
building/installing main's older target**. Use `.build/icloud-worktree` for this installed feature set.
Current library upload has been verified from the phone's iCloud status; live isolated restore and
a second physical-device round trip remain unverified. Builds 7, 8 and 9 left the store byte-identical.

## Build/sign/install

Project source of truth: `ios/project.yml`; regenerate with `xcodegen generate --spec ios/project.yml`.
Generated `.xcodeproj` and shared scheme are tracked. Target: iOS 18+, iPhone; no Catalyst/Mac lane.

```sh
xcode-select -p
xcodebuild -version
make setup                  # uv sync --locked (build tooling only)
make simulator              # unsigned simulator build
make device                 # signed device build; does NOT install
make archive                # local archive; does NOT upload
swift test
```

Verified toolchain: Xcode 26.4.1 (17E202), XcodeGen 2.45.4. Never assume selected Xcode stayed unchanged.
Bundle `com.robbarry.overcoil`; team `3XLD352MG9`; automatic signing. Team/bundle IDs are public.

- `scripts/apple.py` reads only ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH from an authorized
  env file. Makefile defaults to the existing Tank `ios/.env` reference, as Rob authorized.
  Override `APPLE_ENV` or `--env-file`; do not print/source/copy secrets for discovery.
- Keychain holds development signing material. Do not export/revoke certificates, wipe accounts,
  bulk-delete profiles, or borrow Tank's restricted devsim signing bridge to fix a local error.
- Xcode account login, developer membership, API-key auth and the user's iCloud account are separate.
  A successful ASC GET proves that route only. A generic authentication failure does not prove a
  bad key or universally unsupported operation. Dott is the existing release/setup reference peer.
- Source stamp uses `ios/Info.plist` + `OVERCOIL_SOURCE_REVISION`; the build helper adds a dirty suffix
  when needed. Arbitrary `INFOPLIST_KEY_...` did not embed the custom stamp reliably. Read final Info.plist.
- Bump CURRENT_PROJECT_VERSION for delivered builds. Commit the tested source, then build cleanly
  for an exact stamp. Separate derived-data paths when independent builds overlap.

```sh
uv run --locked scripts/apple.py device --env-file /absolute/authorized.env \
  --derived-data .build/DeviceDerivedData
xcrun devicectl list devices --json-output .build/devices.json
xcrun devicectl device install app --device rb17 \
  .build/DeviceDerivedData/Build/Products/Debug-iphoneos/Overcoil.app \
  --json-output .build/install.json
xcrun devicectl device info apps --device rb17 --json-output .build/apps.json
xcrun devicectl device process launch --device rb17 com.robbarry.overcoil
```

Resolve `rb17` from live device inventory; don't reuse stale IDs blindly. Use JSON receipts, filter
Overcoil locally (the info-apps filter returned unrelated apps). A locked phone can accept installation
but deny launch. Rob handles unlock/trust/Developer Mode; do not bypass them. A directory-copy transport
reset can occur while individual file copies succeed. Verify at the file/data level, not just exit status.

Before delivery inspect actual app Info.plist, `codesign --verify --deep --strict`, signed entitlements,
and embedded provisioning profile (`security cms -D -i .../embedded.mobileprovision`). Verify exact
bundle/team, build/source, device family, required capabilities and absence of fixture/credential bytes.
Keep prior signed artifacts for rollback; rollback is an in-place install, not data deletion.
Push separately from any merge and verify remote SHA/content. A successful install is not launch,
iCloud upload, physical capture alignment, TestFlight processing, or App Store distribution proof.

## Tests and visual QA

Use explicitly named Overcoil-only simulators. Never mutate/erase a peer's simulator or the real phone.
`make ui-test SIMULATOR_ID=<uuid>` runs native UI tests. Seed the generated icon into that simulator's
Photos library for the native import test (`xcrun simctl addmedia <uuid> ios/Overcoil/Assets.xcassets/AppIcon.appiconset/AppIcon.png`).
- `--ui-testing` synthetic captures exist only in simulator DEBUG builds, use unique per-test local
  stores, and **must never start iCloud sync**. Physical builds exclude these fixture controls.
- Real and simulated cameras share `CameraSurface`. Its dark style is an environment override,
  not presentation-wide `preferredColorScheme(.dark)`; the latter leaked white text onto ivory entry.
  Contrast regression samples rendered pixels after capture/retake, not only text existence.
- Inspect `.xcresult` screenshots. UIKit/Photos accessibility can expose frames while claiming an
  image isn't hittable; the import test uses the live element's measured center, not guessed coordinates.
- Read snapshots before acting. Simulator screenshots via `simctl io` require absolute output paths
  here. Core Graphics generates the app icon; visually verify regeneration (an earlier 24-bit AppKit
  bitmap context produced a black image despite command success).
- Capture alignment still needs physical validation against a validated visible clock, including
  low light/moving hands/torch. Timestamp metadata alone is not a certified accuracy bound.

## iCloud Drive

Container `iCloud.com.robbarry.overcoil`, CloudDocuments. Both iCloud-container and ubiquity-container
entitlements must name it. Visible-folder metadata is in `NSUbiquitousContainers`; bump build version
when changing that metadata. Verify signed app/profile, not only the source entitlements.
Rob's Xcode sign-in enabled registration/association/profile provisioning; subsequent API-key builds
worked. Keep changes Overcoil-only. No CloudKit schema or Mac app is required for the document approach.

The iCloud feature is on `feature/icloud-drive-sync` (worktree `.build/icloud-worktree`) until live
verification is complete. `docs/ICLOUD-WIP.md` and `docs/icloud-verification.json` on that branch are the
implementation/receipt references. Main has the independently shipped UI/statistics work.

- Shared `Library.overcoil.json` contains full-precision records, readable inspection summaries and
  checksums. `Photos/`, `Thumbnails/`, `Recovery/` are browsable in Finder → iCloud Drive → Overcoil.
- New empty installations restore; an empty/missing cloud folder must not replace existing local
  timings. Baseline/revision checks detect divergent edits. Imports validate all photos and unchanged
  local revision, keep recovery copies, and wait for open edits to finish.
- Account switches require confirmation. Cloud snapshot writes are coordinated/atomic, after photos.
  Never derive I/O destinations from unrelated metadata-query results. Never label a local Drive write
  an upload: require Apple's uploaded state AND checksum verification. Original photos/recovery versions
  are retained; do not add cloud garbage collection without an explicit preservation/deletion policy.
- Settings includes a safe restore check into a separate local repository. It never resets the real
  library. Debug launch argument `--verify-icloud-restore` requests it after upload; otherwise use the
  Settings button. Actual second physical-device sync is separate from this isolated restore check.
- Private diagnostics: `cloud-status.json` and `sync-restore-check.json` in the app's local store folder.
  Copy them to private storage to inspect; never publish account archives, user data or raw device logs.

At the last live check the phone reported the current Watch Box/photos uploaded to iCloud Drive.
The live isolated-restore receipt was still absent. Recheck rather than treating that negative as permanent.
The user's real timings have a verified private backup. Preserve that boundary while finishing verification.
