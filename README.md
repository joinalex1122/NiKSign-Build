# NiKSign — IPA resign tool

NiKSign là ứng dụng SwiftUI cho iPhone/iPad, dùng Zsign để ký lại IPA bằng chứng chỉ của người dùng. Giao diện có ba tab **Ký IPA / Tệp / Cài đặt**, hỗ trợ tiếng Việt/Anh và giao diện sáng/tối/theo hệ thống.

- Lưu nhiều bộ `.p12` + `.mobileprovision`, mật khẩu trong Keychain; chọn chứng chỉ riêng cho từng IPA.
- Ký ngay hoặc ký hàng loạt qua hàng đợi có nhật ký bền vững, hủy/thử lại/xóa công việc.
- Đổi tên, Bundle ID, phiên bản, Minimum iOS; quản lý App Extensions và chèn `.dylib`/`.deb` vào IPA.
- Duyệt nguồn AltSource/Feather JSON, kiểm tra SHA-256 nếu nguồn cung cấp, tải vào thư viện hoặc thêm thẳng hàng đợi với chứng chỉ được chọn.
- Quản lý **Ứng dụng đã ký**, xuất IPA, cài OTA cục bộ qua HTTPS với manifest đúng metadata, liên kết Safari và QR.
- Kiểm tra thu hồi bằng OCSP, đếm ngược hạn sớm hơn của chứng chỉ/profile, cảnh báo khi còn dưới 7 ngày.

Đây là công cụ ký lại IPA cùng nhóm chức năng với AltStore/Sideloadly/ESign. NiKSign không tự cấp chứng chỉ và không thay thế điều kiện provisioning của iOS. Ký thành công không bảo đảm một profile bất kỳ được iOS cho phép cài. Tệp của ứng dụng được quản lý trong sandbox NiKSign hoặc qua bộ chọn tài liệu iOS.

## Build

Yêu cầu macOS, Xcode, XcodeGen, Homebrew OpenSSL 3 và pkgconf:

```sh
brew install xcodegen openssl@3 pkgconf
python3 scripts/check-integration.py
python3 scripts/check-dependencies.py
bash -n scripts/*.sh
xcodegen generate
for nik_pass in pass1 pass2; do bash scripts/audit-ios.sh "$nik_pass"; done
```

Workflow `.github/workflows/build.yml` chạy **hai lượt audit/build sạch liên tiếp** theo yêu cầu kiểm chứng hiện tại, chỉ xuất IPA của lượt cuối, tạo `NiKSign-unsigned.ipa` cùng bản nguồn. `scripts/build-ios.sh` dùng `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO`, mặc định Bundle ID `com.niksign.app`; có thể đặt `NIKSIGN_BUNDLE_ID` trong namespace của bạn. IPA build ra chưa có chữ ký cài đặt.

## Cài OTA cục bộ

Sau khi ký, chọn **Cài qua HTTPS** trong kết quả/hàng đợi hoặc **Ứng dụng đã ký**. Lần đầu, mở **Cài đặt → Tin cậy & Cài IPA**, tải hồ sơ HTTPS trong Safari, cài hồ sơ rồi bật tin cậy đầy đủ trong Cài đặt iOS. Hồ sơ chỉ chứa chứng nhận công khai do máy này tạo; khóa riêng ở Keychain.

Liên kết/QR `127.0.0.1` chỉ hoạt động trên chính iPhone đang chạy NiKSign. Máy chủ không phát tệp sang LAN; cần giữ ứng dụng chạy khi iOS tải IPA. iOS có thể dừng máy chủ khi hết thời gian nền. Bộ đếm manifest/IPA thể hiện yêu cầu tải, không xác nhận cài đặt hoàn tất. Tin cậy HTTPS và chứng chỉ ký IPA là hai việc riêng.

Xem [FEATURES.md](FEATURES.md), [VALIDATION.md](VALIDATION.md), [DEPENDENCIES.md](DEPENDENCIES.md) và [bàn giao refactor](docs/SIGN-ONLY-REFACTOR.md). Mã NiKSign tiếp tục dùng giấy phép GPL-3.0; thông báo các thư viện được giữ trong [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
