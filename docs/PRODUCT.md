# Overcoil v1 implementation contract

Based on Rob's September 13, 2026 developer handoff. Written behavior governs;
mockups are visual direction, not sample data. All UI calls the collection **Watch Box**.

## Everyday flow

Watch Box → choose watch → in-app photo → frozen hour/minute/second entry → save.
No synchronization prerequisite, account, backend, network reference clock, or photo OCR.
Native iPhone, SwiftUI, AVFoundation, app-owned local image files and atomic manifest.

- A watch needs only a name. Identical names/models represent separate UUIDs.
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
- Time selection is frozen from the capture instant, using the run's fixed UTC
  offset basis; it never follows a timer. One-second entry; subseconds retained in
  the reference. Locale 12/24-hour presentation; date and UTC offset inspectable.
- Date inference chooses the closest plausible day (and half-day in 12-hour mode)
  to reference + previous offset. Explicit date/AM-PM choices override inference.
- Offsets are entered absolute time minus reference instant. Headline rate is
  `(latestOffset - firstOffset) * 86400 / actualReferenceElapsed`. Sort by capture
  time, not save time. Intermediate observations stay visible; no regression or
  unweighted average of interval rates. No rate for one reading or zero elapsed.
- Rates are estimates, rounded for display only; avoid negative zero. Less than
  24 hours is an Early estimate. End time never alters measured span or rate.
- Editing a reading changes entered components/interpretation only. Ending a run
  preserves editable history. Stopped/reset hands require a new run. Winding alone
  does not. Large jumps (>120 seconds in this build) prompt, never silently exclude.
- Deleting a reading retains its image when used as a cover. Removing the final
  reading also removes the empty run after confirmation, retaining the watch.
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

Cloud sync, accounts, OCR/automatic dial reading, social sharing, reminders, exports,
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
