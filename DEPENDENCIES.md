# Dependency của NiKSign

Các revision và giấy phép đầy đủ nằm ở `Native/Licenses/components.json`. `project.yml` ghim các package; `dependencies-vendor-lock.json` kiểm tra byte nguồn native và `server-overlays.json` chỉ rõ thay thế tương thích máy chủ.

| Thư viện | Vai trò |
|---|---|
| Zsign (MIT) | Ký Mach-O/CMS và resource seal; nguồn local ghim tại `Vendor/Zsign` |
| OpenSSL (Apache-2.0) | Mật mã cho signer, PKCS12 và chứng nhận HTTPS cục bộ |
| minizip (Zlib) | Kiểm tra ZIP trước khi giải nén |
| ZIPFoundation (MIT) | Giải nén/đóng gói IPA với CRC |
| MachOKit (MIT) | Đọc Mach-O, cờ mã hóa, chữ ký/entitlements |
| ArArchiveKit (MIT) | Đọc archive deb/ar |
| SWCompression (MIT) | Giải nén/đọc tar trong deb |
| GCDWebServer (BSD-3-Clause) | HTTP loopback cho tải hồ sơ tin cậy và chia sẻ tệp; HTTPS OTA dùng Network.framework |

BitByteData 2.0.4 là dependency bắc cầu của SWCompression được ghim để giữ tương thích iOS 17. Framework Apple dùng Foundation, SwiftUI/UIKit, Security, Network, CoreImage, CryptoKit và AppIntents từ SDK. AppIntents được liên kết để bộ tạo metadata Xcode 16 hoạt động đúng; không có capability truy cập ngoài sandbox.

Zsign có các thay đổi native được ghi rõ hash gốc, hash sau sửa và replacements trong `Vendor/Zsign/UPSTREAM.json`: giữ profile trước khi seal, tạo application-identifier cụ thể cho từng bundle từ App ID seed trong profile, XML/DER nhất quán, kiểm tra đúng giá trị get-task-allow, dùng CPU/VM macro SDK trên Apple. Không đổi wildcard hợp lệ của quyền không liên quan. Kiểm tra dependency khôi phục các byte gốc để so hash.
