# Engineering notes

- `ios/project.yml`: reproducible XcodeGen source. `Overcoil` is the only shipping
  target; `OvercoilUITests` is a simulator test runner, not a provisioned app resource.
- `Core/Models.swift`: Codable value model, fixed-offset date interpretation,
  first-to-latest rate, display rounding, and pure clock-anchor mapping.
- `Core/ReadingPrefill.swift`: predicts watch time from the last observed offset,
  adding elapsed measured drift once at least two prior valid readings exist.
  Suggestions never mutate reference instants or count as observations. No historical
  reading after the new capture instant participates; compromised clocks fall back
  to capture-time phone values.
- `Core/Repository.swift`: single-owner transaction boundary. Files commit before
  the one JSON manifest; visible state changes only after successful manifest commit.
  Atomic file replacement uses temporary file → synchronize → rename. No in-place
  datastore migrations. `beforeManifestWrite` enables failure injection in tests.
  Whole-run deletion removes the run and its readings in one commit, retaining
  photos referenced by covers or surviving readings. Only the deleted readings'
  unreferenced assets are removed, after the commit succeeds. Existing reading
  deletion likewise removes an emptied run. Neither operation changes other runs
  or clears clock-compromise flags; statistics derive from remaining evidence.
- `Services/AppStore.swift`: main-actor observable adapter, bounded image cache,
  native image import/thumbnail/orientation normalization. Original bytes retained.
- `Services/CaptureService.swift`: serial camera queue; rear autofocus-capable ultra-wide camera when its reported minimum focus distance
  is shorter (and at most 100 mm), otherwise the wide-angle camera; no audio input, JPEG/speed priority, flash off, no Live Photo. Close-up mode uses 2× digital zoom
  on the ultra-wide sensor; tap-to-focus maps preview points into camera coordinates.
  Lens type, zoom, and minimum focus distance are saved with capture diagnostics. Native
  `AVCapturePhoto.timestamp` converts from `session.synchronizationClock` to host
  time via `CMSyncConvertTime`. Bracketed wall/host anchor maps the exposure timestamp
  to a wall-clock reference; callback/save/tap times are not substituted. Metadata
  keeps raw CMTime fields, anchor and residual for later alignment investigation.
  A request-ID guard rejects late callbacks after a 25-second capture timeout.
- `ClockContinuity`: locked process-local token and anchor. Resets on background.
  No persistent uptime comparisons. Detected discontinuities suppress the entire
  run's headline while keeping all observations. Undetected corrections remain a
  stated limitation, including changes outside a continuous foreground context.
- `Core/TimeWheelMath.swift` and `Views/CyclicTimePicker.swift`: repeated native
  UIKit picker rows re-center after selection, allowing independent looping fields.
  Selection changes only that field; seconds do not carry into minutes. VoiceOver
  component labels identify hour/minute/second; wheel fonts/row heights scale.
- `Views/`: Watch Box, details, capture, frozen entry, runs/history/reading correction,
  reference-photo selection/crop and Settings. Camera dark appearance is scoped with
  an environment override, never a presentation-wide preferred-color-scheme change.
  Ivory time entry explicitly uses light appearance and dark ink. The simulator
  camera uses the same appearance modifier, so camera→entry/retake tests catch leaks.
  Normal time entry is a fitted, non-scrolling vertical layout with an adaptive photo
  height and a compact footer. AM/PM is outside the footer; date/zone and reading tips
  open separate sheets. Accessibility sizes use a full-page scroll without an overlay. Crops use normalized center and a
  side fraction of the shorter orientation-corrected image edge.
- `SimulatorFixture.swift`: `targetEnvironment(simulator) && DEBUG` only, gated by
  `--ui-testing`. Clearly labeled synthetic dial and fixed timestamps. It is not
  compiled into physical-device builds and does not validate actual capture.
  UI tests use a separate UUID-named Application Support directory; real data is
  never reset to run a test. Fixtures never preload production collections.

## Tests

`swift test` runs pure calculation/calendar/storage tests on macOS. App's code uses
no third-party runtime dependencies. Python cryptography is a build-tool dependency
only and is not bundled.

```sh
xcodegen generate --spec ios/project.yml
xcodebuild -project ios/Overcoil.xcodeproj -scheme Overcoil \
  -destination 'platform=iOS Simulator,id=YOUR_OVERCOIL_SIMULATOR_UUID' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
```

UI tests drive native buttons and picker wheels, save actual synthetic image files,
terminate/relaunch, and inspect rendered rates and history. Test attachments are
local `.xcresult` artifacts. Synthetic evidence is distinct from device-camera proof. Camera-denied UI testing
injects a denied authorization result only in simulator DEBUG builds; it does not
claim to exercise Apple's physical permission prompt. For the Photos import test,
seed only the dedicated simulator library with the generated app icon:

```sh
xcrun simctl addmedia YOUR_OVERCOIL_SIMULATOR_UUID ios/Overcoil/Assets.xcassets/AppIcon.appiconset/AppIcon.png
make ui-test SIMULATOR_ID=YOUR_OVERCOIL_SIMULATOR_UUID
```

## Privacy and release boundaries

No app-side networking/analytics, user defaults, microphone, location, or broad
Photos authorization. PhotosPicker can download the user's chosen iCloud photo via
Apple; Overcoil copies the result locally and does not transmit it. Privacy manifest
reports no collection or tracking. Direct timing APIs are CoreMedia clocks, not
`systemUptime`/`mach_absolute_time`; re-audit required-reason declarations when adding
APIs or SDKs. The ordinary device backup policy still applies to Application Support.

Never commit env files, keys, provisioning profiles, local device identifiers,
real watch photos, user databases, or unreviewed diagnostics. Keep device receipts
under `.build/`; publish only deliberately sanitized verification summaries.

## Watch identity (build 10)

The editable identity is **brand**, **model**, and **optional nickname**. A title is
nickname → brand → model; at least one must be nonblank. Grid cards show that title
and model without duplicating a model-only title. Brand and model are independent
of the UUID identifying the physical watch; identical watches remain distinct.

Additive persistence: `nickname == nil` marks a legacy record and preserves its
old `name` verbatim, without guessing brand/model splits. Empty nickname explicitly
selects the derived title. The schema-1 `name` remains a compatibility title written
by `normalizeIdentity()` at save; UI and inspection summaries use `displayName`.
Untouched legacy decoding/re-encoding preserves the canonical cloud revision. New
nickname-bearing cloud snapshots require build 10+ on other installations: old
builds cannot validate the extra fields in their canonical hash and must be upgraded,
not used to overwrite the newer library. No capture or measurement schema changes.

Developer identity correction uses a private `WatchIdentityCorrections` request,
exact watch IDs and expected old identity fields. The repository validates the entire
batch before one atomic commit and saves the exact prior manifest to local
`IdentityRecovery/`. It can change only identity; notes, photo links, crops, runs,
readings and timing evidence are preserved. Already-applied requests are idempotent;
stale, duplicate, invalid or missing targets reject the whole batch. A write failure
keeps the previous database and the backup. No user inventory is embedded in code.
