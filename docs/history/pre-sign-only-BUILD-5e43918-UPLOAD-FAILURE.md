# Kết quả build 5e43918 — upload thất bại

- Commit: 5e43918a24b56d1a0a8228c6f33a3e3a81e4f07a.
- Run: https://github.com/joinalex1122/NiKSign-Build/actions/runs/44235522878
- Job iOS: 134570694577. Workflow kết luận failure vì upload; source-checks success.
- Hai clean audits/build đều PASS: BUILD SUCCEEDED 2026-11-18 04:24:14 UTC và 04:35:26 UTC; full audit logs có zero warning/error diagnostics.
- PatchSchema9Smoke gồm crypto import/update/tamper PASS cả hai lượt, certificate harness đã biên dịch với OCSP service. verify-ipa.py PASS arm64/ZIP/Bundle ID com.niksign.app/localizations trên runner.
- Upload IPA/source CreateArtifact thất bại ETIMEDOUT lúc04:36:45 UTC; upload diagnostics thất bại ENOTFOUND lúc04:37:16 UTC. Không phải lỗi biên dịch, không sửa app để che lỗi mạng.
- Không có IPA của commit này đã tải/xác minh lại tại workspace, chưa có checksum artifact. Không gọi workflow success hoặc đưa IPA cũ dưới tên mới.
- Cần chạy lại workflow với upload retries và tải/xác minh artifact sau khi upload đạt.
