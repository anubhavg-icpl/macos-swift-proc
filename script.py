# Create a comprehensive Package.swift example for the dual-daemon Swift package
package_swift_content = '''// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DualDaemonApp",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        // Two executables for our daemons
        .executable(name: "user-daemon", targets: ["UserDaemon"]),
        .executable(name: "system-daemon", targets: ["SystemDaemon"]),
        // Library for shared functionality
        .library(name: "SharedMessaging", targets: ["SharedMessaging"])
    ],
    dependencies: [
        // PubNub Swift SDK for production-grade messaging
        .package(url: "https://github.com/pubnub/swift.git", from: "9.2.0"),
        // Alternative: Google Cloud Pub/Sub (if using cloud approach)
        // .package(url: "https://github.com/googleapis/google-cloud-swift", from: "1.0.0"),
        // Logging framework
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        // User daemon executable target
        .executableTarget(
            name: "UserDaemon",
            dependencies: [
                "SharedMessaging",
                .product(name: "PubNubSDK", package: "swift"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/UserDaemon",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/UserDaemon/Info.plist"
                ])
            ]
        ),
        
        // System daemon executable target
        .executableTarget(
            name: "SystemDaemon",
            dependencies: [
                "SharedMessaging",
                .product(name: "PubNubSDK", package: "swift"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/SystemDaemon",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/SystemDaemon/Info.plist"
                ])
            ]
        ),
        
        // Shared messaging library
        .target(
            name: "SharedMessaging",
            dependencies: [
                .product(name: "PubNubSDK", package: "swift"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/SharedMessaging"
        ),
        
        // Test targets
        .testTarget(
            name: "SharedMessagingTests",
            dependencies: [
                "SharedMessaging",
                .product(name: "PubNubSDK", package: "swift")
            ],
            path: "Tests/SharedMessagingTests"
        ),
        
        .testTarget(
            name: "UserDaemonTests",
            dependencies: [
                "UserDaemon",
                "SharedMessaging"
            ],
            path: "Tests/UserDaemonTests"
        ),
        
        .testTarget(
            name: "SystemDaemonTests", 
            dependencies: [
                "SystemDaemon",
                "SharedMessaging"
            ],
            path: "Tests/SystemDaemonTests"
        )
    ]
)
'''

# Save the Package.swift content
with open("Package.swift", "w") as f:
    f.write(package_swift_content)

print("Package.swift created successfully!")
print("Content preview:")
print(package_swift_content[:500] + "..." if len(package_swift_content) > 500 else package_swift_content)