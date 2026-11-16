# NiKSign 2.1 — bản nguồn đã bổ sung chức năng thật

Bản này thay giao diện mô phỏng trong ZIP ban đầu bằng ứng dụng SwiftUI và
bản web sửa tệp. **Chưa có IPA đã biên dịch hoặc ký trong gói nguồn này.**
Môi trường thực hiện không có Xcode, nên native chưa được xác minh build hay
chạy trên iPhone. Các workflow macOS dưới đây là bước kiểm chứng tiếp theo.

## Đã triển khai

- Native: mở JSON, XML/binary plist từ ứng dụng Tệp; sửa và xuất bản sao.
- Native: tạo mẫu, mở và xuất lại gói `3105PATCH` envelope v1–v3 bằng codec
  thực tế của YangJiiii/3105. Sửa metadata/rules ở dạng JSON; replacementData
  là Base64. Gói có mật khẩu được mở bằng mật khẩu, cập nhật và giữ bảo vệ
  ban đầu. Không cho sửa nội dung gói private; không lưu content key lâu dài.
- Native: chọn IPA, .p12, .mobileprovision, nhập mật khẩu; giải nén có giới hạn,
  kiểm tra executable Mach-O, gọi Zsign thực và xuất IPA. Lỗi được trả về;
  không dùng bộ đếm giờ để giả lập ký. Certificate/profile đã nhập được xóa
  sau lần ký hoặc bằng nút Xóa. Mật khẩu không lưu vào UserDefaults hay log.
- Web: mở/sửa/xuất JSON và XML plist, sửa key có kiểu dữ liệu, tải xuống hoặc
  chia sẻ tệp qua trình duyệt. Bản nháp lưu tại máy chỉ khi bật tùy chọn.
- Build GitHub Actions macOS: tạo project, chạy kiểm tra codec, build arm64,
  kiểm tra binary và xuất artifact IPA unsigned.
- Publish NiKSign Web: workflow xuất bản web qua GitHub Pages khi bạn chạy.

## Giới hạn cần hiểu

Bạn chỉ có iPhone và chưa có chứng chỉ. Vì vậy **bản web là phần có thể dùng
mà không cài IPA**. Build unsigned không thay thế bước ký và cài app native.

- Không có mã nguồn ESign gốc đã xác minh để ghép. Tham khảo Feather và dùng
  thư viện Zsign MIT. Xem THIRD_PARTY_NOTICES.md để biết nguồn/commit/license.
- Không đăng nhập Apple ID, không cấp chứng chỉ, không ký miễn phí thay Apple,
  không có trình cài OTA. IPA được ký không đồng nghĩa iOS sẽ chấp nhận cài.
- Không truy cập dữ liệu app khác, không ghép exploit MHA-C2/kernel, không có
  quyền Apple riêng tư. Bundle ID native là `app.niksign.personal`.
- Không tuyên bố đầy đủ định dạng workspace schema v9, ZIP .3105, repository,
  Dialer, wallpaper, cleaner hay chức năng khôi phục trên thiết bị của 3105.
- `.3105` dạng JSON trong prototype cũ được nhận là JSON và xuất `.json`.
- Giới hạn native: tệp sửa 16 MB, IPA 1 GB nén và 1 GB sau giải nén, 50.000 mục;
  web: tệp nhập 8 MB. Giới hạn thiết bị/RAM vẫn có thể thấp hơn.
- Native chỉnh sửa trên RAM; hãy xuất trước khi đóng app. Không có tự lưu
  bản nháp native. Bản web không đọc binary plist hoặc gói mã hóa 3105PATCH.

## Làm bằng iPhone: đưa nguồn lên GitHub

Cần tài khoản GitHub và hạn mức Codespaces/Actions. Chưa có repository đích
được cung cấp, nên gói này chưa được đẩy lên tài khoản hay chạy Actions.

1. Tạo repository trên github.com, bật tạo README.
2. Mở **Code → Codespaces → Create codespace** bằng Safari; bật giao diện
   desktop nếu cần. Codespaces chỉ dùng để tải mã; không build iOS trên Linux.
3. Trong File Explorer của Codespaces, chọn **Upload** và tải ZIP nguồn này
   từ ứng dụng Tệp vào thư mục gốc repository.
4. Trong Terminal của Codespaces, chạy (đổi tên ZIP nếu iPhone đổi tên tệp):

```bash
unzip -o NiKSign-2.1-source.zip
node Tests/web.test.js
git add Native Tests scripts web project.yml .github .gitignore README.md LICENSE THIRD_PARTY_NOTICES.md VALIDATION.md
git commit -m "Implement NiKSign file tools, Zsign signing and iOS build"
git push
```

ZIP có các tệp ở ngay gốc, gồm cả thư mục ẩn `.github`; không chỉ tải riêng
HTML nếu muốn có workflow native. Không tải .p12, mật khẩu hoặc profile lên repo.

## Dùng bản web từ Safari

1. Vào repository **Settings → Pages → Source → GitHub Actions**.
2. Vào **Actions → Publish NiKSign Web → Run workflow**.
3. Mở URL trong kết quả deployment; dùng Safari → Chia sẻ → Thêm vào Màn hình
   chính. Bản này không có service worker/offline cache được cam kết.
4. Chọn **Mở tệp**, sửa, rồi **Lưu vào Tệp** hoặc **Chia sẻ bản đã sửa**.

Nếu Pages không khả dụng cho loại repo/tài khoản của bạn, có thể đưa nguyên
thư mục `web/` lên dịch vụ static HTTPS khác. File `NiKSign-Web-Standalone.html`
đi kèm có CSS/JS nhúng sẵn; dùng để tải lên static host hoặc xem ở trình duyệt
cho phép chạy HTML cục bộ. Ứng dụng Tệp trên iPhone không bảo đảm chạy JavaScript
của HTML tải về, nên không coi mở ZIP/Quick Look là cài bản web.

## Build IPA từ iPhone

1. Vào **Actions → Build NiKSign → Run workflow**.
2. Chờ job macOS hoàn thành; nếu lỗi, xem bước cụ thể trong log.
3. Tải artifact **NiKSign-unsigned-IPA**, giải nén bằng ứng dụng Tệp.
4. IPA chỉ có thể cài sau khi có cách ký/provisioning phù hợp. Không có chứng
   chỉ và công cụ sideload đã cài thì quy trình này dừng ở IPA unsigned.

Workflow không nhập bí mật và không tạo chứng chỉ. Không có quyền private
entitlement trong bản này. Native signer hỗ trợ chứng chỉ hợp lệ kèm profile,
không nhất thiết là chứng chỉ doanh nghiệp; nhưng không cấp quyền 3105 nâng cao.

## Build trên Mac nếu sau này có

```bash
brew install xcodegen
bash scripts/build-ios.sh
```

Chọn Xcode có iOS SDK trước khi chạy. Khi build để cài bằng Xcode, chọn Team và
Bundle ID phù hợp với profile của bạn. Release artifact unsigned nằm ở
`dist/NiKSign-unsigned.ipa`.

## Kiểm tra

Xem VALIDATION.md. Unit test web và kiểm tra Chromium di động đã chạy.
Kiểm tra codec Swift và build arm64 mới được cấu hình trong Actions, chưa
chạy thành công ở phiên này. Không có kiểm tra trên Safari/iPhone thật hay
chứng chỉ thật. Phát hành binary cần kiểm tra tiếp các bước đó.

Phần mã sửa đổi phát hành theo GPL-3.0. Giữ thông báo nguồn và giấy phép
của 3105/Zsign/ZIPFoundation/OpenSSL khi phân phối; cung cấp nguồn tương ứng
cho binary theo điều khoản GPL. Không có chứng chỉ đính kèm.
