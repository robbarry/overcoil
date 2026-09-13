# Overcoil

Native iPhone watch timing journal. Watch Box → photograph a dial → enter the
frozen watch time → measure seconds gained or lost per day. Local-first, with optional two-way iCloud Drive sync and no developer
backend or automatic dial reading. See [product behavior](docs/PRODUCT.md)
and [engineering notes](docs/ARCHITECTURE.md).

## Build on Pollux

Prerequisites: selected Xcode with iOS SDK, XcodeGen, uv. Run `xcode-select -p`
before building; initial verification used Xcode 26.4.1 (17E202).

```sh
make setup
make simulator       # No Apple credentials required
make device          # Signed iPhone build; does NOT install
make archive         # Local Release archive; does NOT upload
open ios/Overcoil.xcodeproj
```

`ios/project.yml` is the project source of truth. `make generate` regenerates the
generated Xcode project. Current target: iOS 18+, iPhone portrait, version 0.1.0. Build numbers are in the
project spec. Camera permission is requested only when opening capture.

The iCloud implementation is described in [iCloud sync](docs/ICLOUD-WIP.md).
It uses the device's own iCloud account, preserves a local offline copy, and detects
conflicting edits. Finder access needs no Mac app. Physical verification is recorded
separately from simulated/unit-test evidence.

## Apple configuration

- App: **Overcoil**; bundle: **com.robbarry.overcoil**.
- Team: **3XLD352MG9**; signing: **Automatic**.
- Device family: iPhone only; Catalyst, Mac-designed-for-iPhone, and XR disabled.
- Developer identifier record: **A9662M58TU**, created/read back September 13, 2026.
  Apple returns its identifier platform as `UNIVERSAL`; the Xcode target is iOS,
  iPhone only. No extra capabilities have been requested.
- Rob authorized reuse of the existing team and credentials. The Makefile reads
  only the three `ASC_*` credential references from Tank's local `ios/.env` by
  default. It does not copy that file or embed credentials into the application.
- Override with `make device APPLE_ENV=/absolute/path/to/authorized.env`, or provide
  `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` in the process environment.
  `ios/.env.example` documents the schema; actual env/key files stay untracked.
- Development signing uses Pollux's existing Apple Development Keychain identity.
  Xcode currently chooses the existing general team wildcard development profile;
  the app's actual signed application identifier is the exact Overcoil identifier.
  This is not Tank's restricted devsim signing bridge. No certificates were
  exported, revoked, or manually imported.
- Build commands allow Xcode automatic provisioning updates for this target.
  They do not register new devices, assign testers, export distribution packages,
  upload builds, or mutate another app's configuration.

`make apple-status` reads back Overcoil's identifier and App Store Connect record.
`uv run scripts/apple.py register --env-file /path/to/authorized.env` creates the
identifier only when the exact identifier is absent. It never creates an ASC app.

## Remaining release setup

An App Store Connect app record has **not** been created; initial API lookup found
none for this bundle. It is not required for local development. Create the iOS
record named Overcoil in App Store Connect before the first TestFlight upload
(proposed SKU `overcoil-ios`; confirm primary language then). Apple's public
[Apps API documentation](https://developer.apple.com/documentation/appstoreconnectapi/apps)
directs new-app creation to the website.

App Store release build-number allocation, distribution export, and TestFlight
groups remain future work; this project is currently for local device testing. Do not claim a local development signature proves App Store
distribution or installation. No release scripts from Tank have been copied or run.

Run `swift test` for core tests. Native UI tests are described in the engineering
notes. **Physical capture alignment remains unvalidated**; the app makes no
certified accuracy claim.

Build artifacts and logs live under gitignored `.build/`. Keep credentials out of
logs and shared transcripts. Rob authorized public source hosting at
`https://github.com/robbarry/overcoil`; never add real watch/photo data to the repo.

Measured bootstrap results are recorded in
`docs/provisioning-verification-2026-09-13.json`: simulator build, signed iPhone
build, and local Release archive passed; exact signed identifiers, iPhone-only
device family, embedded profiles, and signatures were checked. No on-device UI
test or distribution export has been performed.
