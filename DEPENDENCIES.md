# NiKSign 3.2-dev — thư viện tích hợp, Tweak Injection & OTA

Ngày đối chiếu: 2026-11-16. Danh mục máy đọc được, commit, trạng thái và giấy
phép đầy đủ nằm trong `Native/Licenses/components.json` và các file cạnh đó.
**Chưa build/link bằng Xcode; chưa kiểm chứng chạy trên iPhone.**

| Thư viện | Phần đã thêm & nâng cấp ở 3.2 | Giới hạn/trạng thái |
|---|---|---|
| OpenSSL | Ghim package 3.6.5000 thay cho phụ thuộc transitive không ghim; Zsign dùng crypto | Apache-2.0; SwiftPM tải XCFramework upstream khi build |
| minizip | Nhúng unzip/ioapi từ zlib v1.3.1; kiểm tra metadata trước khi ZIPFoundation giải nén IPA | Không mở archive mã hóa; kiểm tra CRC/path vẫn do bước giải nén hiện có |
| MachOKit | Parse Mach-O/fat; đọc trạng thái mã hóa, RPATH, số load command; chặn ký lại binary còn mã hóa; kết hợp `NiKDylibInjector` kiểm tra dylib | Không giải mã FairPlay binary |
| ArArchiveKit | Đọc danh mục `.deb`/`.ar` tên ngắn và tách `data.tar.*` trong `NiKDylibInjector` để lấy `.dylib` | Hỗ trợ `.deb` chuẩn tên ngắn (tối đa 64 MB khi chèn tweak) |
| SWCompression | Đọc metadata `.tar` và giải nén `data.tar.{gz,xz,lzma,tar}` trong `NiKDylibInjector` | Giữ 4.8.6 hỗ trợ iOS 17 |
| ZIPFoundation | Giữ 0.9.20 để giải nén/đóng IPA | Kết hợp với preflight minizip |
| GCDWebServer | Phục vụ IPA và `manifest.plist` động qua loopback kèm liên kết `itms-services://` và giữ background task ngắn hạn | Cần domain HTTPS hợp lệ trỏ về 127.0.0.1 (như `*.backloop.dev`) khi iOS kiểm tra SSL của `itms-services://` |
| Zsign | Giữ revision c4ba9da… của nhánh Swift Package đã kiểm tra | Ký lại ứng dụng chính, App Extensions và các `.dylib` đã chèn |
| TrollFools | Nguồn tham khảo canonical, revision, giấy phép | Tham khảo; NiKSign dùng `NiKDylibInjector` riêng cho IPA |
| ellekit | Nguồn tham khảo `tealbathingsuit/ellekit`, revision và license | Người dùng có thể chèn `libellekit.dylib` qua mục Chèn Tweak |
| optool | Nguồn tham khảo BSD-2-Clause | Logic chèn `LC_LOAD_DYLIB` / `LC_LOAD_WEAK_DYLIB` 64-bit đã được viết native bằng Swift trong `NiKDylibInjector.swift` |

## Truy cập các phần mới trong 3.2

Trang chủ → **NiKSign · Ký IPA & sửa tệp**:

- Tab **Ký IPA**:
  - **Quản lý chứng chỉ**: Lưu nhiều cặp `.p12` + `.mobileprovision`, mật khẩu lưu trong Keychain, tự động kiểm tra khớp chứng chỉ X.509 DER và đếm ngược ngày hết hạn.
  - **Tùy biến gói IPA**: Đổi Bundle ID (kèm cập nhật đồng bộ App Extensions), đổi tên hiển thị, phiên bản, `MinimumOSVersion`, bật `UIFileSharingEnabled`, xóa `UISupportedDevices` và gỡ `PlugIns`/`Watch`.
  - **Chèn Tweak (`.dylib` / `.deb`)**: Chọn trực tiếp tệp `.dylib` hoặc gói `.deb`; tự động giải nén `data.tar.*`, sao chép `.dylib` vào `Frameworks/` và chèn `LC_LOAD_DYLIB` vào Mach-O 64-bit.
  - **Máy chủ OTA & Manifest**: Tạo `/<token>/manifest.plist` và liên kết `itms-services://?action=download-manifest&url=...` với `UIBackgroundTaskIdentifier`.
- Tab **Kho IPA**:
  - Thêm nguồn JSON theo chuẩn AltStore / Feather Source, tìm kiếm và bấm **Tải & Ký** để đưa thẳng IPA sang tab **Ký IPA**.
- Tab **Thông tin**:
  - **Kiểm tra Mach-O / DEB / TAR** và **Giấy phép mã nguồn mở**.

## Kiểm tra

```bash
python3 scripts/check-integration.py
python3 scripts/check-dependencies.py
python3 Tests/minizip_test.py
```
