#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
nik_https_dir=$(mktemp -d)
trap 'rm -rf "$nik_https_dir"' EXIT
mkdir -p "$nik_https_dir/Sources"
cp Tests/HTTPSOTA/Package.swift "$nik_https_dir/Package.swift"
cp -R Tests/Certificates/OpenSSL "$nik_https_dir/OpenSSL"
cp Tests/HTTPSOTA/Server.swift Native/Dependencies/NiKHTTPSOTAServer.swift Native/Dependencies/NiKLocalTLSIdentity.swift Native/Dependencies/NiKOTAProfile.swift Native/Services/NiKTLSServerCertificate.swift Native/Models/NiKOTAHTTP.swift Native/Models/NiKOTALandingPage.swift Native/Models/NiKOTAURLs.swift "$nik_https_dir/Sources/"
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
swift build --package-path "$nik_https_dir"
nik_https_bin=$(swift build --package-path "$nik_https_dir" --show-bin-path)
python3 Tests/https_ota_test.py "$nik_https_bin/HTTPSOTASmoke"
