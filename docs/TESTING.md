# Testing build handoff

## What to try on the phone

1. Open Overcoil and add a watch using only its name.
2. Start a timing run, allow camera access, photograph its running dial, and enter
   the normal seconds-hand time from the frozen photo. No synchronization needed.
3. Save. There should be an offset, one reading, and an automatic reference photo—
   **no daily rate yet**. Wait until the next day for a more useful second reading.
   Later time pickers suggest the watch's expected time from its prior offset, and
   measured drift once available. Still check the photograph; predictions are not
   observations. The reference timestamp itself always remains the actual capture.
4. Change the reference photo using Photos, a cover-only shot, or a saved image.
   Adjust the square crop. Reading evidence must remain unchanged.
5. Open the current run and a reading, correct its time, and inspect the new result.
   End a run if the watch stops or its hands are reset. Winding alone is fine.
6. Close and relaunch; watch, photos, cover crop, readings, and run history should
   remain. Camera permission can be disabled without losing access to history.

The normal photo is evidence, not a cover pointer. Unsaved captures do not count.
Default builds start empty; no illustrative watches or simulated readings are added.

## Automated verification

- Core tests cover endpoint/12-hour rates, zero elapsed/one reading, intermediates,
  midnight/year/noon inference, fixed time basis, subsecond references, capture
  anchor math, continuity reset, duplicate/stale saves, independent watch identities,
  atomic initial covers, run endings, corrections/deletions, cover retention/fallback,
  fault-injected writes, relaunch, and refusal to overwrite a corrupt manifest.
- Native UI tests exercise real buttons/pickers/file commits and relaunch; camera
  images/timestamps are conspicuously synthetic, simulator DEBUG-only fixtures.
  Permission denial is an injected authorization state in that same isolated build.
- Photos import uses Apple's real native picker and a generated test image copied
  into the dedicated simulator's photo library. No full-library access is requested.
- The two-reading/correction/relaunch flow is also run on iPhone SE (3rd generation)
  at the largest accessibility text category. Scrollable controls remain reachable;
  the save panel joins the scroll content at accessibility sizes instead of covering
  most of the small display. Test screenshots are visually inspected.
- Physical-device binaries are checked for the exact bundle/team/device family,
  valid signature, source revision, and absence of simulator fixture switches and
  credential material. Actual installed bundle version is read back from the device.

## What installation does NOT prove

The first launch probe was denied while the phone was locked; a later probe after
unlock successfully launched the installed app. Rob then tested it and reported
close-focus and button-padding issues. Build 4 addresses these by preferring a
verified autofocus-capable close-up lens, adding tap-to-focus, and giving primary
actions explicit horizontal/vertical insets and secondary actions 44-point touch
areas. Actual close-up sharpness still needs Rob's hands-on check. No passcode,
trust, or privacy prompts are bypassed.

Capture alignment has **not** been validated against a visible reference clock on a
physical device. The mathematical and simulator tests do not establish an exposure
error bound. The app labels results estimates and explains this limitation in Settings.

Before accuracy claims: use a validated visible reference, preserve diagnostic
metadata with each photo, and test bright/low light, moving hands, torch off/on,
processing latency, interruptions, and repeated shots. A timestamp on a processed
image alone is not proof of one perfectly defined exposure instant. Camera timestamp
alignment and physical interaction remain the principal hands-on validation tasks.

This is a local development install, not a TestFlight or App Store release. A new
App Store Connect app record, distribution export verification, tester setup, and
release metadata remain separate future work.

## Build 5 follow-up

Rob reported white-on-ivory text after a physical capture. A regression test that
shared the real camera's old presentation-wide dark scheme reproduced a heading
with zero dark pixels. Dark camera styling is now local, while reading entry
explicitly uses light appearance and dark ink. The test checks actual rendered
heading pixels after capture and retake, rather than only checking that text exists.

Rob also revised subsequent-reading defaults to predicted watch time. Core tests
cover first/one/two readings, real elapsed intervals, future/invalid observations,
compromised clocks, and fixed-offset interpretation; native UI tests check +8-second
and then +20-second suggestions in the +8 → +14 over 24 hours example.

## Build 6 follow-up

Time wheels now loop in both directions independently. Rob clarified that seconds
must not carry into minutes. The wrap regression taps the actual adjacent rows to
move 59 → 00 → 01 and back, asserting the hour/minute fields never change.

The save panel no longer repeats “Suggested from offset + drift.” The offset and
Save button use less vertical space; the normal page has no scrolling form beneath
an overlay. Tests check that both AM/PM buttons are hittable and that their lower
edge lies above the offset label, while Save is visible without scrolling. Prediction
still works; its explanation is available under Reading tips.
