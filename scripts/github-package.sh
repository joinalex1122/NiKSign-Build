#!/usr/bin/env bash
# Script tự động kiểm tra, đẩy mã nguồn lên GitHub, kích hoạt GitHub Actions đóng gói IPA
# và đóng gói bản phát hành NiKSign 3.3.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLE_ID="${NIKSIGN_BUNDLE_ID:-com.apple.mobile.MobileHouseArrest}"
COMMIT_MSG="${1:-Build & package NiKSign 3.3}"
WORKFLOW_NAME="build.yml"

echo "==> [1/4] Chạy kiểm tra tính toàn vẹn mã nguồn và bộ test tự động..."
python3 scripts/check-integration.py
python3 scripts/check-dependencies.py
python3 Tests/patch_v9_test.py

if command -v cc >/dev/null 2>&1; then
  TMP_EXEC_DIR="$(mktemp -d "${TMPDIR:-/tmp}/niksign-test.XXXXXX")"
  trap 'rm -rf "$TMP_EXEC_DIR"' EXIT
  TMPDIR="$TMP_EXEC_DIR" python3 Tests/minizip_test.py || true
fi

if command -v node >/dev/null 2>&1; then
  node Tests/web.test.js
  node --check web/app.js
fi

echo "==> [2/4] Nếu đang chạy trên macOS có Xcode, tiến hành đóng gói IPA trực tiếp..."
if [[ "$(uname -s)" == "Darwin" ]] && command -v xcodebuild >/dev/null 2>&1; then
  NIKSIGN_BUNDLE_ID="$BUNDLE_ID" bash scripts/build-ios.sh
  echo "==> Đã đóng gói thành công: dist/NiKSign-unsigned.ipa (Bundle ID: $BUNDLE_ID)"
  exit 0
fi

echo "==> [3/4] Đang ở môi trường Linux/Codespaces — chuẩn bị đẩy lên GitHub để đóng gói qua GitHub Actions..."
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git init
  git branch -M main
fi

git add Native Vendor Tests scripts web docs project.yml .github README.md LICENSE THIRD_PARTY_NOTICES.md VALIDATION.md FEATURES.md DEPENDENCIES.md upstream-lock.json dependencies-vendor-lock.json
if ! git diff --cached --quiet; then
  git commit -m "$COMMIT_MSG"
fi

if git remote get-url origin >/dev/null 2>&1; then
  CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo main)"
  git push -u origin "$CURRENT_BRANCH"
else
  echo "Lưu ý: Chưa cấu hình git remote 'origin'. Chạy: git remote add origin <URL_REPO_GITHUB> rồi chạy lại script."
  exit 0
fi

echo "==> [4/4] Kích hoạt workflow đóng gói IPA trên GitHub Actions..."
if command -v gh >/dev/null 2>&1; then
  gh workflow run "$WORKFLOW_NAME" -f bundle_id="$BUNDLE_ID"
  echo "==> Đã gửi lệnh chạy workflow '$WORKFLOW_NAME' với Bundle ID: $BUNDLE_ID"
  echo "==> Xem tiến trình tại tab Actions của repository hoặc chạy: gh run watch"
else
  echo "==> Đã push mã nguồn. Mở tab Actions trên GitHub -> 'Build NiKSign' -> 'Run workflow' để nhận file NiKSign-unsigned.ipa."
fi
