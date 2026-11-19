# Kiểm chứng bản Sign IPA

Người dùng đã xác nhận nhánh CI tạm để kiểm chứng refactor 3.4.0 (340). Đang chờ audit/build macOS của nhánh codex/niksign-sign-only-ci. Máy thực hiện hiện tại là Linux, chưa có Xcode/XcodeGen. Kết quả macOS của các bản cũ không xác nhận bản nguồn này.

| Lệnh | Trạng thái hiện tại |
|---|---|
| `python3 scripts/check-integration.py` | PASS: một app entry, metadata/routing và nguồn Sign IPA |
| `python3 scripts/check-dependencies.py` | PASS: 8 thư viện, giấy phép, hash nguồn, các sửa đổi Zsign có thể đối chiếu ngược |
| `bash -n scripts/*.sh` | PASS |
| Swift frontend parse nguồn Native | PASS cú pháp; chưa phải kiểm tra kiểu với iOS SDK |
| `python3 Tests/minizip_test.py` | PASS 5 ca |
| `python3 Tests/verify_ipa_test.py` | PASS 7 ca |
| `xcodegen generate` | BLOCKED, exit 127: command not found trên Linux |
| Xcode build arm64 unsigned | BLOCKED, exit 127: xcodebuild command not found; chưa PASS |

Các kiểm thử thực thi bổ sung đã PASS trên Linux: 20 dòng kết quả Foundation (hàng đợi/model, source download, xử lý tệp, URL/HTML và lịch OCSP), bộ FileTools SwiftPM với nguồn ZIPFoundation thật, kiểm tra native provisioning/CMS của Zsign và tạo/kiểm tra chuỗi TLS với SAN/EKU. FileImport (NSFileCoordinator), QueueRemoval (Combine), PKCS12/Keychain dùng Security và máy chủ Objective-C cần macOS, vẫn nằm trong audit bắt buộc. SwiftPM trên Linux có cảnh báo tài nguyên PrivacyInfo.xcprivacy từ ZIPFoundation; không tuyên bố Linux toàn bộ không cảnh báo.

`scripts/audit-ios.sh` chạy các test Foundation về hàng đợi, chứng chỉ, tệp/khôi phục, tải mạng, OTA URLs và lịch OCSP; kiểm thử native Zsign giữ profile và chữ ký CMS thật; test GCDWebServer, TLS/Keychain/PKCS12 trên macOS; sau đó build và kiểm tra IPA. Workflow chỉ có một lượt audit/build.

Test CMS dùng khóa/chứng chỉ tổng hợp, xác minh chữ ký tách rời, hash trang/special slots, sửa dữ liệu phải thất bại, định danh app/extension và cờ debugging. Chứng chỉ test không được Apple tin cậy; kết quả này không chứng minh IPA cài được trên iPhone.

Chưa kiểm thử trên iPhone: khởi động bản refactor, ký bằng chứng chỉ người dùng, OCSP thực tế, tải/chuyển nền, cài hồ sơ HTTPS và cài OTA qua trình cài iOS. Cần ghi đúng commit, run CI, artifact và kết quả thiết bị trước khi phát hành. Danh sách thay đổi và nhật ký kiểm chứng cuối cùng ở [bàn giao](docs/SIGN-ONLY-REFACTOR.md).
