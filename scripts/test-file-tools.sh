#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
file_tools_dir=$(mktemp -d)
trap 'rm -rf "$file_tools_dir"' EXIT
mkdir -p "$file_tools_dir/Sources"
cp Tests/FileTools/Package.swift "$file_tools_dir/Package.swift"
cp Tests/FileTools/main.swift Native/NiKArchive.swift Native/NiKCertZipHelper.swift Native/Services/NiKSignedOutputValidator.swift "$file_tools_dir/Sources/"
swift run --package-path "$file_tools_dir" FileToolsSmoke
