# Bản build đã xác minh: 5229db4

- Commit: 5229db481a891a4b1e1fc7853ba48884f5e8b409
- Workflow: https://github.com/joinalex1122/NiKSign-Build/actions/runs/44210893692
- Job iOS: 134488700385, macos-15-intel, Xcode 16.4, SDK iPhoneOS18.5.
- Cả hai lượt clean audit/build cùng commit: success, zero warning/error diagnostics trong toàn bộ pass logs.
- BUILD SUCCEEDED lần 1: 2026-11-18 00:59:40 UTC; lần 2: 01:06:45 UTC.
- Hai IPA đã được tải về và chạy lại scripts/verify-ipa.py: Mach-O arm64 MH_EXECUTE, Bundle ID, localizations và ZIP CRC đều đạt. IPA chưa ký.

Artifact IPA/source: https://github.com/joinalex1122/NiKSign-Build/actions/runs/44210893692/artifacts/14386558398

| Tệp | SHA-256 |
|---|---|
| Artifact ZIP | 5a33fd1904df73b1028e0704f724df46b237e5822f76289c653da8360d1e6fef |
| Pass 1 IPA | 945050812cc0788adc69d9647d519328d5909bdb95b5e3cdb1547287c8da8916 |
| Pass 2 IPA | 713089a10b4b34e5b14636413b24b40c2a6ad2b080b60615af0ecf4e39ba2b2d |

Bản local: /workspace/NiKSign-verified-builds/5229db4/. Tên IPA NiKSign-5229db4-pass1-unsigned.ipa và NiKSign-5229db4-pass2-unsigned.ipa.

Bản này có các mốc 1–7: queue/jobs, certificate assessment, recovery, editor, 8B, diagnostic allowlist và library index protection. Chưa chứa nguồn/tải ứng dụng của mốc 8, các cờ storage/dọn download của mốc 9, nhiều tab/yêu thích mốc 10 hoặc các phần nâng cấp viết sau đó.

Không dùng gate này để gán PASS cho commit mới. Chưa xác minh ký/cài iPhone, HTTPS trust/OTA trên iPhone hoặc quyền truy cập hệ thống iOS 27.2.
