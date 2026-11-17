# Kiểm tra lỗi tiếp sau bản bàn giao đã chốt

## Lỗi hạ tầng đã xác minh

Run 44135683138: source-checks success; cả hai job macOS 26 bị hủy trước khi chạy bước nào. Annotation ghi rõ `The job was not acquired by Runner of type hosted even after multiple attempts` và cảnh báo thiếu công suất macOS arm64. Không có log biên dịch để kết luận Swift đã lỗi hoặc đã qua.

Workflow được đổi lại macos-15-intel, hai lần audit chạy tuần tự trong cùng một job. Mỗi lần xóa riêng sản phẩm build được sinh tự động, chạy kiểm tích hợp/dependencies/tests và build từ source, kiểm warning/error của cả log audit. IPA chỉ upload sau khi cả hai lần qua; artifact diagnostics không chứa IPA khi gate thất bại.

## Lỗi mã đã sửa trong lần rà soát này

- Callback nhận kết nối của listener cũ có thể còn nằm trong hàng đợi MainActor sau stop/restart. Callback hiện kiểm tra đúng listener hiện hành; phần nhận header cũng kiểm tra kết nối vẫn thuộc phiên hoạt động. Kết nối cũ bị đóng thay vì phục vụ dữ liệu sau stop.
- Chuyển SecIdentity sang identity TLS có thể trả nil nhưng mã vẫn tạo listener. Hiện báo lỗi ngay.
- Mã sinh X.509 bỏ qua lỗi gán version/serial/ngày/key/CN/issuer và lỗi tạo/thêm extension. Hiện kiểm tra kết quả, dọn tài nguyên và từ chối tạo profile khi không có đủ cấu trúc chứng chỉ bắt buộc. Kiểm thử chứng chỉ hiện có xác minh purpose TLS, địa chỉ IP và DER/profile khi runner hoạt động.

## Bằng chứng hiện có

Kiểm tích hợp, dependency, 5 test minizip, 6 test mô hình Patch v9, 7 test IPA verifier, 4 test JavaScript, bash syntax và git diff whitespace đã qua trên Linux. Chưa xác minh compile Swift/Xcode, TLS handshake hoặc cài đặt trên iPhone tại mã mới. Phải cập nhật bằng kết quả workflow thực tế; không coi thông báo này là chứng nhận không còn lỗi.

Phạm vi nâng cấp người dùng đã chốt vẫn là 1B 2C 3B 4B 5C 6B 7B 8B 9B 10C. Lần sửa này chỉ xử lý lỗi và QA hiện tại, không tuyên bố đã triển khai toàn bộ roadmap.
