# Tiến độ nâng cấp đã chốt

Phạm vi: 1B 2C 3B 4B 5C 6B 7B 8B 9B 10C. Đặc tả/tiêu chí: APPROVED-UPGRADE-SCOPE.md.

Base: 099f0b087ed537b38ee25e6e6f8041052a78354d. Nhánh: codex/niksign-upgrades.
P0 của nhánh codex/niksign-handoff-final còn chờ workflow 44148347210; chưa có build iOS được xác nhận tại base. Không báo hoàn tất phát hành khi hai lượt chưa qua.

| Mốc | Trạng thái | Bằng chứng còn cần |
|---|---|---|
| P0 / 10C: 2-pass sạch | Đang chờ runner | Swift/Xcode/IPA thật |
| P1: job/journal/đầu ra an toàn | Đã viết, chờ kiểm định | SigningJobsSmoke + output ZIP fixtures + build |
| P2: 3B chứng chỉ + 1B queue | Đã viết và qua core tests Linux; chờ Apple tests/Xcode/device | Fixture Security/X509, UI, ký thiết bị |
| P3: 4B tệp + workspace | Chưa triển khai bổ sung | Editors/tab/trash/backup |
| P4: 2C IPA chuyên sâu | Chưa triển khai bổ sung | Từng bộ sửa/diff/restore |
| P5: 5C patch lifecycle | Chưa triển khai bổ sung | Xung đột/history/restore/device |
| P6: 6B OTA | Có mã cần xác minh | Hai lượt compile + iPhone |
| P7: 7B nguồn | Có nền, chưa hoàn tất | Tải tệp/hash/cancel/thư viện |
| 8B: Cơ bản/Nâng cao | Đã viết; chờ Xcode/UI | Persistence và chuyển chế độ trên iPhone |
| 9B/10C: backup/report/QA | Có nền, chưa hoàn tất | Giao dịch/report/redaction/tests |

Mỗi mốc phải cập nhật file này với commit, test thật, lỗi còn lại và bước tiếp theo. Các lựa chọn đã chốt không cần hỏi lại. Không nới quyền iOS hoặc hứa cài/đọc container khi chưa có bằng chứng trên thiết bị.

## Mốc 1 — job và hàng đợi (mã đã viết, chưa gọi hoàn tất QA)

- Tách signing models Foundation, job snapshot/journal có schema, commit atomically trước cập nhật UI, bảo toàn journal hỏng, chuyển việc đang chạy thành interrupted khi mở lại.
- Queue tuần tự, chọn nhiều IPA, chứng chỉ/tùy chọn riêng, thử lại/hủy an toàn, không ghi mật khẩu vào journal; ký một IPA cũng dùng queue và đồng bộ metadata kết quả.
- Signer kiểm cancellation ở các bước và khi giải nén, không ngắt giữa native Zsign; output tạo staging, kiểm cấu trúc/CRC rồi publish. Validator không khẳng định Apple chấp nhận chữ ký/cài đặt.
- Chặn xóa IPA gốc khi job chưa kết thúc; lỗi ghi journal không báo success giả.
- Thêm SigningJobsSmoke và fixture cấu trúc IPA đầu ra. Source/dependency checks và bash syntax/whitespace qua; các test Swift mới chưa chạy ở thời điểm cập nhật.
- Tiếp theo: chạy CI và sửa lỗi; triển khai 3B compatibility, loại phân phối, expiry/UDID/entitlements và nối preflight vào signer/queue.

### Kiểm thử mốc 1 đã chạy trên Swift Linux 6.1.2

- SigningJobsSmoke: PASS (snapshot bất biến, ID trùng, recovery, lỗi commit giữ nguyên trạng thái, journal hỏng không bị xóa).
- FileToolsSmoke: PASS, gồm fixture validator đầu ra đúng/sai Bundle ID, thiếu tài nguyên ký và executable không phải Mach-O; không kiểm mật mã chữ ký.
- Parser Swift của các file UI/queue/signer: PASS cú pháp, **không** thay kiểm tra type của SwiftUI/UIKit bằng Xcode.
- ZIPFoundation 0.9.20 trên Linux có cảnh báo manifest về PrivacyInfo.xcprivacy chưa được khai báo resource. Giữ nguyên cảnh báo để đối chiếu; chưa đạt gate native 0 cảnh báo.
- P0 workflow cũ bị hủy do cấp runner; phải chạy Xcode cho nhánh nâng cấp và xử lý lỗi nếu có.

## Mốc 2 — phân tích chứng chỉ (đã viết, chưa hoàn tất gate Apple)

- Tách certificate models; bổ sung validity của cert, loại phân phối, UDID và entitlements có kiểu. Sửa TeamIdentifier khác App ID prefix; không nhầm seed prefix với Team ID.
- Compatibility core kiểm bundle exact/wildcard, profile/cert expiry, not-before, cert/profile mismatch, UDID và loại phân phối. Không biết UDID/không chọn IPA thì hiển thị chưa kiểm tra, không giả thông tin thiết bị.
- Nối phân tích vào picker/chi tiết chứng chỉ, lỗi chặn hiển thị ở chi tiết IPA và signer kiểm tra lại từ p12/profile thật. Snapshot UDID vào options của job để đổi Settings không thay đổi công việc đã xếp hàng.
- Signing options có schema/default decoding để đọc dữ liệu cũ, từ chối version chưa hỗ trợ. Store chứng chỉ bảo toàn index hỏng, chặn import/remove khi chưa đọc được, cho xuất index khôi phục.
- CertificateCompatibilitySmoke trên Swift Linux: PASS; SigningJobsSmoke có migration options: PASS; parser UI/store: PASS cú pháp. Bổ sung fixture macOS kiểm ngày X509, prefix/Team ID, typed entitlements và index hỏng; các fixture Security này chờ runner.
- NiKPlistValue giữ bool/integer/data/date/array/dictionary, round-trip binary plist; giới hạn 64 cấp/100.000 mục. Core tests round trip/bounds PASS.
- Phân tích này offline, chưa xác minh Apple CMS/thu hồi; không tuyên bố cài được trước kiểm thử iPhone. P0 và gate hai lượt Xcode vẫn là điều kiện phát hành.
- Tiếp theo: xử lý CI nếu có lỗi; triển khai 9B workspace/backup/diff rồi 4B editors/tab/trash, sau đó 2C.

## Mốc 3 — nền tảng khôi phục tệp (đang nối UI)

- Recovery store có root policy/symlink guard, SHA-256, snapshot chống stale edit, backup trước ghi và journal trước đổi tệp; giữ POSIX permissions. File editor tối đa 32 MB ở backend, tổng backup 256 MB.
- Restore không tự ghi đè phiên bản mới; backup lỗi/thiếu bị từ chối và giữ lịch sử để thử lại. Prepared records được đối chiếu sau gián đoạn, không tự ghi lên tệp chưa rõ trạng thái.
- Xóa backup cần xác nhận mất khả năng restore; dùng tombstone và index transaction, khôi phục folder nếu bị ngắt trước commit. Không xóa nội dung tệp đích khi dọn backup.
- FileRecoverySmoke trên Swift Linux đã PASS: SHA-256 chuẩn, snapshot/backup, stale edits, restore conflict/retry, quyền file, ba điểm lỗi ghi, journal trước ghi, root/symlink, backup/index hỏng, recovery sau gián đoạn; test dọn backup/tombstone cũng đã PASS.
- Có controller nền và màn lịch sử trong Settings. Các API Apple NSFileCoordinator/CryptoKit và UI chờ CI; Linux dùng sha256sum trong harness, ứng dụng Apple dùng CryptoKit.
- Tiếp theo: hoàn tất editor text/JSON/plist có preview thay đổi và backup tự động; nối menu tệp rồi triển khai tab/favorites/trash.

## Mốc 4 — editor text/JSON/plist (WIP trong workspace, CHƯA có trong commit GitHub)

- Workspace /workspace/NiKSign-upgrades mất kết nối trong lúc chuẩn bị checkpoint. Không reset/xóa workspace khi trở lại.
- WIP: Native/Models/NiKEditableTextDocument.swift, Native/Views/NiKTextEditorView.swift, Tests/TextDocumentSmoke.swift; thay đổi Native/NiKPreviewUI.swift (editorDoc + tap text), Native/Services/NiKRecoveryController.swift (refresh lịch sử khi write lỗi), Native/Signer.swift (Zsign.checkSigned), scripts/audit-ios.sh (chạy test editor).
- Có kiểm JSON/plist, định dạng, review vùng thay đổi giới hạn, xác nhận bỏ draft; lưu qua snapshot/backup/journal/SHA-256. No-op giữ nguyên byte, không tạo backup thừa.
- Editor giới hạn 2 MB; binary plist giữ binary. Đã phát hiện Date có phần lẻ bị XML truncation, parser XML không chấp nhận fractional date: guard round-trip từ chối sửa trường hợp mất dữ liệu. Không gọi đây là typed tree editor hoàn chỉnh.
- TextDocumentSmoke đã chạy Swift Linux 6.1.2 PASS, gồm nested fractional Date bị chặn, no-op, Data/Date/Bool, JSON lỗi và diff bounds. Chưa có kết quả parse cuối sau bản sửa guard do workspace ngắt; chưa typecheck UIKit.
- Khi workspace trở lại: đối chiếu git diff trước; lấy commit remote mới bằng fetch. NiKPreviewUI.swift có thay đổi remote 8B và local editor, phải giữ cả hai; NiKSettingsView.swift remote 8B. Không reset --hard làm mất WIP.
- Zsign bridge pinned gọi completion đồng bộ trước trả về; checkSigned chỉ kiểm tra theo zsign, không chứng minh Apple chấp nhận cài.
- Cập nhật handoff này cùng checkpoint editor sau khi khôi phục môi trường và chạy lại kiểm tra cần thiết.

## Mốc 5 — 8B giao diện Cơ bản/Nâng cao

- Thêm nik.interfaceMode, mặc định basic, lưu độc lập nik.mode (sign/tools/both). Chọn trong Settings hoặc nút chuyển ngay ở tùy chọn IPA.
- Cơ bản gồm tên/Bundle ID/version/cert/ký; Nâng cao hiện các chỉnh sửa hiện có. Chuyển chế độ không reset options và không đụng snapshot hàng đợi.
- Luôn hiện tóm tắt các tùy chọn nâng cao đang áp dụng ở cả hai chế độ để không ký với thiết lập bị ẩn.
- Đây là sửa UI qua GitHub khi workspace unavailable; chưa chạy kiểm thử UI/typecheck Xcode. Commit sẽ kích hoạt audit hai lượt. Không ghi PASS khi chưa có bằng chứng.
- Run 44156319150 (c7ee74c) đã có runner, source-checks PASS, bước hai audit đang chạy ở lần kiểm tra gần nhất. Chưa có IPA xác nhận.
- Còn tiếp: phục hồi/checkpoint editor; xử lý kết quả CI; tab/favorites/trash; workspace typed plist + components/diff/undo (2C); patch lifecycle (5C); tải nguồn (7B); report/redaction và gate thiết bị (9B/10C).

## Mốc 6 — 10C báo cáo chẩn đoán theo danh sách trường cho phép

- Thêm báo cáo JSON có schema: phiên bản app/iOS, đếm trạng thái, tối đa 1.000 job gần nhất (số thứ tự riêng trong báo cáo, state, phần trăm, thời gian, cờ có output/lỗi), đếm trạng thái recovery. Không serialize trực tiếp job/recovery.
- Loại khỏi bản xuất: tên app/tệp/cert, đường dẫn/URL, UUID/UDID, options/credentials, nội dung file, raw error/log/step. Phiên bản chỉ chấp nhận chữ số và dấu chấm. Progress/time không hữu hạn hoặc ngoài giới hạn được chuẩn hóa.
- Settings có màn xem trước chính xác JSON rồi ShareLink; không gửi tự động lên mạng. Bản xuất đặt ở temporary directory.
- Thêm DiagnosticsSmoke với sentinel trong options/path/UDID/error/log/digest/ID để phát hiện lộ dữ liệu; fixture giới hạn 1.005 job và NaN/duration bất thường. Nối test vào hai lượt audit.
- Chưa thực thi test mới vì workspace unavailable; cần Xcode/Swift CI trước khi xác nhận. Báo cáo không thay xác minh trust/cài đặt/hệ thống, không tự khẳng định gate build đã qua. Recovery counts là snapshot đang nạp, chưa báo được tình trạng storage unavailable riêng (cần bổ sung ở controller).
- Khi khôi phục workspace, merge scripts/audit-ios.sh giữ cả TextDocumentSmoke local và DiagnosticsSmoke remote. NiKSettingsView.swift remote chứa cả 8B và report. Không làm mất editor WIP của mốc 4.
