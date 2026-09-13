# iCloud Drive sync — verification in progress

Rob's requirement is a browsable iCloud Drive folder containing the complete Watch
Box and original photos, automatic two-way sync between Overcoil installations,
and restore on a new device using the same iCloud account. No Mac app is required
for Finder access. This is NOT merely a one-way export.

## Implemented on this branch

- Dedicated `iCloud.com.robbarry.overcoil` CloudDocuments container, visible as
  Overcoil in iCloud Drive. No Tank container or signing bridge is reused.
- One authoritative `Library.overcoil.json` with exact native timestamps/records,
  readable UTC reading/overall-watch summaries, safe photo paths and SHA256 checksums.
  `Photos/` contains originals; `Thumbnails/` previews; `Recovery/` older documents.
- A local offline database remains usable. A new empty installation downloads the
  existing cloud library; an empty/missing cloud folder never replaces local data.
- Baseline/local/remote revision checks choose upload, download, unchanged, or a
  visible conflict. Concurrent divergent changes are not silently overwritten.
- Every cloud operation is coordinated. The shared document changes atomically,
  after immutable photos are present. A pre-write comparison prevents overwriting
  a document that changed during the operation.
- Conflict choices retain each available cloud version and its photos locally,
  plus recovery documents in Drive, before explicitly replacing the active copy.
  Original cloud photo files are retained for recovery, not automatically deleted.
- Imports validate all checksums and the still-current local revision, retain a
  local recovery copy, and atomically commit. Imports wait while an edit is open.
- Account changes pause sync until confirmation. Simulator UI fixtures never start
  iCloud operations. No backend/analytics or account credentials are embedded.
- Metadata notifications plus foreground/local-save triggers schedule sync. Settings
  exposes pending uploads, errors, conflicts and the last verified upload. “Uploaded”
  requires Apple's per-file uploaded state plus photo checksum checks.
- A safe restore check uses an isolated local repository, never clears the real
  library, and writes a bounded private receipt. Debug launch argument
  `--verify-icloud-restore` requests this check after the initial verified upload.

## Verification

Core tests exercise two replicas (initial restore, second-device edit, return sync),
subsecond preservation, missing/corrupt photos, divergent revisions, and refusal to
replace a locally changed library. The main UI tests remain isolated from iCloud.
Physical upload and isolated-restore verification is the remaining release gate.

## Signing setup

The original API-key-only bootstrap failed for the new iCloud capability, while
ordinary signing and ASC reads worked. Xcode's account route reported No Accounts.
Rob then signed into Xcode. A subsequent account-based build succeeded; its actual
signed app/profile were verified for team3XLD352MG9, com.robbarry.overcoil,
CloudDocuments and the exact iCloud/ubiquity container identifiers. No working key
was rotated and no Tank certificates/profiles were removed.

User data and diagnostics stay in private local storage/iCloud, never the public
repo. The original phone library has a separate checksummed Mac backup. Build 7's
in-place update preserved its store byte-for-byte; no uninstall/reset was used.

Use one reference phone per timing run. Sync does not certify that two devices'
wall clocks agree; switching the reference phone should start a new run.
