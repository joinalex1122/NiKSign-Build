// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FileToolsSmoke", platforms: [.macOS(.v13)], dependencies: [
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
], targets: [.systemLibrary(name: "OpenSSL", path: "OpenSSL", pkgConfig: "openssl"), .executableTarget(name: "FileToolsSmoke", dependencies: ["ZIPFoundation", "OpenSSL"], path: "Sources")])
