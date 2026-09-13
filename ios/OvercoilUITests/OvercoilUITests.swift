import XCTest

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
