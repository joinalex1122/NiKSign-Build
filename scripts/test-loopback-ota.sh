#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
loopback_test_dir=$(mktemp -d)
trap 'rm -rf "$loopback_test_dir"' EXIT
loopback_sources=()
while IFS= read -r loopback_source; do
    case "$loopback_source" in
        */GCDWebServerConnection.m|*/GCDWebServerFunctions.m) continue ;;
    esac
    loopback_sources+=("$loopback_source")
done < <(find Vendor/GCDWebServer -name '*.m' -print | sort)
xcrun clang -fobjc-arc -I Native/Dependencies -I Vendor/GCDWebServer/Core -I Vendor/GCDWebServer/Requests -I Vendor/GCDWebServer/Responses -I Vendor/GCDWebServer/Handlers \
    "${loopback_sources[@]}" Native/ServerCompatibility/Core/GCDWebServerConnection.m Native/ServerCompatibility/Core/GCDWebServerFunctions.m \
    Native/Dependencies/NiKLoopbackServer.m Tests/LoopbackOTASmoke.m \
    -framework Foundation -framework CFNetwork -framework SystemConfiguration -framework Security -framework UniformTypeIdentifiers \
    -lz -o "$loopback_test_dir/server"
python3 Tests/loopback_ota_test.py "$loopback_test_dir/server"
