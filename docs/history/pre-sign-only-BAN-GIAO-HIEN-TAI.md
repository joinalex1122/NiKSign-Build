# Bàn giao NiKSign — 18/11/2026

## Trạng thái
Đã triển khai đến mốc 16; chưa hoàn tất toàn bộ lựa chọn 1B 2C 3B 4B 5C 6B 7B 8B 9B 10C. Chi tiết và giới hạn từng mốc tại UPGRADE-PROGRESS.md; phạm vi gốc tại APPROVED-UPGRADE-SCOPE.md.

## Mã nguồn và kiểm chứng
- Nền nguồn: d30b78d014507c80ef487f8330da3ee18e65c295, thêm thay đổi cancellation/token của plist trong gói nguồn này.
- Nhánh: codex/niksign-upgrades; checkpoint: handoff/niksign-upgrade-checkpoints. Chưa merge main.
- Run typed editor: https://github.com/joinalex1122/NiKSign-Build/actions/runs/44226714053 — đang chạy lúc kiểm tra.
- IPA đính kèm thuộc 4d9b7e25f6642deef9596f7667466afa00bb67c7, gồm mốc 1–14 và Trash UI. Không chứa typed editor mốc 15–16. Hai lượt Xcode sạch; xem VERIFIED-BUILD-4d9b7e2.md.
- IPA unsigned, cần ký bằng chứng chỉ/profile phù hợp trước khi cài. Không có chứng chỉ/profile trong gói.

## Tiếp tục theo thứ tự
1. Theo dõi run d30b78d, tải diagnostics khi thất bại, sửa lỗi thực tế; không che warnings. Chạy gate cho cả thay đổi cancellation cuối.
2. Hoàn thiện 2C: workspace từ bản IPA gốc bất biến/hash, safe extraction và bundle scan, chỉnh Info/entitlements/component, diff/undo, xuất change set, nén thật, validate và đưa queue ký. Typed editor hiện chỉ mở plist riêng.
3. Hoàn thiện 4B: clipboard dùng chung các tab, nền I/O, dọn staging sau crash; kiểm tra UI thùng rác/tabs trên máy thật.
4. Hoàn thiện 5C: trạng thái bản vá, phát hiện xung đột, lịch sử và recovery trên nền PatchV9 transactional engine; giữ giới hạn và backup.
5. 6B/9B: thử TLS/OTA với iPhone, kiểm tra recovery qua kill/relaunch và lỗi đĩa; chưa có bằng chứng hỗ trợ truy cập hệ thống/app đã cài trên thiết bị 27.2.
6. 10C: hai clean audits cho commit cuối, checksum IPA, ghi rõ SHA nguồn và kết quả thiết bị. Không dùng gate commit cũ cho code mới.

## Quyết định giao diện đã chốt
Chọn ký / công cụ 3105 / cả hai lần đầu, đổi trong Settings. Phong cách iOS sáng/tối/hệ thống. Chứng chỉ hỏi lần đầu, có Để sau, nhiều chứng chỉ và chọn riêng mỗi IPA. Basic/advanced độc lập, default basic; giữ tùy chỉnh nâng cao.

## Kiểm tra gói
SHA256SUMS liệt kê checksum các tệp giao. source.zip chứa file tracked hiện tại cùng sửa đổi được bàn giao; không chứa .git, toolchain hay build cache. Không chứa p12/password.
