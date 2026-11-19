# Chức năng NiKSign

| Mục | Hành vi |
|---|---|
| Thư viện IPA | Nhập từ Files/Open In, kiểm tra ZIP/CRC, đọc metadata và biểu tượng, giữ bản gốc |
| Chứng chỉ | Nhiều bộ p12/profile; mật khẩu Keychain; chọn theo từng IPA/công việc |
| Hàng đợi | Snapshot chứng chỉ/tùy chọn; chạy tuần tự; hủy an toàn; thử lại từ gốc; xóa lịch sử/toàn bộ; không tự ký lại khi mở app |
| Tùy chỉnh | Tên, Bundle ID, phiên bản, Minimum iOS, chia sẻ tệp, UISupportedDevices, App Extensions/Watch |
| Chèn thư viện | Dylib hoặc trích dylib từ deb; liên kết thường/yếu; vẫn cần IPA không mã hóa và quyền hợp lệ |
| Nguồn IPA | AltSource/Feather JSON, tải có giới hạn/hủy, kiểm tra SHA-256 và Bundle ID của nguồn, nhập hoặc tải & xếp hàng |
| Kết quả | Mục Ứng dụng đã ký; xuất/chia sẻ; cài HTTPS từ kết quả và hàng đợi |
| OTA | Manifest riêng theo metadata thật, snapshot IPA bất biến, HTTPS loopback, kiểm tra tin cậy, trang Safari, QR/link, bộ đếm yêu cầu |
| Trạng thái chứng chỉ | OCSP trực tuyến thủ công và định kỳ khi app hoạt động; tốt/thu hồi/chưa xác minh; đếm ngược và cảnh báo dưới 7 ngày |
| Tệp | Duyệt Documents/IPALibrary/Signed của NiKSign, xem/sửa tệp nhập, khôi phục/thùng rác |
| Giao diện | Ba tab Ký IPA/Tệp/Cài đặt, sáng/tối/hệ thống, tiếng Việt/Anh |

Profile không khớp Bundle ID tạo cảnh báo, không chặn riêng bước ký. Các lỗi khóa riêng, chứng chỉ/profile hết hạn, ZIP hỏng, mã hóa hoặc chữ ký đầu ra thiếu dữ liệu vẫn phải xử lý. Khả năng cài đặt do iOS quyết định; app không tạo quyền ngoài provisioning.

Kiểm tra OCSP tự động: lần đầu khi chọn chứng chỉ, sau đó tối đa mỗi 6 giờ với trạng thái tốt; thử lại sau 15 phút khi chưa xác minh/lỗi mạng; trạng thái thu hồi kiểm tra lại sau 24 giờ. Kiểm tra chỉ chạy khi app đang hoạt động. Dữ liệu OCSP tốt quá 24 giờ hiển thị chưa xác minh.
