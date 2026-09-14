import XCTest
@testable import OvercoilCore

extension CoreTests {
    func testRelativeReadingAgeBoundariesAndFutureClock() {
        for (seconds, expected) in [(0.0, "just now"), (59, "just now"), (60, "1m ago"),
                                    (3599, "59m ago"), (3600, "1h ago"), (10800, "3h ago"),
                                    (86400, "1d ago"), (1814400, "3w ago"), (2592000, "1mo ago"),
                                    (31536000, "1y ago")] {
            XCTAssertEqual(ReadingAge.label(since: start, now: start.addingTimeInterval(seconds)), "Last reading \(expected)")
        }
        XCTAssertEqual(ReadingAge.label(since: start.addingTimeInterval(10800), now: start), "Last reading in 3h")
        XCTAssertEqual(ReadingAge.label(since: start, now: start.addingTimeInterval(10800), spoken: true), "Last reading 3 hours ago")
    }

    func testPlotUsesActualElapsedSpacingAndRetainsIntermediateVariations() {
        let first = reading(start, offset: 8), middle = reading(start.addingTimeInterval(3600), offset: 20)
        let last = reading(start.addingTimeInterval(14400), offset: 14)
        let plot = RunPlot(readings: [last, first, middle])
        XCTAssertEqual(plot.points.map(\.id), [first.id, middle.id, last.id])
        XCTAssertEqual(plot.points.map(\.x), [0, 0.25, 1])
        XCTAssertLessThan(plot.points[1].y, plot.points[2].y)
        XCTAssertEqual(plot.change, 6); XCTAssertEqual(plot.duration, "4h")
        XCTAssertTrue(plot.connects(1)); XCTAssertTrue(plot.connects(2))
        XCTAssertLessThan(plot.lower, 8); XCTAssertGreaterThan(plot.upper, 20)
        XCTAssertEqual(RunPlot.seconds(-0.01), "0s")
    }

    func testPlotSingletonFlatAndCoincidentCapturesDoNotInventDrift() {
        let first = reading(start, offset: 8)
        let singleton = RunPlot(readings: [first])
        XCTAssertEqual(singleton.points[0].x, 0.5); XCTAssertNil(singleton.change)
        XCTAssertEqual(singleton.upper - singleton.lower, 4)
        let flat = RunPlot(readings: [first, reading(start.addingTimeInterval(86400), offset: 8)])
        XCTAssertEqual(flat.points[0].y, flat.points[1].y); XCTAssertEqual(flat.change, 0)
        let coincident = RunPlot(readings: [first, reading(start, offset: 10)])
        XCTAssertFalse(coincident.connects(1)); XCTAssertNil(coincident.change)
        XCTAssertTrue(RunPlot(readings: []).points.isEmpty)
    }

    func testPlotDoesNotBridgeInvalidObservationsOrCompromisedClock() {
        let first = reading(start, offset: 8), last = reading(start.addingTimeInterval(7200), offset: 14)
        var invalid = reading(start.addingTimeInterval(3600), offset: 20); invalid.timingValid = false
        let plot = RunPlot(readings: [first, invalid, last])
        XCTAssertEqual(plot.points.count, 3); XCTAssertNil(plot.change)
        XCTAssertFalse(plot.connects(1)); XCTAssertFalse(plot.connects(2))
        let compromised = RunPlot(readings: [first, last], clockCompromised: true)
        XCTAssertEqual(compromised.points.count, 2); XCTAssertFalse(compromised.connects(1)); XCTAssertNil(compromised.change)
    }
}
