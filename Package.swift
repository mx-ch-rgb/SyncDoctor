// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SyncDoctor",
    // Le SDK de Xcode 27.1 plafonne la cible à 27.0 ; le minimum 27.2 est imposé par
    // LSMinimumSystemVersion dans Resources/Info.plist.
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(
            name: "SyncDoctor",
            path: "Sources/SyncDoctor",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
