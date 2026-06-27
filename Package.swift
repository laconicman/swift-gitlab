// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitLabKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        // Façade: the type you use day-to-day (re-exports the generated API).
        .library(name: "GitLabKit", targets: ["GitLabKit"]),
        // The generated client/types, if you want them directly.
        .library(name: "GitLabOpenAPI", targets: ["GitLabOpenAPI"]),
    ],
    dependencies: [
        // Generator is a *plugin* — attached via `plugins:`, never `dependencies:` of a target.
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
        // Reused middleware from the same ecosystem as YooMoneyAPIClient.
        .package(url: "https://github.com/laconicman/OSLogLoggingMiddleware", from: "1.0.0"),
        // DocC catalog rendering via `swift package generate-documentation`.
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
        // YAML parsing for the maintainer spec tool (also used transitively by the generator).
        .package(url: "https://github.com/jpsim/Yams", from: "6.0.0"),
    ],
    targets: [
        // Generated target: holds only openapi.yaml + the generator config.
        // The build plugin emits Client.swift + Types.swift at build time (not committed).
        .target(
            name: "GitLabOpenAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            // Preserved tier templates kept beside the active config for reference, but
            // must not be seen by SwiftPM or the generator plugin (which loads the file
            // named exactly `openapi-generator-config.yaml`).
            exclude: [
                "openapi-generator-config.core.yaml",
                "openapi-generator-config.full.yaml",
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
        // Thin façade: client factory + auth middleware.
        .target(
            name: "GitLabKit",
            dependencies: [
                "GitLabOpenAPI",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "OSLogLoggingMiddleware", package: "OSLogLoggingMiddleware"),
            ]
        ),
        // Maintainer tool: fetch + normalize + retype the vendored spec. `swift run gitlab-spec-tool`.
        .executableTarget(
            name: "gitlab-spec-tool",
            dependencies: [.product(name: "Yams", package: "Yams")]
        ),
        .testTarget(
            name: "GitLabKitTests",
            dependencies: [
                "GitLabKit",
                "GitLabOpenAPI",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ]
        ),
    ]
)
