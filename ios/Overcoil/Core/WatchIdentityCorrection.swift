import Foundation

// Private, operator-supplied repair input. No personal inventory belongs in source.
// Exact identity preconditions prevent overwriting a concurrent edit. Only these
// fields can be changed; photos, timings, notes and watch IDs are not inputs.
struct WatchIdentityFields: Codable, Equatable {
    var name: String
    var brand: String
    var model: String
    var nickname: String?
    init(_ watch: Watch) {
        name = watch.name; brand = watch.brand; model = watch.model; nickname = watch.nickname
    }
}
struct WatchIdentityCorrection: Codable {
    var watchID: UUID
    var expected: WatchIdentityFields
    var brand: String
    var model: String
    var nickname: String
}
struct WatchIdentityCorrections: Codable {
    var version = 1
    var corrections: [WatchIdentityCorrection]
}
