# Bản build đã xác minh: 4460603

Commit: 446060385fe4192560c739b14d6a2ad07aba650d.
Workflow: https://github.com/joinalex1122/NiKSign-Build/actions/runs/44213739009
Job iOS: 134498309615, macos-15-intel, Xcode 16.4 / SDK iPhoneOS18.5.

Hai clean audit/build đều PASS, zero warning/error diagnostics trong full pass logs. BUILD SUCCEEDED lúc 2026-11-18 01:21:08 UTC và 01:28:49 UTC. Fixtures source/HTTP/cancel/hash/tab cũng chạy PASS cả hai lượt trên macOS. Hai IPA đã tải về và chạy lại scripts/verify-ipa.py, kiểm arm64 executable/Bundle ID/localizations/ZIP CRC.

Artifact: https://github.com/joinalex1122/NiKSign-Build/actions/runs/44213739009/artifacts/14388591883
Artifact ZIP SHA-256: 5099504fa77b2db22007184b5f450efc8bc7c94ac18b9a9dd10c4f53b37a24f1

| IPA | SHA-256 |
|---|---|
| pass1 | 6776d967b80647e09db408292cc8c996e909e0fc143ac6bbf12fc22733b8427f |
| pass2 | 5eadf476a0b7a003dcf3ad74a331411d190d2ee7d2adc9acb8141a102bf2965c |

Local: /workspace/NiKSign-verified-builds/4460603/.
Phạm vi: mốc 1–10 (queue/cert/recovery/editor/8B/report/library index/source downloads/storage flags/stale download cleanup/tabs/favorites/hidden). Không chứa mốc 11 file properties, mốc 12 mutation reservations, mốc 13 trash core hoặc các thay đổi sau commit này.

IPA chưa ký. Chưa có kết quả ký/cài iPhone, trust/OTA trên iPhone hoặc truy cập hệ thống iOS 27.2. Gate này không thay gate cho commit viết sau.
