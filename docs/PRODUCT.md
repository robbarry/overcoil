# Overcoil v1 implementation contract

Based on Rob's September 13, 2026 developer handoff. Written behavior governs;
mockups are visual direction, not sample data. All UI calls the collection **Watch Box**.

## Everyday flow

Watch Box → choose watch → in-app photo → frozen hour/minute/second entry → save.
No synchronization prerequisite, account, backend, network reference clock, or photo OCR.
Native iPhone, SwiftUI, AVFoundation, app-owned local image files and atomic manifest.

- A watch needs only a brand, model, or nickname. Brand is the maker; model is the watch designation; optional nickname overrides the derived title. Identical names/models represent separate UUIDs. Existing names remain intact until explicitly edited.
  Optional brand/model/notes and an optional deliberately chosen creation cover.
- The first successful saved photo automatically becomes the cover only when no
  cover exists. Discarded drafts never count. Later readings never replace a cover.
- Cover-only camera, native Photos import, retained watch images, and earliest
  retained image can supply a cover. Square position/zoom is stored independently
  of immutable original bytes. Imported files are copied into app-owned storage.
- A run begins in the same commit as its first reading. At most one active run per
  watch; different watches may run concurrently. Cancel leaves no empty run.
- Capture metadata and bytes are a single draft. Retake discards both together.
  Imported images cannot create measurements. Save is idempotent by draft UUID.
- Time selection is frozen for the capture, using the run's fixed UTC offset basis;
  it never follows a timer. Per Rob's follow-up, the first reading starts at phone
  capture time; later readings start at predicted watch time: reference + last
  measured offset + measured first-to-latest rate × time since the last reading.
  With only one prior reading, use its offset without drift. This is visibly labeled
  a suggestion that the user must confirm against the image, not a new measurement.
  Details are available in Reading tips; the compact save panel has no prediction
  caption, per Rob's follow-up. Hours/minutes/seconds wrap independently in both
  directions, with no carry between fields.
  One-second entry; subseconds retained in the reference. Locale 12/24-hour
  presentation; date and UTC offset inspectable.
- Date inference chooses the closest plausible day (and half-day in 12-hour mode)
  to the predicted watch instant. Explicit date/AM-PM choices override inference.
- Offsets are entered absolute time minus reference instant. Headline rate is
  `(latestOffset - firstOffset) * 86400 / actualReferenceElapsed`. Sort by capture
  time, not save time. Intermediate observations stay visible; no regression or
  unweighted average of interval rates. No rate for one reading or zero elapsed.
- Rates are estimates, rounded for display only; avoid negative zero. Less than
  24 hours is an Early estimate. End time never alters measured span or rate.
- Editing a reading changes entered components/interpretation only. Ending a run
  preserves editable history. Stopped/reset hands require a new run. Winding alone
  does not. Large deviations from the predicted watch time (>120 seconds in this build) prompt, never silently exclude.
- Deleting a reading retains its image when used as a cover. Removing the final
  reading also removes the empty run after confirmation, retaining the watch.
  Run and reading detail screens offer a top-bar trash button with confirmation.
  Deleting an active or completed run removes all its readings in one transaction;
  the watch, its cover/crop, unrelated photos and other runs remain unchanged.
  Deleting an active run does not reopen a completed run. Timing results recalculate
  from remaining evidence. Deletions sync through the normal iCloud library update;
  cloud original photos and recovery copies may remain, rather than being purged.
  Explicit cover-image deletion falls back to the earliest retained image or placeholder.
- Clock discontinuities (>0.5 s wall/host disagreement, or an overly wide anchor
  bracket) retain readings but end/compromise the run and suppress its rate.
  Continuity UUIDs are limited to uninterrupted foreground lifetimes. They are NOT
  boot IDs; uptime is never compared across suspension, relaunch, or reboot.
- Camera denied/unavailable keeps collection/history usable. No microphone,
  location, or full-library permission. No runtime network uploads.
- Failed storage operations preserve prior committed state and do not announce
  success. A corrupt manifest or missing referenced file blocks loading rather than
  silently overwriting user data. Writes use synchronized temporary files and an
  atomic manifest rename, followed by cleanup of unreferenced app-owned assets only.

## Visual and accessibility direction

Warm ivory, dark text, restrained accessible burnt-orange accents, original watch
photography, italic serif wordmark plus code-native hairspring mark, tabular timing
numerals. Native navigation and controls; scrolling layouts for smaller iPhones and
Dynamic Type. Photo/time actions have VoiceOver labels. Direction and validity are
expressed in words, not only color. No mockup watches are preloaded.

## Explicit non-goals

Developer-hosted accounts, OCR/automatic dial reading, social sharing, reminders,
iPad/Catalyst, App Store publication, and certified measurement accuracy.

## Physical measurement validation gate

A compiled timestamp mapping is not an accuracy test. Before accuracy claims,
compare saved images and mapped reference instants with a validated visible time
reference on physical iPhones, under daylight, low light, moving seconds hands,
and every enabled mode (close-up ultra-wide when autofocus-capable, wide-angle fallback, JPEG speed priority, torch off/on). Record
pipeline settings, raw timestamp/timebase, anchor bracket, residual, image, and
observed alignment. Device install is not this validation. Settings says so.

Apple references:
- [Photo timestamp](https://developer.apple.com/documentation/avfoundation/avcapturephoto/timestamp)
- [Session synchronization clock](https://developer.apple.com/documentation/avfoundation/avcapturesession/synchronizationclock)
- [Photo quality prioritization](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/photoqualityprioritization)
- [Native Photos picker](https://developer.apple.com/documentation/photokit/bringing-photos-picker-to-your-swiftui-app)
- [Required reason API categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)

## Overall watch statistics (follow-up)

Watch Box and watch detail lead with the watch's overall estimated seconds/day
when any valid run has two readings. Combine each run's first-to-latest offset
change and divide by the sum of those runs' actual measured seconds. This is a
duration-weighted average—not an unweighted mean and never a comparison across
reset offsets. Single-reading runs, zero spans and compromised clocks contribute
no rate. Watch detail shows the contributing reading/run counts, measured duration, and date.
“Early estimate” indicates that no contributing run yet spans 24 hours; it is not
a confidence percentage. All valid runs currently contribute; a future servicing
boundary will start a new statistics epoch.

Add/Edit Watch has a fixed header outside the scrolling form, keeping Save visible
even with the keyboard or a chosen photo. Reference-photo cropping also offers a
top Save action; both save locations share the same duplicate/save-failure guard.

## iCloud follow-up

Rob requested automatic backup AND two-way synchronization through a browsable
iCloud Drive folder, including restoration on another Overcoil installation. The
local store remains available offline; conflicts require an explicit choice, with
recovery copies retained. No Mac app is required to browse the JSON and original
photos. This supersedes the original local-only/no-cloud v1 default.

## Watch Box visual simplification

Rob explicitly removed the extra metadata from collection cards. Cards now contain
the reference photo, name/model, and one timing value when available: overall
seconds/day, or the latest offset if a rate cannot yet be calculated. No active dot,
reading count, absolute timestamp, “early estimate,” “start a timing run,” or “no rate
yet” placeholder belongs on the grid. Supporting information remains on detail
screens. Grid items align at their top edges despite unequal caption heights.

## Watch Box ordering

Most recently saved or corrected timing entry first, across active and completed
runs. Use the latest save/update timestamp among remaining readings, not the entered
watch time or photo capture timestamp. Watches without readings follow those with
readings; ties and untimed watches retain their existing collection order. Deleting
readings/runs recomputes the order from surviving entries. Identity/cover edits alone
do not move a watch. This is display-only: persisted collection order and timing
evidence remain unchanged.

## Quiet timing presentation

Watch Box also shows a compact relative age, such as “Last reading 3h ago” or
“Last reading 3w ago,” only when a reading exists. This uses the latest photo's
capture instant, not its correction time or the latest contributing rate endpoint.
The caption refreshes while visible and after foregrounding. Future timestamps
are expressed as “in …” rather than disguised as a recent past observation.

Remove recurring instructions about taking another reading, waiting until tomorrow,
automatic covers and correction semantics from everyday screens. The concise Early
estimate qualifier and genuine clock/error warnings remain; explanations live in
Reading tips, info and Settings rather than repeating alongside the data.

Each run has a small chart on its list row, current-run card and detail screen:
observed offset in seconds, with dots at actual capture-time spacing and straight
connections between adjacent valid observations. Detail charts label their vertical
scale; all charts with valid measured change show that change and elapsed span.
One reading produces one dot, not a trend. Coincident captures do not establish a
line/rate, invalid observations break connections, and compromised runs show only
neutral outlined dots. No bridging runs, smoothing, fitted curve, implied steady
rate between samples, or unvalidated uncertainty/error bars. Charts never change
saved evidence or headline rate calculations.
