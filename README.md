# NiKSign 3.3-dev — Hoàn thiện bộ tính năng 3105 2.0 & nâng cấp toàn diện Sign IPA

Bản này ghép cây nguồn công khai của 3105 tại commit
`a72617ed4c764a65d8aac1e91aca95231e72a2cb`, bổ sung công cụ ký IPA và các module
tham khảo tài liệu 3105 2.0. Chưa xác nhận tương đương đầy đủ với bản phát hành 3105.

## Sửa lỗi và build — 2026-11-17

- Sửa lệnh `lipo` để đóng gói IPA arm64 sau khi Xcode biên dịch.
- Patch v9 lưu bản sao lưu trước khi ghi tệp, chặn áp dụng lại khi chưa Restore,
  giữ các mục khôi phục thất bại để thử lại. Giới hạn 32 MiB/tệp và 128 MiB/giao dịch.
- Giảm bộ nhớ kiểm tra IPA bằng đọc header và kiểm tra CRC theo luồng.
- Máy chủ nội bộ chỉ phục vụ HTTP; chưa cung cấp cài OTA qua HTTPS.
- GitHub Actions chạy test Swift rồi build **NiKSign-unsigned.ipa**. Chưa ký hoặc
  kiểm thử các tính năng hệ thống trên iPhone. Xem [chi tiết](docs/reliability-build.md).

## Các module bổ sung 3.3 (cần kiểm thử trên thiết bị)

1. **Workspace Schema v9 (`Application/` + `AppGroup/` + `settings.json` — `NiKPatchV9Engine.swift`):**
   - Tạo và đồng bộ cấu trúc thư mục `Documents/Patches/<Tên_Patch>/` gồm `settings.json`, vùng `Application/<bundleID>/...`, vùng `AppGroup/<group.id>/...` và hỗ trợ đọc vùng cũ `SystemAppGroup/<systemgroup.id>/...`.
   - Định vị container `AppGroup` qua `MCMActivateContainerPath(7, groupID, true, &err)` kết hợp quét fallback `/private/var/mobile/Containers/Shared/AppGroup`.
   - Hỗ trợ đầy đủ các kiểu trường trong `settings.json` (`string`, `boolean`, `integer`, `double`, `date`, `data` với `utf8`/`base64`, `options`, `multiline` và công tắc `canRemove`).
   - Bộ trộn (Merge Engine) Plist & JSON động: nhận diện tên tệp `%3105_Overwrite%`, xóa key với `%3105_Remove%`, ghi đè nhánh Dictionary với `%3105_Overwrite%: true`, và tìm/đọc/ghi chính xác key biến thiên theo từng máy bằng `%3105_MatchPrefix%` (kèm giao dịch sao lưu & rollback tự động).
2. **Trình quản lý & cài đặt gói Dialer `.3105pass` (`NiKDialerService.swift`):**
   - Hỗ trợ mở trực tiếp tệp `.3105pass` từ ứng dụng Tệp hoặc nhập trong tab **3105 2.0 → Dialer (.3105pass)**.
   - Tự động phân loại biến thể phím **Sáng (Light)**, **Tối (Dark)** và **Chữ đậm (Bold)**, áp dụng vào `Library/Caches/TelephonyUI` và khôi phục nguyên trạng từ bản sao lưu.
3. **Footnote màn hình khóa, Supervised & Gói tính năng Cleaner (`NiKSystemFeaturesService.swift`):**
   - Chỉnh sửa và khôi phục `LockScreenFootnote` trong `SharedDeviceConfiguration.plist`.
   - Bật/tắt trạng thái `IsSupervised` và `OrganizationName` trong `CloudConfigurationDetails.plist` kèm sao lưu/hoàn tác.
   - Cho phép cài đặt hoặc gỡ tính năng **Dọn dẹp (3105 Cleaner)** đồng bộ với trang chủ và mục Đã cài.

## Cập nhật 3.2: Luồng Sign IPA, Tweak & xuất tệp

- **Quản lý chứng chỉ (`NiKCertificateStore.swift`):** Lưu nhiều bộ `.p12` + `.mobileprovision`, mật khẩu trong Keychain, kiểm tra khớp X.509 DER và đếm ngược ngày hết hạn.
- **Tùy biến IPA & Chèn Tweak (`Signer.swift`, `NiKDylibInjector.swift`):** Đổi Bundle ID (kèm App Extensions), tên hiển thị, phiên bản, `MinimumOSVersion`, bật `UIFileSharingEnabled`, giải nén `.deb` lấy `.dylib` và chèn `LC_LOAD_DYLIB` / `LC_LOAD_WEAK_DYLIB`.
- **Máy chủ HTTP & Kho AltSource (`NiKLoopbackServer.h/.m`, `NiKAltSourceView.swift`):** Phục vụ IPA và manifest nội bộ, giữ background task ngắn hạn và tích hợp trình duyệt kho AltSource JSON. Cài OTA cần nơi lưu trữ HTTPS thực tế; đổi domain không cung cấp TLS.
