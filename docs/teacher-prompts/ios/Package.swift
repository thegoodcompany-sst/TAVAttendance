// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PromptRouter",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "PromptRouter", targets: ["PromptRouter"])],
    targets: [
        .target(name: "PromptRouter"),
        .testTarget(name: "PromptRouterTests", dependencies: ["PromptRouter"],
                    resources: [.copy("Fixtures")])
    ]
)
