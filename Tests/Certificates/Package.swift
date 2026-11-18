// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CertificateSmoke", platforms: [.macOS(.v13)], targets: [
    .systemLibrary(name: "OpenSSL", path: "OpenSSL", pkgConfig: "openssl", providers: [.brew(["openssl@3"])]),
    .executableTarget(name: "CertificateSmoke", dependencies: ["OpenSSL"], path: "Sources")
])
