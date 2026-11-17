# Tiến độ nâng cấp đã chốt

Phạm vi: 1B 2C 3B 4B 5C 6B 7B 8B 9B 10C. Đặc tả/tiêu chí: APPROVED-UPGRADE-SCOPE.md.

Base: 099f0b087ed537b38ee25e6e6f8041052a78354d. Nhánh: codex/niksign-upgrades.
P0 của nhánh codex/niksign-handoff-final còn chờ workflow 44148347210; chưa có build iOS được xác nhận tại base. Không báo hoàn tất phát hành khi hai lượt chưa qua.

| Mốc | Trạng thái | Bằng chứng còn cần |
|---|---|---|
| P0 / 10C: 2-pass sạch | Đang chờ runner | Swift/Xcode/IPA thật |
| P1: job/journal/đầu ra an toàn | Đã viết, chờ kiểm định | SigningJobsSmoke + output ZIP fixtures + build |
| P2: 3B chứng chỉ + 1B queue | 1B đã nối UI; đang làm 3B | Fixture, UI, ký thiết bị |
| P3: 4B tệp + workspace | Chưa triển khai bổ sung | Editors/tab/trash/backup |
| P4: 2C IPA chuyên sâu | Chưa triển khai bổ sung | Từng bộ sửa/diff/restore |
| P5: 5C patch lifecycle | Chưa triển khai bổ sung | Xung đột/history/restore/device |
| P6: 6B OTA | Có mã cần xác minh | Hai lượt compile + iPhone |
| P7: 7B nguồn | Có nền, chưa hoàn tất | Tải tệp/hash/cancel/thư viện |
| 8B: Cơ bản/Nâng cao | Chưa triển khai bổ sung | Persistence/UI |
| 9B/10C: backup/report/QA | Có nền, chưa hoàn tất | Giao dịch/report/redaction/tests |

Mỗi mốc phải cập nhật file này với commit, test thật, lỗi còn lại và bước tiếp theo. Các lựa chọn đã chốt không cần hỏi lại. Không nới quyền iOS hoặc hứa cài/đọc container khi chưa có bằng chứng trên thiết bị.

## Mốc 1 — job và hàng đợi (mã đã viết, chưa gọi hoàn tất QA)

- Tách signing models Foundation, job snapshot/journal có schema, commit atomically trước cập nhật UI, bảo toàn journal hỏng, chuyển việc đang chạy thành interrupted khi mở lại.
- Queue tuần tự, chọn nhiều IPA, chứng chỉ/tùy chọn riêng, thử lại/hủy an toàn, không ghi mật khẩu vào journal; ký một IPA cũng dùng queue và đồng bộ metadata kết quả.
- Signer kiểm cancellation ở các bước và khi giải nén, không ngắt giữa native Zsign; output tạo staging, kiểm cấu trúc/CRC rồi publish. Validator không khẳng định Apple chấp nhận chữ ký/cài đặt.
- Chặn xóa IPA gốc khi job chưa kết thúc; lỗi ghi journal không báo success giả.
- Thêm SigningJobsSmoke và fixture cấu trúc IPA đầu ra. Source/dependency checks và bash syntax/whitespace qua; các test Swift mới chưa chạy ở thời điểm cập nhật.
- Tiếp theo: chạy CI và sửa lỗi; triển khai 3B compatibility, loại phân phối, expiry/UDID/entitlements và nối preflight vào signer/queue.

### Kiểm thử mốc 1 đã chạy trên Swift Linux 6.1.2

- SigningJobsSmoke: PASS (snapshot bất biến, ID trùng, recovery, lỗi commit giữ nguyên trạng thái, journal hỏng không bị xóa).
- FileToolsSmoke: PASS, gồm fixture validator đầu ra đúng/sai Bundle ID, thiếu tài nguyên ký và executable không phải Mach-O; không kiểm mật mã chữ ký.
- Parser Swift của các file UI/queue/signer: PASS cú pháp, **không** thay kiểm tra type của SwiftUI/UIKit bằng Xcode.
- ZIPFoundation 0.9.20 trên Linux có cảnh báo manifest về PrivacyInfo.xcprivacy chưa được khai báo resource. Giữ nguyên cảnh báo để đối chiếu; chưa đạt gate native 0 cảnh báo.
- P0 workflow cũ bị hủy do cấp runner; phải chạy Xcode cho nhánh nâng cấp và xử lý lỗi nếu có.
