# iCloud work in progress — not in the installed app

Rob clarified the requirement: a browsable iCloud Drive folder holding the complete
library and original photos, automatic two-way sync between Overcoil installations,
and restoration on a new installation signed into the same iCloud account. Not a
one-way export. No Mac app is currently requested; Finder access remains possible.

This branch is groundwork only, not an enabled sync feature. It contains:
- Overcoil-only iCloud Documents entitlements / visible container metadata.
- `CloudLibrary`: full-precision native records, original/thumbnail SHA256 manifests,
  safe filenames, readable UTC/offset inspection rows, and revision validation.
- Pure baseline/local/remote sync decisions: upload, download, unchanged, initial
  empty, conflict, or missing cloud library. Divergent edits must not be overwritten.
- A guarded repository import that validates every photo and the still-current local
  revision, retains a local recovery copy, then atomically commits imported records.

Still required: coordinated iCloud file I/O, metadata discovery/upload status,
account-switch protection, automatic scheduling, safe conflict UI/recovery,
first-launch restore integration, multi-replica tests, and physical iCloud verification.
The local database remains the offline working copy. Proposed shared document:
`Library.overcoil.json`, immutable `Photos/` and `Thumbnails/`, plus recovery versions.
Never treat callback success or local iCloud-container writes as confirmed uploads.

## Signing blocker (measured)

Automatic iCloud provisioning using the existing ASC API key returned Authentication
failed; the public ASC read-only identifier lookup still succeeds with that key.
Trying Xcode's account-based route returned `No Accounts: Add a new account in
Accounts settings`. The existing wildcard development profile has no iCloud
entitlements. Rob was asked to sign into Xcode → Settings → Accounts on Pollux.
No signing identities were exported/revoked and no Tank capabilities were changed.
The only requested container is `iCloud.com.robbarry.overcoil` on team 3XLD352MG9.

The wheel/layout fix was separately shipped as build 6 on main. This branch was
parked intact while responding to Rob's follow-up requesting all-run watch statistics
and a top Save control for reference-photo cropping.
