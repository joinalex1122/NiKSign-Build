# Bản build đã xác minh: 4d9b7e2

Commit: 4d9b7e25f6642deef9596f7667466afa00bb67c7.
Workflow: https://github.com/joinalex1122/NiKSign-Build/actions/runs/44222092235
Job iOS: 134526342696, macos-15-intel, Xcode 16.4 / SDK iPhoneOS18.5.

Hai clean audit/build PASS, zero warning/error diagnostics trong full pass logs. BUILD SUCCEEDED lúc 2026-11-18 02:30:52 UTC và 02:42:37 UTC. Fixtures trash/library transaction cũng PASS cả hai lượt trên macOS. Hai IPA đã tải về và chạy lại scripts/verify-ipa.py: arm64 MH_EXECUTE, Bundle ID, localizations, ZIP CRC đều đạt.

Artifact: https://github.com/joinalex1122/NiKSign-Build/actions/runs/44222092235/artifacts/14392916122
Artifact ZIP SHA-256: fa573ceda8e1eca53279fd408443ab4b10abd1f3fb8342672402d492ffe8513b

| IPA | SHA-256 |
|---|---|
| pass1 | 2040d5d01273e9eb35248066bbf9d1e2393d313e3d33533279ec0f9cdc141b4e |
| pass2 | d2eacd2732b01cada985540c2a1f7b8ed76f236ec73c9d7bcbd4077c72b92369 |

Local: /workspace/NiKSign-verified-builds/4d9b7e2/.
Phạm vi: mốc 1–14, đã có properties/hash, mutation reservations và Trash UI/controller/cross-library transaction. Chưa chứa typed plist engine/editor mốc 15–16 hoặc thay đổi viết sau commit này.

IPA chưa ký. Chưa có kết quả ký/cài iPhone, trust/OTA trên iPhone hoặc truy cập hệ thống iOS 27.2. Gate này không thay gate của commit viết sau.
