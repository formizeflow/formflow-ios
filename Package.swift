// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "FormFlow",
    platforms: [.iOS(.v15)],
    products: [.library(name: "FormFlow", targets: ["FormFlow"])],
    targets: [
        .target(name: "FormFlow"),
        .testTarget(name: "FormFlowTests", dependencies: ["FormFlow"]),
    ]
)
