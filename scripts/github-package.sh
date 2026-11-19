#!/bin/bash
# Build and validate before creating a commit. Linux cannot perform the required Xcode build.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
    echo 'Run on macOS with Xcode; this helper never commits unbuilt changes.' >&2
    exit 1
fi
bash scripts/audit-ios.sh
printf '%s\n' 'Build passed. Review the diff and commit explicitly; no automatic push.'
