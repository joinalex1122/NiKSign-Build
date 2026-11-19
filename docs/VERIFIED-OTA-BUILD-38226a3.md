# Xác minh bản sửa cài IPA — 19/11/2026

- Code commit: 38226a33a0c325a11e4d47dbecd75358b81d1c5f
- Workflow: https://github.com/joinalex1122/NiKSign-Build/actions/runs/44454201571 — completed/success, MỘT audit/build; không có pass2.
- IPA: NiKSign-OTA-Fix-38226a3-unsigned.ipa, 7,677,488 bytes.
- SHA256: 72b585777541191cde0b4626052807ed9602ab4157027fbb943b8074428db975
- Artifact gốc: NiKSign-unsigned-IPA-macos-15-intel, ID14496424189; ZIP chỉ có đúng một IPA ở audit-results/pass1/.
- App Bundle ID com.niksign.app; arm64 MH_EXECUTE; ZIP CRC/localization verifier PASS sau tải lại.
- Log build: 0 warning:, 0 error:, BUILD SUCCEEDED.
- Actual ObjC/GCDWebServer regression PASS: full/range/HEAD, health, route isolation404, counters, stop, input unchanged.
- Snapshot/recovery fixtures, model/download tests và Apple Security/chain regression PASS.

## Thay đổi và giới hạn

Tiêu chuẩn dùng HTTPS manifest tĩnh của SignTools và HTTP IPA loopback trên iPhone; không upload IPA/chứng chỉ/UDID/app metadata. Dịch vụ thấy IP mạng + cổng; lần đầu có consent trong app. Nested itms URL encode đúng; manifest bounded64KB và không theo redirect; snapshot private giữ bytes ổn định khi HTTP response đang drain.

Manifest tĩnh có tên Local app/IDcom.foo.bar theo contract nguồn. UI nói rõ hộp thoại có thể hiện Local app, IPA thật không đổi tên/ID. Chưa có phép thử cài trên iPhone27.2 từ môi trường này; không khẳng định mọi iOS/IPA chấp nhận metadata placeholder hoặc mọi provisioning đều hợp lệ. Còn lựa chọn HTTPS nội bộ với metadata thật. HTTPS preflight trong app không chứng minh daemon chấp nhận user root.

## Thử trên máy thật

Cài bản NiKSign mới đã ký, mở Ứng dụng đã ký → Garena → Cài đặt → Tiêu chuẩn → Đồng ý & Cài đặt. Xác nhận hộp thoại iOS nếu hiện Local app. Xem Yêu cầu IPA trên iPhone và xác nhận app thực sự xuất hiện/chạy. Có thể dùng IPA Garena đã ký sẵn, không cần ký lại để kiểm tra đường cài. Nếu đã tải nhưng không cài: xử lý lỗi chữ ký/profile riêng; không bỏ validator, không tự đổi ID.

Mốc31 trong UPGRADE-PROGRESS ghi các trạng thái pending/failed theo lịch sử. Kết quả success trong tài liệu này thay thế pending Apple gate của mã đến38226a3; không thay thế kết quả thiết bị.

Nguồn giao thức: https://github.com/SignTools/ota-me
