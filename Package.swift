// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "OvercoilCore", platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "OvercoilCore", targets: ["OvercoilCore"])],
    targets: [.target(name: "OvercoilCore", path: "ios/Overcoil/Core"),
              .testTarget(name: "OvercoilCoreTests", dependencies: ["OvercoilCore"])]
)
