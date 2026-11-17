# Bàn giao NiKSign — phạm vi nâng cấp đã được người dùng chốt

**Cập nhật:** 17/11/2026, 17:28 UTC (00:28 ngày 18/11 theo GMT+7).
**Mục đích:** giữ toàn bộ quyết định, mã và việc dang dở để một phiên Codex/Gemini hoặc lập trình viên khác tiếp tục nếu phiên hiện tại hết credit. Người dùng yêu cầu viết bàn giao trước; các nâng cấp trong lộ trình bên dưới chưa được coi là đã triển khai.

## 1. Quyết định mới nhất — không hỏi lại

Người dùng đã chọn chính xác:

**1B · 2C · 3B · 4B · 5C · 6B · 7B · 8B · 9B · 10C**

A/B/C là mức độ cộng dồn: B gồm nền tảng A; C gồm A và B. Đây là phạm vi được chốt, không phải danh sách tính năng đã hoàn thành.

| Mục | Mức chốt | Kết quả cần đạt |
|---|---|---|
| 1. Ký IPA | B | Ký từng IPA ổn định và hàng đợi ký nhiều IPA |
| 2. Tùy chỉnh IPA | C | Không gian chỉnh sửa IPA chuyên sâu, có đối chiếu và hoàn tác |
| 3. Chứng chỉ | B | Nhiều chứng chỉ, chọn theo IPA và phân tích mức phù hợp trước ký |
| 4. Quản lý tệp | B | Đủ thao tác cơ bản, nhiều tab, trình sửa và xem tệp nâng cao |
| 5. 3105 | C | Tích hợp đầy đủ, quản lý bản vá, xung đột và lịch sử khôi phục |
| 6. Cài đặt | B | Xuất IPA và HTTPS OTA cục bộ có hướng dẫn, trạng thái thực |
| 7. Kho nguồn | B | Thư viện cục bộ và nhập nguồn/tải ứng dụng vào thư viện |
| 8. Giao diện | B | Thiết kế đã chốt, có mức Cơ bản/Nâng cao |
| 9. Bảo toàn dữ liệu | B | Giữ bản gốc, điểm khôi phục và báo cáo thay đổi/rollback |
| 10. Chẩn đoán/QA | C | Nhật ký, báo cáo và phát hành có hai lượt build sạch được xác minh |

**Không mặc định triển khai thêm:** cấu hình mẫu/hàng loạt tự động kiểu 1C; sao lưu toàn bộ kho mã hóa kiểu 3C/9C; so sánh thư mục/đổi tên hàng loạt kiểu 4C; máy chủ OTA bên ngoài kiểu 6C; quản lý nhiều phiên bản kiểu 7C; cá nhân hóa toàn diện/iPad kiểu 8C. Chỉ làm những phần của các mức này khi thực sự cần cho tính đúng đắn của phạm vi đã chốt, hoặc người dùng bổ sung yêu cầu.

## 2. Trạng thái repository và build — phân biệt thật rõ

- Repo: https://github.com/joinalex1122/NiKSign-Build
- Main kiểm tra gần nhất: **2102677cf29ead0500a9163575b21ba0069099d3**.
- Nhánh đang sửa: **codex/niksign-handoff-final**.
- HEAD của nhánh và ZIP mã nguồn đi kèm: **751208b12b8caf051fbeff890afb750803db1a48**.
- PR nháp: https://github.com/joinalex1122/NiKSign-Build/pull/4 — chưa merge main.
- Workflow mới nhất: https://github.com/joinalex1122/NiKSign-Build/actions/runs/44135683138
- Job source-checks **134224449999: success**.
- Job macOS 26 pass 1 **134224658717: queued**.
- Job macOS 26 pass 2 **134224658804: queued**.
- Các trạng thái trên được đọc lúc bàn giao; người tiếp tục phải đọc lại vì GitHub có thể đã cập nhật.
- **Chưa có lượt biên dịch Swift/Xcode nào hoàn tất cho HEAD 751208b. Chưa có IPA mới của HEAD này.** Không gửi IPA cũ rồi gọi là bản hiện tại.
- Bản cũ đã trực tiếp xác minh BUILD SUCCEEDED: commit `6a1e8ead9600b86264d66c0df9cb7e1e8006e6b7`, workflow https://github.com/joinalex1122/NiKSign-Build/actions/runs/44070680108 . Bản đó vẫn còn cảnh báo và không phải mã hiện tại.
- Các runner macos-15-intel và macos-15 đã chờ lâu; cuối cùng cấu hình chuyển macos-26. macos-14 đã được đối chiếu là ngừng GitHub Actions từ 02/11/2026, nên không dùng lại nhãn đó.
- Một số lượt cũ được hủy trên GitHub; không diễn giải là compiler đã báo lỗi. Không tạo thêm lượt build chỉ để đổi nội dung báo cáo nếu không cần.
- PR #1 đã đóng sẵn. Không cần đóng lại.

**Câu hỏi đang chờ trả lời:** GitHub → Actions của tài khoản có thông báo xác minh, giới hạn sử dụng hoặc thanh toán hay chỉ đang chờ runner? Kết nối hiện tại không đọc được mục quản lý tài khoản. Không giả định có lỗi thanh toán khi chưa có bằng chứng.

## 3. Bối cảnh người dùng và quyết định giao diện cũ

- Người dùng chỉ có iPhone, báo **iOS 27.2 chính thức**. Chưa cài bản hiện tại để thử. Chưa cung cấp p12, provisioning hoặc mật khẩu cho môi trường này.
- Người dùng nói **3105 2 beta 2 hỗ trợ iOS 27.2**, nguồn cung cấp: https://github.com/YangJiiii/3105 . Khi đối chiếu, main upstream `a72617ed4c764a65d8aac1e91aca95231e72a2cb` vẫn chỉ liệt kê iOS 27.0 beta 1–4. Chưa có commit/release cụ thể chứng minh 27.2 trong mã công khai. Ghi nhận thông tin của người dùng; cần kiểm thử thực tế, không tuyên bố đã xác minh.
- Lần mở đầu chọn **Chỉ ký IPA / Chỉ 3105 / Cả hai**. Chỉ hỏi lần đầu, đổi được trong Cài đặt, không mất dữ liệu.
- Tab theo chế độ: **Ký IPA · 3105 · Tệp · Cài đặt**. Thiết kế Capsule kính mờ nổi, viền gradient, bóng đổ. Không thêm nút tròn phụ ở góc dưới phải.
- Native iOS, trắng/đen/theo hệ thống; màu nhận diện navy/cyan/tím theo logo NiKSign người dùng đã gửi. Không tự thay thương hiệu hoặc vẽ lại logo nếu chưa cần.
- Thẻ chính 16pt; hàng tệp thoáng chỉ nổi khung 14pt khi chạm/giữ/chọn; icon bo 10pt; chừa cuối nội dung cuộn 100pt.
- Tệp có 4 mục gốc: Tệp đã nhập, Thư viện IPA, Tệp hệ thống · Chỉ đọc, Dữ liệu ứng dụng đã cài.
- Toolbar tệp chỉ nút `...`, không nút tải xuống phụ, không thêm Trình duyệt tài nguyên vào menu này.
- Chạm IPA: Ký & Cài đặt / Giải nén thành App / Xem trước. Chạm ZIP: Nhập làm Chứng chỉ / Giải nén tại đây / Xem trước.
- Menu nhấn giữ cần đủ Chọn / Sao chép / Cắt / Chuyển đến / Sao chép đến / Đổi tên / Chia sẻ / Hex / Xóa.
- QuickLook luôn có nút Đóng. Chứng chỉ chỉ hỏi nhập lần đầu dùng signer, có **Để sau**; hỗ trợ nhiều bộ, mặc định và chọn riêng từng IPA.
- Mức giao diện **Cơ bản/Nâng cao** ở 8B là lựa chọn độc lập với ba chế độ chức năng trên. Không nhập hai khái niệm thành một.

## 4. Những sửa đã viết và đẩy lên nhánh hiện tại

Các mục này đã có mã nhưng **chưa được Xcode xác nhận tại HEAD cuối**:

1. Khôi phục file SupportPolicy upstream nguyên bản để qua kiểm hash; tạo `Native/Integration/SupportPolicy.swift` làm lớp thay thế. Giữ các phiên bản upstream đã cho phép, bổ sung đúng 27.2.0 làm ứng viên kiểm thử; không cho phép mọi bản iOS 27/28.
2. `upstream-overlays.json` và `server-overlays.json` liệt kê lớp thay thế. Script tích hợp kiểm tra mỗi translation unit upstream được thay đúng chỗ, nguồn gốc còn nguyên. `project.yml` loại bản gốc khi biên dịch bản thay thế; không được compile hai bản cùng tên.
3. Lớp tương thích sửa onChange cũ, cách lấy UIWindowScene, cảnh báo prototype/enum/const/kiểu số và MIME UTType. Không tắt toàn bộ warnings.
4. HTTPS OTA: chỉ bind loopback; giữ identity trong Keychain; chờ listener ready; xử lý GET/HEAD và header phân mảnh, giới hạn header 16 KiB, tối đa 8 kết nối, đóng kết nối sau thời gian giới hạn; IPA truyền từng đoạn 64 KiB; có background task và dọn khi rời màn chi tiết.
5. Tách `NiKLocalTLSIdentity.swift` và `NiKOTAProfile.swift` để dùng cùng mã giữa server và kiểm thử chứng chỉ. Profile chỉ chứa DER công khai; private identity lưu Keychain, không cho vào profile.
6. OpenSSL default/legacy providers sống suốt tiến trình để tránh nhập chứng chỉ gỡ provider đang được thao tác khác dùng. Mật khẩu giữ đúng khoảng trắng; không tự trim rồi lưu mật khẩu sai cho bước ký.
7. Kiểm Info.plist trong IPA giới hạn 1 MiB, kiểm CRC. Xuất IPA vào Documents dùng helper không ghi đè tệp cùng tên.
8. Nối `nik.language` với bộ AppLanguage upstream qua lớp thay thế Localization.swift; bổ sung Việt/Anh và thẻ 16pt/khoảng đáy cho công cụ 3105.
9. Xóa `NiKZipCheck.o`, `ioapi.o`, `unzip.o`, `wallpaper_zip.o` gốc không được project sử dụng; thêm ignore *.o.
10. CI cập nhật checkout/upload-artifact, thêm kiểm thử p12 modern/legacy, chứng chỉ TLS thật, Keychain reload và profile root; hai matrix audit_pass trên cùng source, max-parallel 1; kiểm log compiler và không upload IPA nếu còn warning/error.

**Lưu ý review:** Các file thay thế dài chủ yếu là bản sao nguyên nguồn để sửa API tương thích. Đọc diff với file gốc, không hiểu số dòng thêm là toàn bộ tính năng được viết mới. Nếu compiler mới phát sinh warning, sửa đúng nguyên nhân, không thêm cờ che warning để giả qua gate.

## 5. Đặc tả triển khai từng lựa chọn đã chốt

### 1B — Ký IPA ổn định và hàng đợi

**Cần có:** kiểm IPA/chứng chỉ/profile/Bundle ID trước ký; chọn nhiều IPA; chứng chỉ và tùy chọn riêng mỗi mục; trạng thái chờ/kiểm tra/đang ký/thành công/thất bại/đã hủy; tiến độ từng mục và tổng; xuất kết quả; thử lại mục lỗi; hủy an toàn giữa các bước; bảo toàn đầu vào.

**Nền hiện có:** `SigningService` là actor để tuần tự hóa bộ ký có trạng thái dùng chung. Có thư viện IPA và tùy chọn theo IPA; chưa được coi đã có hàng đợi bền vững đầy đủ.

**Cách làm:** service hàng đợi tách khỏi View; lưu snapshot công việc trước khi chạy; đầu ra staging rồi publish; không dùng try? để báo thành công giả; xử lý khi app bị hệ thống kết thúc. Có thể đánh dấu mục bị gián đoạn để thử lại, không hứa tiếp tục giữa chừng thao tác Zsign khi chưa hỗ trợ.

**Nghiệm thu:** nhiều IPA gồm một tệp hỏng không làm mất kết quả mục khác; cùng tên không ghi đè; hủy không để thư viện trỏ vào đầu ra dở; đổi tab không tạo tác vụ ký thứ hai; lỗi riêng từng mục; thành công chỉ sau kiểm tra IPA đầu ra. Không thuộc phạm vi này: hệ thống mẫu và tự động hóa 1C hoàn chỉnh.

### 2C — Không gian tùy chỉnh IPA chuyên sâu

**Nền tảng A:** đổi tên, Bundle ID, version, icon, cấu hình chia sẻ tệp, URL schemes, quản lý extension/Watch.

**Mức B:** cây Payload/*.app; trình sửa plist giữ đúng kiểu dữ liệu; quản lý framework/dylib/tài nguyên; nhập dylib/deb; phân tích kiến trúc, phụ thuộc và mã hóa; xem diff trước/sau, hoàn tác trước đóng gói.

**Mức C:** workspace riêng theo IPA; nhận diện executable và bundle lồng nhau; chỉnh entitlements có đối chiếu profile; cập nhật/kiểm tra phụ thuộc khi thay thành phần; chọn nén/đóng gói; xuất bộ thay đổi để áp dụng lại có kiểm tra điều kiện đầu vào cho phiên bản IPA khác.

**Cách làm:** dùng mô hình thay đổi có kiểu và nhật ký thao tác; mở rộng `NiKSigningOptions` theo schema có version/migration; lớp phân tích riêng cho bundle/Info.plist/Mach-O. Các bộ sửa không ghi trực tiếp vào IPA gốc. Phiên bản thư viện JSON cũ vẫn đọc được sau thêm trường mới.

**Nghiệm thu:** tên/Bundle ID/profile nhất quán giữa app và bundle con; diff có đường dẫn/giá trị gốc/mới; đổi kiểu plist sai bị từ chối; xóa dylib còn phụ thuộc phải báo; thành phần thêm được ký theo thứ tự đúng; có cấu hình nén thực sự được backend dùng. Entitlement không hợp lệ phải được giải thích; không có công tắc chỉ đổi UI mà backend bỏ qua.

**Giới hạn:** hạ MinimumOSVersion không tự tạo tương thích iOS cũ; entitlement không tự cấp đặc quyền; nhận diện Mach-O bị mã hóa và báo không xử lý được thay vì sửa cờ để giả giải mã. Chưa hứa tương đương/hơn ESign trước khi có checklist và kiểm thử.

### 3B — Kho chứng chỉ và phân tích mức phù hợp

**Cần có:** nhập p12/profile trực tiếp và ZIP; nhiều bộ, đặt mặc định, override theo IPA; kiểm mật khẩu, chứng chỉ có private key, profile đúng định dạng, ngày hết hạn, khớp cert; hiển thị Team ID, Bundle ID pattern, loại phân phối, UDID và quyền profile cho phép. Giải thích bộ nào phù hợp với IPA/thiết bị trước ký.

**Cách làm:** giữ Keychain cho mật khẩu; dữ liệu nhạy cảm có file protection; nhập/lưu index là giao dịch; dọn bản tạm khi lỗi/hủy; không đoán cặp trong ZIP nhiều chứng chỉ; không tự đổi sang chứng chỉ khác nếu bộ đã chọn bị xóa. Thông tin thiết bị không thu được tự động phải có cách nhập rõ ràng, không bịa UDID.

**Nghiệm thu:** modern/legacy p12, password rỗng/có khoảng trắng/sai, ZIP nhiều cặp, cert hết hạn, Bundle ID wildcard/exact, UDID thiếu và cert lệch profile đều có kết quả đúng. Chứng chỉ nhập ở tab Tệp xuất hiện ngay ở signer/Settings. Không khẳng định chưa bị thu hồi chỉ dựa vào hạn dùng.

**Ngoài phạm vi:** nhóm/nhắc hết hạn và sao lưu mã hóa toàn bộ kho kiểu 3C.

### 4B — Quản lý tệp nâng cao

**Cần có:** đầy đủ nhập/tạo/đổi tên/copy/cut/paste/move/delete/share/search/sort; nhiều tab vị trí, yêu thích, hiện ẩn; trình sửa text/JSON/plist; QuickLook; Hex; ZIP an toàn; thuộc tính/dung lượng/hash; thùng rác trong phạm vi app quản lý được.

**Cách làm:** thống nhất model file, clipboard, editor và thao tác nền; đọc File Provider bằng security scope và NSFileCoordinator; staged writes; tránh path traversal/symlink/self-move/ghi đè; kiểm kích thước khi mở editor; lưu atomically; lỗi thao tác phải hiện, không biến lỗi quyền thành thư mục trống.

**Nghiệm thu:** import từ On My iPhone và iCloud; tệp Unicode/trùng tên/lớn; copy/move cùng thư mục và vào thư mục con; chuyển tab giữ vị trí; file editor sai JSON không làm mất bản gốc; ZIP lỗi/CRC/quá giới hạn dọn hết đầu ra dở; QuickLook đóng được; trash khôi phục và xử lý xung đột tên.

**Giới hạn:** trình duyệt chỉ thấy dữ liệu được iOS/quyền thực tế cho phép. Không hứa đọc toàn bộ hệ thống trên máy chưa jailbreak. Không thuộc 4C: so sánh thư mục và đổi tên hàng loạt đầy đủ.

### 5C — Quản lý vòng đời bản vá 3105

**A/B cần có:** tích hợp màn hình cốt lõi, phiên bản hỗ trợ rõ ràng, Việt/Anh và UI thống nhất; Application/AppGroup; trường plist/JSON; nhập/xuất gói; xem trước file/container bị tác động; sao lưu và kết quả từng phần.

**C cần bổ sung:** phát hiện bản vá cùng đích hoặc cùng khóa cấu hình; lịch sử áp dụng/khôi phục; biểu diễn bản vá đang hoạt động; kiểm tra lại khi container/phiên bản app đổi; báo cáo chẩn đoán; kiểm tra điều kiện trước áp dụng lại.

**Cách làm:** mở rộng journal hiện có thay vì một cơ chế ghi độc lập. Phát hiện xung đột tĩnh ở file và đường dẫn khóa plist/JSON; phân biệt xung đột tiềm tàng với xung đột đã biết. Không tự gộp hai thao tác mâu thuẫn. Khi chưa thể biết tác động runtime phải ghi rõ giới hạn.

**Không được phá:** bản sao lưu nguyên bản trước ghi; không ghi đè bản gốc khi apply lặp; giới hạn 32 MiB/file và 128 MiB tổng; rollback lỗi giữa chừng; giữ lại mục restore thất bại để thử lại; guard symlink/duplicate path. Không nới support guard rộng chỉ để UI mở.

**Nghiệm thu:** hai patch cùng file/cùng khóa/khác khóa, app nâng phiên bản hoặc đổi container, apply lặp, thiếu container, lỗi đĩa, restore một phần, xóa patch đang hoạt động. Kiểm tra thành phần thực tế trên iPhone 27.2 riêng với unit tests.

### 6B — HTTPS OTA cục bộ

**A:** xuất/lưu/chia sẻ IPA hợp lệ, giải thích phương thức cài phù hợp chứng chỉ.

**B:** profile tin cậy; chứng chỉ TLS ổn định; hướng dẫn cài profile và bật trust; server loopback; trạng thái chờ/ready/đang phục vụ/thất bại/hết thời gian nền; truyền tệp có giới hạn RAM; theo dõi yêu cầu manifest/IPA; ghi nhận phản hồi hệ thống mở URL.

**Cách làm tiếp:** biên dịch và kiểm thử mã server đã sửa; kiểm DER, SAN, mục đích TLS, profile payload; test handshake/GET/HEAD/header phân mảnh/tệp lớn/cancel/đổi IPA/hết background. Có thể cần chỉnh thiết kế CA/leaf nếu iOS không chấp nhận mô hình hiện tại. Dùng chứng chỉ/profile cài app phù hợp; TLS CA không thay thế chứng chỉ ký IPA.

**Nghiệm thu:** profile xuất trước/sau khởi động app vẫn cùng chứng chỉ; không lắng nghe LAN; token cũ không truy cập được sau đổi phiên; xác nhận tải manifest/IPA; ngừng phục vụ sạch; hướng dẫn thiết bị đúng. Chỉ báo cài thành công khi có bằng chứng phù hợp, không lấy UIApplication.open=true làm kết quả cài.

**Bắt buộc thử iPhone:** iOS có thể hạn chế trust, background hoặc OTA. Nếu cách cài cục bộ không được nền tảng chấp nhận, báo giới hạn và giữ xuất IPA dùng được. Không giả HTTPS trên server HTTP. Không tự thêm máy chủ/domain bên ngoài — đó là 6C, chưa chốt.

### 7B — Thư viện và nguồn ứng dụng

**A:** danh sách/lưới, icon, tìm tên/Bundle ID, nhóm và phân biệt IPA gốc/đã ký.

**B:** nhập URL nguồn theo định dạng hỗ trợ; xem nhà cung cấp, mô tả, phiên bản, dung lượng; tải có tiến độ/hủy; kiểm hash nếu có; đưa IPA đã tải hoàn chỉnh vào cùng luồng nhập/kiểm tra thư viện.

**Cách làm:** tận dụng `NiKAltSourceView.swift`/store hiện có; tách metadata nguồn khỏi hàng đợi tải; URLSession tải ra tệp, không Data toàn bộ; giới hạn redirect/định dạng/dung lượng; staging và validate trước publish. Nêu rõ những định dạng nguồn thực sự đọc được, không ghi hỗ trợ mọi feed.

**Nghiệm thu:** nguồn đúng/sai schema, lỗi mạng/redirect, metadata thiếu, hash sai, tải dở và app bị đóng, tên trùng, tệp không phải IPA. Thư viện chỉ nhận tệp hợp lệ, không tự ký/cài khi chỉ mở nguồn.

**Ngoài phạm vi:** giữ/so sánh nhiều phiên bản và tự áp lại cấu hình kiểu 7C hoàn chỉnh.

### 8B — Giao diện Cơ bản/Nâng cao

**A:** hoàn thiện giao diện cũ đã chốt, toàn bộ vi/en, sáng/tối/system; trạng thái trống/chờ/lỗi; giữ tab/navigation khi đổi tab.

**B:** Cơ bản: nhập IPA → chọn chứng chỉ → ký → xuất/cài. Nâng cao: mở thêm cây IPA, plist, thành phần, entitlements và chẩn đoán. Cùng dữ liệu/backend; đổi mức chỉ thay phần hiển thị, không xóa tùy chọn hoặc thay kết quả ký ngầm.

**Cách làm:** lưu lựa chọn hiển thị riêng; cảnh báo rõ cấu hình nâng cao đang áp dụng ngay cả khi ở Cơ bản; helper dịch dùng cùng `nik.language` và upstream AppLanguage. Không có trường hiển thị thông tin implementation không giúp người dùng quyết định.

**Nghiệm thu:** đổi ngôn ngữ/theme/mức UI không mất job/chứng chỉ/IPA; tiến độ ký đúng khi quay lại tab; Dynamic Type và nút đóng/cancel dùng được; toolbar và khoảng đáy đúng thiết kế. Các tính năng tiếp cận cần cho sử dụng nên làm ngay; không biến thành phạm vi cá nhân hóa 8C toàn diện.

### 9B — Bảo toàn dữ liệu và khôi phục theo công việc

**A:** giữ IPA gốc, không ghi đè ngầm, cleanup tệp tạm theo ownership, xác nhận xóa dữ liệu đáng kể.

**B:** điểm khôi phục trước sửa IPA/apply patch; diff trước/sau; dung lượng backup; trạng thái giao dịch; báo phần đã rollback và phần còn chờ; thử restore lại được sau lỗi.

**Cách làm:** phân biệt bản gốc bất biến, workspace đang sửa, kết quả đã publish. Journal versioned; ghi backup/journal trước ghi đích; kiểm dung lượng khả dụng; recovery sau app chết. Điểm khôi phục của IPA không dùng chung với backup container của 3105 một cách tùy tiện.

**Nghiệm thu:** lỗi mỗi giai đoạn ghi, hết dung lượng, app bị kết thúc, nhập trùng, mất quyền/container, restore vào đích đã đổi. Không báo thành công toàn bộ khi chỉ xong một phần; không xóa backup còn cần dùng; có cách dọn backup được người dùng hiểu rõ.

**Ngoài phạm vi:** sao lưu/khôi phục toàn bộ NiKSign mã hóa kiểu 9C.

### 10C — Chẩn đoán và phát hành có kiểm chứng

**A/B:** log theo công việc/bước/mức lỗi, hướng xử lý; báo cáo IPA/tùy chọn/chứng chỉ ở mức an toàn; chế độ dễ hiểu và kỹ thuật; xuất báo cáo đã che dữ liệu nhạy cảm. Không log private key, mật khẩu, p12, token OTA hoặc URL nhạy cảm đầy đủ.

**C:** hồi quy nhập file/ZIP/p12/chỉnh sửa/khôi phục; hai lượt Xcode sạch từ cùng source cuối, mỗi lượt có source/dependency checks và Swift tests; không warning/error; kiểm IPA thực sau đóng gói; ghi commit SHA, SHA256, phiên bản toolchain và checklist thiết bị.

**Nghiệm thu:** pipeline không upload IPA khi log còn lỗi/warning hoặc thiếu success marker; hai lượt qua trước khi báo hoàn tất; tải artifact thật về chạy verify-ipa.py; kiểm source ZIP khớp commit; công khai giới hạn chưa thử trên thiết bị. Nếu sửa code sau lượt một thì đếm lại. Hai source-checks không thay thế hai lượt compile.

## 6. Thứ tự làm — tránh triển khai tất cả cùng lúc

1. **P0 — Chốt bản đang dang dở:** đọc lại trạng thái workflow, giải quyết runner, chạy compiler và sửa lỗi. Hoàn thành QA hai lượt hoặc báo rõ blocker khách quan. Tải và kiểm IPA thật; đưa bản thử cho người dùng trước.
2. **P1 — Xương sống 10C/9B:** job model, giao dịch, staging, journal, log/redaction, schema/migration. Chỉ tạo cấu trúc cần dùng, không dựng abstraction dư.
3. **P2 — 3B rồi 1B:** kiểm chứng chỉ và queue ký, thử end-to-end bằng IPA/chứng chỉ của người dùng trên máy. Không yêu cầu người dùng gửi private key vào chat.
4. **P3 — 4B và phần workspace của 2C:** file service/editor/plist, backup/diff/undo dùng chung đúng chỗ.
5. **P4 — Hoàn thiện 2C:** bundle con, entitlements, thành phần/Mach-O, nén và xuất bộ thay đổi; mỗi nhóm có fixture và tiêu chí riêng.
6. **P5 — 5C:** kiểm thử 3105 thực tế trên 27.2, rồi lịch sử/xung đột/khôi phục. Có thể làm song song phần model với signer, nhưng không phá transactional engine hiện tại.
7. **P6 — 6B:** ổn định TLS/profile/luồng cài trên iPhone; phần thử thiết bị có thể bắt đầu ngay khi P0 có IPA. Không chờ hoàn thành mọi nâng cấp mới thử OTA.
8. **P7 — 7B:** nguồn và download dùng lại hàng đợi nhập, kiểm tra và thư viện đã ổn định.
9. **8B xuyên suốt:** mỗi tính năng có UI Cơ bản/Nâng cao phù hợp; không để cuối mới chữa toàn bộ ngôn ngữ và trạng thái.
10. Mỗi mốc có bản build kiểm chứng và cập nhật bàn giao; không đợi làm xong mọi mục mới tạo bản khôi phục công việc.

Không cần hỏi lại các mã lựa chọn. Chỉ hỏi khi thiếu thông tin thực sự ảnh hưởng hướng đi, quyền/dữ liệu, dịch vụ bên ngoài hoặc khi kết quả thiết bị phủ định giả định. Tiếp tục các việc độc lập trong khi chờ trả lời.

## 7. Bản đồ mã và kiểm thử

| Vùng | Tệp đang có |
|---|---|
| Root/library/chi tiết IPA | Native/NiKPreviewUI.swift |
| Settings | Native/NiKSettingsView.swift |
| File picker/QuickLook/system files | Native/NiKFilePicker.swift |
| File tools/dashboard | Native/NiKFileViews.swift |
| Copy provider an toàn | Native/NiKFileImport.swift |
| ZIP | Native/NiKArchive.swift, Native/NiKCertZipHelper.swift |
| Signer/options | Native/Signer.swift |
| Chứng chỉ | Native/Dependencies/NiKCertificateStore.swift |
| TLS/OTA/profile | Native/Dependencies/NiKHTTPSOTAServer.swift, NiKLocalTLSIdentity.swift, NiKOTAProfile.swift |
| Binary/archive/IPA inspection | Native/Dependencies/NiKBinaryInspector.swift, NiKArchiveInspector.swift, NiKInspectView.swift |
| Dylib/deb | Native/Dependencies/NiKDylibInjector.swift |
| Nguồn ứng dụng | Native/Dependencies/NiKAltSourceView.swift |
| Patch v9 | Native/Dependencies/NiKPatchV9Engine.swift và workspace service hiện có |
| Hub 3105 | Native/Dependencies/NiK3105V2HubView.swift |
| Nguồn 3105 | Vendor/3105/ThreeOneOSFive — giữ nguyên/đối chiếu khóa hash |
| Lớp thay thế | Native/Integration, Native/UpstreamCompatibility, Native/ServerCompatibility; manifest JSON ở gốc |
| Build/QA | .github/workflows/build.yml, scripts/build-ios.sh, scripts/check-build-log.py |
| Kiểm IPA | scripts/verify-ipa.py, Tests/verify_ipa_test.py |
| Test Swift | Tests/CodecSmoke.swift, PatchV9Smoke.swift, PatchV9TransactionSmoke.swift, FileImportSmoke.swift |
| Test ZIP/file | Tests/FileTools, scripts/test-file-tools.sh |
| Test cert/TLS/profile | Tests/Certificates, scripts/test-certificates.sh |

Tên service/model mới cho queue/workspace/journal chưa chốt cứng; chọn sau khi đọc kiến trúc để tránh trùng service hiện có.

## 8. Những kiểm tra đã chạy và giới hạn bằng chứng

Đã qua ở mã sửa: check-integration, check-dependencies, 5 test minizip C, 6 test mô hình Patch v9 Python, 7 test IPA verifier, 4 test JavaScript; bash syntax, git diff whitespace. Source-checks của commit cuối trên GitHub success. Nguồn ZIP đã kiểm CRC.

Chưa có kết quả cho các test Swift và Xcode ở HEAD cuối vì job chưa có runner. Các test certificate/TLS/profile mới viết dùng cùng mã thật nhưng **chưa chạy**, không được gọi là passed. Kiểm cấu trúc mobileconfig hay OpenSSL verify cũng không thay được kết quả iPhone có chấp nhận profile và cài IPA hay không.

Môi trường local là Linux, không Xcode/Swift đang dùng được cho build iOS. Build được tổ chức qua GitHub Actions. IPA luôn unsigned nếu chưa được ký bằng chứng chỉ/profile phù hợp. Chưa có chứng chỉ người dùng trong workspace.

## 9. Cách tiếp tục ở phiên hoặc công cụ khác

### Có GitHub

1. Clone repo, fetch nhánh `codex/niksign-handoff-final`, đọc HEAD/PR/workflow mới nhất. Không mặc định trạng thái queued còn đúng.
2. Tạo nhánh/worktree riêng nếu có thay đổi của người dùng; không reset hard hay force push đè mã mới.
3. Đọc tài liệu này và `docs/HANDOFF-2026-11-17.md` trong source.
4. Xử lý P0 trước, cập nhật log và bàn giao sau mỗi mốc. Không báo toàn bộ lộ trình đã hoàn tất chỉ vì check-integration pass.

### Chỉ có gói ZIP

- `NiKSign-SOURCE-751208b.zip` chứa source tracked đúng commit 751208b; dependencies Swift Package sẽ được tải khi build.
- Các giấy phép, khóa nguồn và workflow nằm trong ZIP. Không áp lại patch cũ từ gói bàn giao Gemini trước lên source này.
- Có thể tạo repo mới từ ZIP nếu không truy cập repo gốc, nhưng phải ghi rõ nguồn commit và giữ bản quyền/giấy phép.
- `BAT-DAU-LAI.txt` là prompt ngắn để dán vào phiên mới; gửi kèm tài liệu này và source ZIP.

### Workspace hiện tại

- Đang làm: `/workspace/NiKSign-handoff-final` (HEAD 751208b, sạch lúc bàn giao).
- Checkout cũ `/workspace/NiKSign-latest-review` có WIP của giai đoạn trước; không xóa/reset nếu chưa đối chiếu. Nó không phải nguồn ưu tiên của bản hiện tại.
- Gói bàn giao Gemini cũ vẫn là lịch sử, không thay thế gói đã chốt lần này.

## 10. Việc cần ghi lại sau mỗi mốc để chống mất phiên

- Commit/nhánh/PR và link workflow; trạng thái từng gate, log lỗi thật còn lại.
- Các tệp đã sửa/chưa commit, lệnh tiếp theo và điều kiện đang chờ.
- Tính năng đã implement khác với tính năng chỉ có UI hoặc chỉ là roadmap.
- Artifact IPA/source kèm SHA256 và source commit.
- Kết quả thiết bị do người dùng gửi, bao gồm OS build/cách ký/thao tác, không lưu bí mật.
- Quyết định mới của người dùng. Giữ nguyên bộ chọn **1B 2C 3B 4B 5C 6B 7B 8B 9B 10C** trừ khi họ đổi rõ ràng.
