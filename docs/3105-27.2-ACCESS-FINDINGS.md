# Đối chiếu truy cập 3105 trên iOS27.2 — mốc28

## Bằng chứng người dùng

- 3105 gốc: 2.2 Beta1, iOS27.2.0/build24B119. Người dùng xác nhận đã áp dụng patch thành công trên cùng máy.
- Settings của bản gốc ghi Cách truy cập: worse_query, App Group: Có; chú thích nói không cần ghép đôi/VPN cho patch, dọn dẹp và duyệt dữ liệu.
- Application hiển thị ID com.apple.mobile.MobileHouseArrest. Việc liệt kê app riêng lẻ không chứng minh read/write, nhưng xác nhận patch thành công là bằng chứng thiết bị có đường truy cập hoạt động. Không phủ nhận báo cáo này bằng bảng hỗ trợ của repo2.0 cũ.

## Đối chiếu mã và tài liệu

- Nguồn tác giả: https://github.com/forcequitOS/worse_query — README mô tả iOS26.0–26.7.2/27.2, cần App Group container do app kiểm soát. Một số container ứng dụng/daemon/extension/shared/system trên iOS27 được hỗ trợ; không phải quyền toàn bộ filesystem.
- Mã tham khảo tích hợp: https://github.com/liliansouza1490-alt/3105-ios-worse-query-only26-27-2.0.1 , commit55ca388c34ddb2b2a809f184e61c3ebf34afbe33. File exploit/worse_query.m/h và ContainerStore.grantContainerAccess có hướng App Group trước legacy. Đây là fork tham khảo, chưa chứng minh là source đúng IPA2.2 Beta1 của người dùng. Không chạy hoặc nhập mã fork này vào NiKSign trong mốc28.
- Repo YangJiiii/3105 hiện maina72617e/release2.0, không tìm thấy implementation pairing/lockdown/usbmux trong các nguồn mã được rà. Không khẳng định ghép đôi trong Settings của người dùng do repo này tạo.
- Apple Developer Mode: https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device — cho phép chạy/debug dev-signed app và liên quan pairing; không tự trao quyền sửa container app khác. Ảnh đã bật Developer Mode.

## Khác biệt NiKSign

NiKSign hiện chỉ có tuyến MHA/bad_query và kernel cũ, chưa có worse_query. Bundle ID riêng com.niksign.app không tự cấm worse_query: điều kiện quan trọng là một App Group hợp lệ được profile/chữ ký cấp và container thực mở được. Không cần đổi tên peer hoặc giả App Group trong Info.plist. Không kết luận bắt buộc enterprise từ README2.0 cho tuyến2.2 mới; phải kiểm quyền profile thực.

Mốc28 thêm Settings→Truy cập3105, đọc entitlement App Group của chính tiến trình qua SecTask runtime, phân biệt thiếu quyền với API đọc thất bại; đối chiếu containerURL của các nhóm đã khai báo trong chữ ký. Không đọc pairing records, private keys hoặc dữ liệu app khác. Chưa chạy exploit hoặc sửa cache App Group.

Ngăn tuyến legacy tự/manual chạy trên27.2 chỉ vì flag isSupported=true: current policy candidate không đồng nghĩa kernel/backend hiện tại phù hợp. Hiển thị lý do cần worse_query thay vì thử kernel cũ. Signing/OTA/workspace không bị thay thế bằng status hỗ trợ giả.

## Việc tiếp theo cho Gemini/Codex

1. Gate Xcode mốc28, người dùng đọc kết quả App Group trong NiKSign thực đã ký/cài. Nếu không có quyền, cần profile cho phép nhóm riêng và signer giữ entitlement; thêm plist không đủ.
2. Khi có App Group hợp lệ, tích hợp worse_query đúng phiên bản, on-demand grants cho các container được hỗ trợ, đồng bộ lease/token release và truy cập metadata/patch transaction; không công bố full root. Giữ custom Bundle ID theo yêu cầu.
3. Nguồn PoC tham khảo có thao tác thay Library/Caches bằng symlink rồi dọn. Trước tích hợp phải thiết kế bảo toàn cache/journal/recovery, không copy mù vào nhóm đã chứa dữ liệu.
4. Thử đọc và ghi hồi phục một tệp thử thuộc app mục tiêu, rồi thử patch/restore và App Group. Không lấy build success hoặc nhãn App Group: Có làm chứng cứ đã có quyền ghi.
