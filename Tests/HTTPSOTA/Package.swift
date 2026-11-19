// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HTTPSOTASmoke", platforms: [.macOS(.v13)], targets: [
    .systemLibrary(name: "OpenSSL", path: "OpenSSL", pkgConfig: "openssl"),
    .executableTarget(name: "HTTPSOTASmoke", dependencies: ["OpenSSL"], path: "Sources")
])
