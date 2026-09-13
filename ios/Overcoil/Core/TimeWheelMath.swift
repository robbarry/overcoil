import Foundation

enum TimeWheelMath {
    static func value(forRow row: Int, period: Int) -> Int {
        ((row % period) + period) % period
    }

    // These are independent dial-entry fields, not a running clock. Wrapping
    // seconds never changes minutes, and wrapping minutes never changes hours.
    static func selecting(_ value: Int, component: Int, in time: WatchTime, twelveHour: Bool) -> WatchTime {
        var result = time
        switch component {
        case 0: result.hour = twelveHour ? time.hour / 12 * 12 + value % 12 : value % 24
        case 1: result.minute = value % 60
        case 2: result.second = value % 60
        default: break
        }
        return result
    }
}
