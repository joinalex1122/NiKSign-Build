# Sửa lỗi provisioning của native Zsign

Nguồn gốc: claration/zsign c4ba9da4283031c07efa03bce42c4b8602d22e73, src/bundle.cpp. Bản upstream có SignFolder chỉ ghi profile khi bRemoveProvision=true; GenerateCodeResources xóa file nếu cùng cờ=true. Vì vậy false không nhúng, true nhúng rồi xóa.

Bản local sửa điều kiện ghi ở SignFolder thành !bRemoveProvision. Call removeProvision=false. File profile được đặt trước khi resource sealing, CodeResources chứa hash profile đúng. Không append profile sau ký và không bỏ output validator.

Local package được ghim nguồn và hash trong Vendor/Zsign/UPSTREAM.json, dependencies-vendor-lock.json; license MIT kèm theo. Các nguồn không đổi được so hash gốc; bundle.cpp được hoàn nguyên có kiểm hash để chứng minh patch duy nhất. Project dùng package path Vendor/Zsign, không dùng remote binary chưa sửa.

Test thực native: python3 Tests/zsign_provisioning_test.py trên macOS. Linux cần --macho /path/to/owned-MachO; fixture không được thực thi, chỉ được ký bởi native engine. Biên dịch C++17/-Werror, link OpenSSL host. Dùng ad-hoc signer để không cần private key thật. Tái hiện cả hai cờ trên source gốc, xác minh bản sửa giữ/xóa đúng; exact/wildcard/mismatch IDs giữ nguyên; SHA256 CodeResources và nguyên bytes profile có NUL đều đúng. Thử nghiệm này không chứng minh Apple CMS/OCSP/khả năng cài lên iPhone.

Lần chạy Linux trong phiên PASS12 ca với owned NiKSign arm64 Mach-O. Apple regression và build của commit mới vẫn phải chạy trước phát hành.
