// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-slot-map-primitives",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [

        .library(name: "SlotMap Primitive", targets: ["SlotMap Primitive"]),

        .library(name: "SlotMap Primitives", targets: ["SlotMap Primitives"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-primitives/swift-storage-generational-primitives.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-primitives/swift-storage-primitives.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-primitives/swift-ownership-shared-primitives.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-primitives/swift-buffer-primitives.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-primitives/swift-memory-heap-primitives.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-primitives/swift-memory-allocation-primitives.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-primitives/swift-index-primitives.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-primitives/swift-ordinal-primitives.git",
            branch: "main"
        ),
        .package(
            url: "https://github.com/swift-primitives/swift-tagged-primitives.git",
            branch: "main"
        ),
    ],
    targets: [

        .target(
            name: "SlotMap Primitive",
            dependencies: [
                .product(
                    name: "Storage Generational Primitives",
                    package: "swift-storage-generational-primitives"
                ),
                .product(name: "Storage Primitive", package: "swift-storage-primitives"),
                .product(name: "Store Primitive", package: "swift-storage-primitives"),
                .product(name: "Store Protocol Primitives", package: "swift-storage-primitives"),
                .product(name: "Buffer Protocol Primitives", package: "swift-buffer-primitives"),
                .product(
                    name: "Ownership Shared Primitive",
                    package: "swift-ownership-shared-primitives"
                ),
                .product(name: "Memory Heap Primitives", package: "swift-memory-heap-primitives"),
                .product(
                    name: "Memory Allocator Primitive",
                    package: "swift-memory-allocation-primitives"
                ),
                .product(name: "Index Primitives", package: "swift-index-primitives"),
            ]
        ),

        .target(
            name: "SlotMap Primitives",
            dependencies: [
                "SlotMap Primitive",
                .product(
                    name: "Storage Generational Primitives",
                    package: "swift-storage-generational-primitives"
                ),
                .product(name: "Storage Primitive", package: "swift-storage-primitives"),
                .product(name: "Store Primitive", package: "swift-storage-primitives"),
                .product(name: "Store Protocol Primitives", package: "swift-storage-primitives"),
                .product(name: "Buffer Protocol Primitives", package: "swift-buffer-primitives"),
                .product(
                    name: "Ownership Shared Primitive",
                    package: "swift-ownership-shared-primitives"
                ),
                .product(name: "Memory Heap Primitives", package: "swift-memory-heap-primitives"),
                .product(
                    name: "Memory Allocator Primitive",
                    package: "swift-memory-allocation-primitives"
                ),
                .product(name: "Index Primitives", package: "swift-index-primitives"),
            ]
        ),

        .testTarget(
            name: "SlotMap Primitives Tests",
            dependencies: [
                "SlotMap Primitives",
                .product(
                    name: "Buffer Primitives Test Support",
                    package: "swift-buffer-primitives"
                ),
                .product(
                    name: "Tagged Primitives Standard Library Integration",
                    package: "swift-tagged-primitives"
                ),
                .product(
                    name: "Ordinal Primitives Standard Library Integration",
                    package: "swift-ordinal-primitives"
                ),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem
}
