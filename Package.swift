// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PodRamsCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "PodRamsCore",
            targets: ["PodRamsCore"]
        )
    ],
    dependencies: [
        .package(path: "LocalDeps/FeedKit")
    ],
    targets: [
        .target(
            name: "PodRamsCore",
            dependencies: [
                .product(name: "FeedKit", package: "FeedKit")
            ],
            path: "PodRams",
            exclude: [
                "Assets.xcassets",
                "Preview Content",
                "Info.plist",
                "PodRams.entitlements",
                "ar.lproj",
                "bg.lproj",
                "ca.lproj",
                "cs.lproj",
                "da.lproj",
                "de.lproj",
                "el.lproj",
                "es.lproj",
                "eu.lproj",
                "fi.lproj",
                "fr.lproj",
                "he.lproj",
                "hi.lproj",
                "hr.lproj",
                "hu.lproj",
                "id.lproj",
                "it.lproj",
                "ja.lproj",
                "ko.lproj",
                "ms.lproj",
                "nb.lproj",
                "nl.lproj",
                "pl.lproj",
                "pt.lproj",
                "pt-BR.lproj",
                "ro.lproj",
                "ru.lproj",
                "sk.lproj",
                "sl.lproj",
                "sr.lproj",
                "sv.lproj",
                "th.lproj",
                "tr.lproj",
                "uk.lproj",
                "vi.lproj",
                "zh-Hans.lproj",
                "zh-Hant.lproj",
                "ColorScheme.xml",
                "PerformanceOptimizations.md",
                "ThreadOptimizationSummary.md",
                "SubscriptionFix.md",
                "PersistenceFix.md"
            ],
            resources: [
                .process("Base.lproj"),
                .process("en.lproj")
            ]
        ),
        .testTarget(
            name: "PodRamsCoreTests",
            dependencies: ["PodRamsCore"],
            path: "PodRamsTests"
        )
    ]
)
