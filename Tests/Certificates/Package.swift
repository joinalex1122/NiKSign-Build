// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CertificateSmoke", platforms: [.macOS(.v13)], dependencies: [
    .package(url: "https://github.com/krzyzanowskim/OpenSSL.git", exact: "3.6.5000")
], targets: [.executableTarget(name: "CertificateSmoke", dependencies: [.product(name: "OpenSSL", package: "OpenSSL")], path: "Sources")])
