#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
file_tools_dir=$(mktemp -d)
trap 'rm -rf "$file_tools_dir"' EXIT
mkdir -p "$file_tools_dir/Sources"
cp -R Tests/Certificates/OpenSSL "$file_tools_dir/OpenSSL"
cp Tests/FileTools/Package.swift "$file_tools_dir/Package.swift"
cp Tests/FileTools/main.swift Native/NiKArchive.swift Native/NiKCertZipHelper.swift Native/Services/NiKSignedOutputValidator.swift Native/Services/NiKProvisioningValidation.swift Native/Models/NiKProvisioningPattern.swift Native/Services/NiKPathValidator.swift Native/Services/NiKIPAArchive.swift Native/Services/NiKSigningBundlePreparation.swift Native/Models/NiKOTAHTTP.swift Tests/Support/NiKProvisionFixture.swift Tests/SigningInstallabilitySmoke.swift Native/Services/NiKInstallMetadata.swift Native/Services/NiKInstallationPayload.swift Native/Services/NiKSignedApps.swift Native/Services/NiKSignedFileAccess.swift "$file_tools_dir/Sources/"
if [[ $(uname) == Darwin ]]; then
    export NIK_TEST_OPENSSL="$(brew --prefix openssl@3)/bin/openssl"
    export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi
swift run --package-path "$file_tools_dir" FileToolsSmoke
