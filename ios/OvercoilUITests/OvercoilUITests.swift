import XCTest
import UIKit

@MainActor final class OvercoilUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUp() async throws {
        await MainActor.run {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["OVERCOIL_UI_STORAGE"] = UUID().uuidString
        app.launch()
        }
    }
    func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func tap(_ title: String) {
        let button = app.buttons[title].firstMatch
        for _ in 0..<5 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Missing button: \(title)")
        button.tap()
    }
    func addWatch() {
        tap("addWatch")
        let field = app.textFields["watchName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Test watch")
        tap("saveWatch")
        XCTAssertTrue(app.buttons["Start timing run"].waitForExistence(timeout: 5))
    }
    func takePhoto() { tap("Take simulator test photo"); XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5)) }
    func enterSeconds(_ seconds: String) {
        XCTAssertEqual(app.pickerWheels.count, 3)
        app.pickerWheels.element(boundBy: 2).adjust(toPickerWheelValue: seconds)
    }
    func testTwoReadingsCoverCorrectionAndRelaunch() {
        addWatch(); screenshot("01-watch-detail-no-cover")
        tap("Start timing run"); takePhoto(); screenshot("02-frozen-entry")
        enterSeconds("08"); tap("Save reading")
        XCTAssertTrue(app.staticTexts["8 seconds ahead"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["1 reading saved"].exists)
        XCTAssertFalse(app.staticTexts["seconds / day"].exists)
        screenshot("03-first-reading-auto-cover")
        tap("Add reading"); takePhoto(); enterSeconds("14"); tap("Save reading")
        XCTAssertTrue(app.staticTexts["rateValue"].waitForExistence(timeout: 8) && app.staticTexts["rateValue"].label.contains("+6.0")); screenshot("04-two-reading-rate")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Test watch"].waitForExistence(timeout: 8))
        app.staticTexts["Test watch"].tap()
        XCTAssertTrue(app.staticTexts["rateValue"].waitForExistence(timeout: 8) && app.staticTexts["rateValue"].label.contains("+6.0"))
        tap("currentRun")
        XCTAssertTrue(app.staticTexts["Average since the first reading"].waitForExistence(timeout: 5)); screenshot("05-run-detail")
        app.staticTexts["14 seconds ahead"].tap()
        tap("Correct entered time")
        enterSeconds("20"); tap("Save correction")
        XCTAssertTrue(app.staticTexts["20 seconds ahead"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["rateValue"].waitForExistence(timeout: 5) && app.staticTexts["rateValue"].label.contains("+12.0"))
        screenshot("06-corrected-rate")
    }
    func testCanceledCaptureDoesNotCreateRunAndCoverOnlyHasNoReading() {
        addWatch(); tap("Start timing run"); tap("Close")
        XCTAssertTrue(app.buttons["Start timing run"].waitForExistence(timeout: 5))
        tap("Change reference photo"); tap("Take a photo"); tap("Take simulator test photo")
        tap("Use as reference photo")
        XCTAssertTrue(app.buttons["Start timing run"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["1 reading saved"].exists)
        screenshot("07-cover-only")
    }
    func testDeleteOnlyReadingKeepsCoverAndWatch() {
        addWatch(); tap("Start timing run"); takePhoto(); enterSeconds("08"); tap("Save reading")
        tap("currentRun")
        let offset = app.staticTexts["8 seconds ahead"].firstMatch
        for _ in 0..<3 where !app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "8 seconds ahead")).firstMatch.isHittable { app.swipeUp() }
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "8 seconds ahead")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        tap("Delete reading…"); tap("Delete reading")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Test watch"].waitForExistence(timeout: 5)); app.staticTexts["Test watch"].tap()
        XCTAssertTrue(app.buttons["Start timing run"].waitForExistence(timeout: 5))
        XCTAssertFalse(offset.exists)
        screenshot("09-deleted-reading-retained-cover")
    }
    func testCameraDeniedLeavesHistoryUsable() {
        addWatch()
        app.terminate(); app.launchArguments = ["--ui-testing", "--real-camera", "--camera-denied"]; app.launch()
        app.staticTexts["Test watch"].tap(); tap("Start timing run")
        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: 8))
        screenshot("10-camera-denied")
        tap("Close")
        XCTAssertTrue(app.buttons["Start timing run"].waitForExistence(timeout: 5))
    }
    func assertDarkText(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let shot = app.screenshot().image.cgImage!
        let scale = CGFloat(shot.width) / app.frame.width
        let frame = element.frame
        let rect = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                          width: frame.width * scale, height: frame.height * scale).integral
        guard let crop = shot.cropping(to: rect), crop.width > 0, crop.height > 0 else { return XCTFail("Text is not in the screenshot") }
        var rgba = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                    bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        let darkPixels = stride(from: 0, to: rgba.count, by: 4).filter { rgba[$0] < 90 && rgba[$0 + 1] < 90 && rgba[$0 + 2] < 90 }.count
        XCTAssertGreaterThan(Double(darkPixels) / Double(crop.width * crop.height), 0.02, "Heading needs dark ink on the ivory surface—not white-on-white.")
    }
    func testReadableEntryAfterDarkCameraAndRetake() {
        addWatch(); tap("Start timing run"); takePhoto()
        let heading = app.staticTexts["What time does your watch show?"]
        screenshot("14-entry-after-dark-camera")
        assertDarkText(heading)
        enterSeconds("08"); tap("Retake"); takePhoto()
        screenshot("15-entry-after-dark-retake")
        assertDarkText(heading)
        enterSeconds("14"); tap("Save reading")
        XCTAssertTrue(app.staticTexts["14 seconds ahead"].waitForExistence(timeout: 5))
    }
    func testSubsequentPrefillUsesWatchOffsetAndMeasuredDrift() {
        addWatch(); tap("Start timing run"); takePhoto(); enterSeconds("08"); tap("Save reading")
        tap("Add reading"); takePhoto()
        XCTAssertEqual(app.pickerWheels.element(boundBy: 2).value as? String, "08")
        XCTAssertFalse(app.staticTexts["Suggested from last offset"].exists)
        screenshot("16-prefill-from-last-offset")
        enterSeconds("14"); tap("Save reading")
        tap("Add reading"); takePhoto()
        XCTAssertEqual(app.pickerWheels.element(boundBy: 2).value as? String, "20")
        XCTAssertFalse(app.staticTexts["Suggested from offset + drift"].exists)
        screenshot("17-prefill-from-measured-drift")
        tap("Cancel")
        XCTAssertTrue(app.staticTexts["rateValue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["rateValue"].label.contains("+6.0"))
    }
    func testSecondsWrapIndependentlyAndPeriodIsUncovered() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-rollover"]; app.launch()
        addWatch(); tap("Start timing run"); takePhoto()
        let hours = app.pickerWheels.element(boundBy: 0)
        let minutes = app.pickerWheels.element(boundBy: 1)
        let seconds = app.pickerWheels.element(boundBy: 2)
        XCTAssertEqual(seconds.value as? String, "59")
        XCTAssertEqual(minutes.value as? String, "00")
        let originalHour = hours.value as? String
        func stepSecond(_ direction: CGFloat) {
            let height = seconds.frame.height
            seconds.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 + direction * 38 / height)).tap()
        }
        stepSecond(1); XCTAssertEqual(seconds.value as? String, "00")
        stepSecond(1); XCTAssertEqual(seconds.value as? String, "01")
        XCTAssertEqual(minutes.value as? String, "00"); XCTAssertEqual(hours.value as? String, originalHour)
        stepSecond(-1); XCTAssertEqual(seconds.value as? String, "00")
        stepSecond(-1); XCTAssertEqual(seconds.value as? String, "59")
        XCTAssertEqual(minutes.value as? String, "00"); XCTAssertEqual(hours.value as? String, originalHour)
        let period = app.segmentedControls["periodPicker"]
        XCTAssertTrue(period.exists); XCTAssertTrue(period.buttons["AM"].isHittable); XCTAssertTrue(period.buttons["PM"].isHittable)
        XCTAssertLessThan(period.frame.maxY, app.staticTexts["readingOffset"].frame.minY)
        XCTAssertTrue(app.buttons["Save reading"].isHittable)
        XCTAssertFalse(app.staticTexts["Suggested from offset + drift"].exists)
        XCTAssertFalse(app.scrollViews["accessibleEntryScroll"].exists)
        screenshot("18-independent-wrap-and-uncovered-period")
        tap("Cancel")
    }
    func testAddWatchSaveStaysPinnedWhileFormScrolls() {
        tap("addWatch")
        let name = app.textFields["watchName"]; name.tap(); name.typeText("Pinned Save test")
        let save = app.buttons["saveWatch"]
        XCTAssertTrue(save.isHittable)
        let top = save.frame.minY
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(save.isHittable)
        XCTAssertEqual(save.frame.minY, top, accuracy: 1)
        XCTAssertLessThan(save.frame.maxY, app.frame.height / 3)
        screenshot("19-add-watch-fixed-save")
        save.tap()
        XCTAssertTrue(app.buttons["Start timing run"].waitForExistence(timeout: 5))
    }
    func testPhotoCropHasTopSaveWithoutScrolling() {
        addWatch(); tap("Change reference photo"); tap("Take a photo"); tap("Take simulator test photo")
        let save = app.buttons["saveReferencePhoto"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertTrue(save.isHittable)
        XCTAssertLessThan(save.frame.maxY, app.frame.height / 3)
        screenshot("20-photo-top-save")
        save.tap()
        XCTAssertTrue(app.buttons["Start timing run"].waitForExistence(timeout: 5))
    }
    func testWatchBoxLeadsWithOverallRateAcrossRuns() {
        addWatch(); tap("Start timing run"); takePhoto(); enterSeconds("08"); tap("Save reading")
        tap("Add reading"); takePhoto(); enterSeconds("14"); tap("Save reading")
        tap("End run"); tap("End run — finished")
        tap("Start timing run"); takePhoto(); enterSeconds("40"); tap("Save reading")
        tap("Add reading"); takePhoto(); enterSeconds("52"); tap("Save reading")
        XCTAssertTrue(app.staticTexts["rateValue"].label.contains("+9.0"))
        app.terminate(); app.launch()
        let headline = app.staticTexts["watchBoxOverallRate"]
        XCTAssertTrue(headline.waitForExistence(timeout: 5)); XCTAssertTrue(headline.label.contains("+9.0"))
        XCTAssertFalse(app.staticTexts["Run in progress"].exists)
        screenshot("21-watch-box-pooled-rate")
    }
    func testPrimaryButtonHasContentInsets() {
        let title = "Add your first watch"
        let button = app.buttons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        let textWidth = (title as NSString).size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .headline)]).width
        XCTAssertGreaterThanOrEqual(button.frame.width, textWidth + 38)
        XCTAssertGreaterThanOrEqual(button.frame.height, 52)
        screenshot("13-primary-button-padding")
        button.tap()
        XCTAssertTrue(app.textFields["watchName"].waitForExistence(timeout: 5))
    }
    func testNativePhotosImport() {
        addWatch(); tap("Change reference photo"); tap("Choose from Photos")
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 20))
        screenshot("11-native-photos-picker")
        // iOS 26's remote Photos grid exposes image frames but reports them
        // non-hittable. Tap the live element's measured center, not a fixed point.
        let frame = photo.frame
        XCTAssertGreaterThan(frame.width, 0)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        tap("Use as reference photo")
        XCTAssertTrue(app.buttons["Start timing run"].waitForExistence(timeout: 8))
        app.terminate(); app.launch(); app.staticTexts["Test watch"].tap()
        XCTAssertTrue(app.buttons["Start timing run"].waitForExistence(timeout: 5))
        screenshot("12-imported-cover-after-relaunch")
    }
    func testFrozenPrefillAndRetake() {
        addWatch(); tap("Start timing run"); takePhoto()
        let original = app.pickerWheels.element(boundBy: 2).value as? String
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.pickerWheels.element(boundBy: 2).value as? String, original)
        enterSeconds("30"); tap("Retake"); takePhoto()
        XCTAssertEqual(app.pickerWheels.element(boundBy: 2).value as? String, original)
        screenshot("08-retake-reset")
        tap("Cancel")
        XCTAssertTrue(app.buttons["Start timing run"].waitForExistence(timeout: 5))
    }
}
