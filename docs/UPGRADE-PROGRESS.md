# Tiến độ nâng cấp đã chốt

Phạm vi: 1B 2C 3B 4B 5C 6B 7B 8B 9B 10C. Đặc tả/tiêu chí: APPROVED-UPGRADE-SCOPE.md.

Base: 099f0b087ed537b38ee25e6e6f8041052a78354d. Nhánh: codex/niksign-upgrades.
Trạng thái 2026-11-18: 4d9b7e2 đã vượt hai lượt clean audit/Xcode và tạo IPA arm64 unsigned; đã tải và kiểm lại cả hai IPA. Chi tiết hash/link: VERIFIED-BUILD-4d9b7e2.md. Các mốc 15 trở đi vẫn cần gate riêng.

| Mốc | Trạng thái | Bằng chứng còn cần |
|---|---|---|
| P0 / 10C: 2-pass sạch | 4d9b7e2: cả 2 pass sạch + IPA verifier PASS | Gate cho các mốc 15 trở đi; device |
| P1: job/journal/đầu ra an toàn | Core/macOS fixtures và build c7ee74c PASS | Ký/cài thực tế và gate mã mới |
| P2: 3B chứng chỉ + 1B queue | Đã viết và qua core tests Linux; chờ Apple tests/Xcode/device | Fixture Security/X509, UI, ký thiết bị |
| P3: 4B tệp + workspace | Tabs/favorites/source qua 446; properties/reservations/trash đã viết; core PASS | Xcode mới + trash UI/device; clipboard/nền I/O |
| P4: 2C IPA chuyên sâu | Typed plist core đã viết/core PASS | UI, workspace/entitlements/components/diff/package |
| P5: 5C patch lifecycle | Chưa triển khai bổ sung | Xung đột/history/restore/device |
| P6: 6B OTA | Có mã cần xác minh | Hai lượt compile + iPhone |
| P7: 7B nguồn | Tải stream/hash/cancel/parser đã viết, core/network fixtures PASS | Xcode và luồng nhập thật trên iPhone |
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

## Sửa gate sau CI thực tế — run 44156319150 / c7ee74c

- macos-15-intel, Xcode 16.4/iPhoneOS18.5: BUILD SUCCEEDED; build/build.log được validator xác nhận zero warning/error. Đóng gói arm64, ZIP CRC, Bundle ID và localizations PASS.
- Các fixture macOS đã PASS: jobs/migration, certificate compatibility, recovery store, ZIP/output validation, p12 modern/legacy, Keychain TLS identity và mobileconfig, corrupt certificate index. Đây là bằng chứng Apple tốt hơn Linux cho các mốc 1–3.
- Full pass1 audit bị chặn bởi 2 warning deprecation trong Tests/SigningJobsSmoke.swift:44 và Tests/FileRecoverySmoke.swift:104: String(contentsOf:) cần encoding. Đã đổi sang encoding: .utf8; không tắt cảnh báo.
- Chưa chạy pass2 vì gate dừng đúng. Không có artifact IPA phát hành ở run này. Cần run lại commit mới gồm 8B + diagnostics; chưa suy diễn từ build c7ee74c sang code mới.

## Checkpoint phục hồi mốc 4 qua GitHub

- Đã tái tạo và lưu model/editor/test từ nội dung đã đọc trước khi workspace mất kết nối; nối menu/tap và refresh-on-error ở controller. Không còn phụ thuộc workspace để lấy mã editor.
- Cùng logic đã PASS Linux (JSON/plist/no-op/fractional date guard), nhưng bản tái tạo + giới hạn XML hiển thị mới cần chạy CI; không gán kết quả Linux cho typecheck UI mới.
- Giữ cả 8B và diagnostic test trong cùng cây nguồn. scripts/audit-ios.sh chạy cả TextDocumentSmoke và DiagnosticsSmoke.
- Khi workspace trở lại, giữ một bản diff local để đối chiếu; các file editor local về cơ bản đã có remote. Native/Signer.swift local thêm Zsign.checkSigned vẫn CHƯA đưa vào commit remote này, cần kiểm tra/giữ thay đổi đó riêng.
- Các file có WIP local không được reset --hard. Fetch remote rồi so sánh/merge; không push đè nhánh remote bằng HEAD local c7ee74c.
- Mốc 4 chưa hoàn tất 4B: còn tab/favorites/trash/hash UI và typed plist (2C). Gate hai lượt sạch vẫn chưa qua ở commit mới.

## Mốc 7 — tiếp tục 2026-11-18: đồng bộ, kiểm thử và bảo toàn thư viện

- Workspace hoạt động trở lại. Đã giữ WIP trong git stash (Preserve editor WIP before recovering remote checkpoints 2026-11-18), fetch/fast-forward từ c7ee74c lên a2618d3. Không áp toàn bộ stash vì remote đã chứa editor/8B/report.
- DiagnosticsSmoke và TextDocumentSmoke bản hiện tại đều chạy PASS bằng Swift Linux 6.1.2; parser toàn bộ Native PASS. Chưa thay cho typecheck iOS.
- Giữ bổ sung local Zsign.checkSigned sau ký từ stash; cần CI xác nhận API. Không coi đó là chứng minh Apple trust.
- Phát hiện library.json hỏng có thể bị save/import ghi đè bằng danh mục mới. Tách library models + index store: load lỗi thì chặn mutation, xuất index để khôi phục, giới hạn 16 MB/5.000 mục, reject ID/tên trùng, tên traversal/control chars, symlink/dangling symlink. Commit chống stale external index và phối hợp NSFileCoordinator trên Apple.
- LibraryIndexSmoke Linux PASS: round-trip Unicode, duplicate/case collision/path rejection, failed/stale writes giữ items, corrupt index giữ byte, xóa index bên ngoài và symlink/dangling symlink.
- Thêm test vào audit. CI concurrency theo nhánh để các push tiếp theo tự hủy lượt build cũ; connector hiện không cung cấp lệnh cancel nên không hứa đã hủy thủ công các run cũ.
- Cần tiếp: typecheck/build mới, hoàn tất tab/favorites/trash và typed IPA workspace, patch lifecycle, download feed; bổ sung flag storage unavailable vào diagnostic thay vì chỉ snapshot counts.

## Mốc 8 — 7B nguồn và tải vào thư viện

- Tách metadata/parser khỏi UI, giữ nguồn AltStore/Feather dạng JSON có apps và versions[0]/downloadURL. URL tương đối resolve theo nguồn; tối đa 40 nguồn, 5.000 app/feed, 16 MB JSON, kiểm duplicate IDs/metadata/hash sai. Không tuyên bố hỗ trợ mọi feed.
- Thay data(for:) / download(from:) không giới hạn bằng HTTP(S) delegate stream ra tệp riêng 0700/0600 (iOS complete protection), tối đa 1 GB IPA. Kiểm Content-Length và byte thực, tối đa 5 redirect, từ chối URL credentials/protocol khác/HTTPS downgrade. Session ephemeral không cookie/credential storage; giữ kiểm TLS của hệ thống.
- Có tiến độ giới hạn 10 cập nhật/giây, hủy xuyên Task tới URLSession, cleanup staging khi lỗi/hủy; SHA-256 streaming trên Apple, đối chiếu sha256 từ version/app nếu có. SHA-256 không được nguồn cung cấp không phải bằng chứng xác thực nhà phát hành.
- Nguồn có mục trong menu thư viện; công cụ AltSource cũ cũng dùng luồng này. Chỉ tải/nhập, không tự ký/cài. Hiển thị nhà cung cấp, mô tả, version, size/hash và cảnh báo HTTP; giao diện nguồn Việt/Anh.
- Nhập dùng cùng NiKLibrary.receive, trả kết quả Bool thật, đối chiếu Bundle ID từ Info.plist trước copy/publish. Cancellation tới import worker và dọn file mới nếu chưa commit; giữ bản gốc. ZIP/CRC/Info.plist được kiểm như nhập thủ công.
- HTTPDownloadSmoke Linux PASS: HTTP/redirect, limit header/body, empty/500/protocol, progress và hủy giữa luồng, không còn staging sau lỗi. SourceDownloadSmoke Linux PASS: schema, URL tương đối, version/hash, duplicate/protocol/size, tải bytes thật và SHA-256 mismatch cleanup.
- Fixture mạng dùng Python HTTP server loopback, không mạng ngoài/credentials; nối cả hai vào audit Apple. Native parser + integration/dependency/bash/whitespace PASS; UIKit typecheck/source UI và import IPA thật cần CI/device.
- Khi app bị hệ thống kết thúc giữa tải, staging tạm chưa được index vào thư viện; chưa có resume tải sau relaunch. Cleanup sau crash dựa trên temp OS, còn cần bổ sung dọn staging cũ có ownership.
- CI 5229db4 / 44210893692 đã có runner và đang audit. Giữ kết quả này để sửa lỗi, không gọi mốc mới đạt build từ kết quả commit cũ.
- Còn lại chính: tab/favorites/trash + typed plist/workspace/entitlements/components/diff/undo, patch conflicts/lifecycle/history, OTA/device, diagnostics storage availability và gate 2 lần sạch.

## Mốc 9 — trạng thái storage trong report và dọn staging sau gián đoạn

- Mốc 8 được giữ ở commit db62f5a55c78e5aaabb6f49c35c4dada8a4f3e5c, nhánh handoff/niksign-upgrade-checkpoints. Chưa advance codex/niksign-upgrades khi CI 5229db4 đang chạy để không hủy runner giữa audit. Đọc nhánh checkpoint này nếu phiên ngắt; tiếp tục fast-forward nhánh build khi audit hiện tại có kết luận.
- Diagnostic thêm các cờ trạng thái mở kho job/recovery/certificate. Empty counts không còn được hiểu ngầm là kho trống trong khi mở index thất bại; không xuất lỗi thô hoặc paths. Đây là trạng thái mở/đọc snapshot, không phải cam kết tất cả ghi tương lai sẽ thành công.
- Recovery controller theo dõi kết quả mở/refresh; queue cho biết journal có nạp được. UI report truyền các cờ thật thay vì mặc định available. DiagnosticsSmoke bổ sung unknown/available flags và vẫn PASS Linux.
- Downloader giới hạn timeout tối đa 1 giờ, dọn folder NiKSign-Network-UUID cũ hơn 24 giờ trước lần tải kế tiếp. Không dọn folder mới, tên khác, regular file hay symlink; không theo link ra ngoài. Không resume tải dở sau app bị kết thúc.
- DownloadCleanupSmoke kiểm namespace/tuổi/UUID và bảo toàn dữ liệu không thuộc ownership; chạy cùng audit. Core và network smoke tests chạy lại sau thay đổi; cần kết quả Apple ở commit mới.

## Mốc 10 — 4B nhiều tab, lịch sử, yêu thích và tệp ẩn

- Thêm state/versioned store/controller riêng. Mỗi root Documents/IPA Library có tối đa 12 tab, mỗi tab giữ vị trí tương đối, history 100 mục, query/sort/hidden; favorites tối đa 1.000. Không lưu UUID đường dẫn container tuyệt đối.
- Navigation thư mục đi trong tab, lùi/tiến/gốc, thêm/đóng/chọn tab và yêu thích nằm trong nội dung/menu ... hiện có; 4 root FilesHome được giữ. Chuyển tab có cache scroll anchor theo tab+vị trí trong phiên; độ chính xác cuộn cần kiểm UI thiết bị. Anchor không persist sau đóng app.
- Root/path traversal và symlink guard; folder bị mất/không đọc được hiển thị lỗi và nút retry/root, không hiển thị giả empty. Danh sách cũ không được giữ ở thư mục lỗi. Lỗi index phiên giữ nguyên file và chặn overwrite; chống stale settings từ instance khác.
- FileBrowserStateSmoke Linux PASS: tab/query/sort/hidden/history độc lập, favorites/relative persistence, giới hạn tab/history, invalid state/path/symlink, stale/corrupt settings. Nối audit. Parser Native và source checks PASS; SwiftUI/controller Apple typecheck chưa chạy ở mốc này.
- Mốc 7 / 5229db4 đã PASS 2 clean audits, có artifact 14386558398. Hash và phạm vi chính xác trong VERIFIED-BUILD-5229db4.md; hai IPA local đã qua verifier. Giữ bản này để đối chiếu, không gọi là bản chứa mốc 8–10.
- Nhánh handoff/niksign-upgrade-checkpoints giữ mốc 8–9 trong khi CI 5229 chạy. Khi checkpoint mốc 10 xong sẽ fast-forward codex/niksign-upgrades tới code mới để audit; không merge main.
- Tiếp theo: properties/hash và trash/recovery thao tác tệp, clipboard/chuyển nền; typed IPA workspace (2C), patch conflicts/lifecycle (5C), QA/device. Chưa tuyên bố 4B hay toàn lộ trình hoàn tất.

## Mốc 11 — thuộc tính tệp và SHA-256

- Màn thuộc tính đọc metadata ở nền, có tên/type/size/ngày/quyền POSIX và SHA-256 cho tệp thường tối đa 1 GB. Thư mục không giả tổng dung lượng, không băm đệ quy.
- Đối chiếu size/mtime/inode/type trước/sau khi băm; báo lỗi nếu tệp đổi. Root/parent/symlink guard dùng cùng FileLocation. Có hủy task khi đóng; Apple SHA-256 đọc từng chunk có cancellation.
- Menu giữ cấp chính bằng thay mục Hex thành submenu Kiểm tra tệp → Hex / Thuộc tính & SHA-256; thư mục có Thuộc tính. Không thêm nút toolbar phụ.
- FilePropertiesSmoke Linux PASS: metadata Unicode, known digest, directory semantics, giới hạn hash và symlink/outside-root. Thêm audit; UIKit/controller Apple typecheck và thao tác UI cần CI.
- Mốc 10 đã push 446060385fe4192560c739b14d6a2ad07aba650d vào cả codex/niksign-upgrades và handoff/niksign-upgrade-checkpoints, kích hoạt gate cho các mốc 8–10. Mốc 11 sẽ checkpoint ở handoff trước để giữ runner đang chạy nếu đã có.
- Tiếp theo ưu tiên 4B: trash/restore không overwrite, bảo vệ file/index/input/component của job đang chạy, clipboard và nền I/O. Chưa có trash; thao tác delete hiện vẫn là xóa trực tiếp, cần sửa trước gọi 4B hoàn tất.

## Mốc 12 — bảo vệ dữ liệu job trước thao tác tệp

- Phát hiện đường xóa/rename/move ở file browser có thể bỏ qua guard Library.remove và tác động input/components của job đang chờ/chạy. Thêm reservation broker MainActor, kiểm giao nhau theo ranh giới path và đường dẫn canonical; thao tác nền giữ lease đến khi I/O kết thúc.
- Queue enqueue kiểm lease cho cả input và injectedFiles; thao tác tệp kiểm tất cả job chưa terminal. Bảo vệ cả thư mục cha, không chỉ file bằng tên trùng. Không cho raw file browser đổi/xóa vùng IPALibrary quản lý riêng; copy đọc ra ngoài vẫn được phép.
- Nối guard vào delete/rename/move/copy destination/new folder/unzip, editor/recovery write/restore. Nhập file thông thường chặn thư mục đang có mutation và hướng nhập IPA về thư viện để giữ index nhất quán.
- FileMutationReservationsSmoke Linux PASS: input/components/ancestor, managed root, leases/release, sibling boundary, root/case/protocol. Nối audit; Native UI integration cần Xcode của code mới.
- Broker này là nền cho trash/restore ở bước tiếp theo, chưa phải thùng rác. Delete vẫn xóa trực tiếp đối với tệp không bị guard; cần thay sang giao dịch trash và xác nhận permanent delete.
- Mốc 11 checkpoint 94ec3a24b0ebdffeaea9a01681d8b786e24d787c trên handoff/niksign-upgrade-checkpoints; build branch đang audit 4460603. Không dùng SHA 5229db4 đã sạch để gán PASS cho mốc 8–12.

## Mốc 13 — nền tảng trash transaction (CHƯA nối thao tác xóa UI)

- Thêm TrashRecord/TrashIdentity/TrashStore, namespace AppSupport ngoài Documents. Index schema 1, tối đa 8 MB/5.000 records; quota 4 GB và 50.000 mục khi quét thư mục. Di chuyển giữ nguyên inode; journal trước rename, nhận diện metadata thư viện nếu có.
- Phases trashPrepared/trashed/restorePrepared/restoredNeedsIndex/restored/purgePrepared/purged và aborted/missing/needsReview; recover chỉ đối chiếu filesystem + identity, không tự overwrite đích. Library restore có trạng thái chờ commit index riêng, không tự báo đầy đủ trước cập nhật metadata.
- Restore không ghi đè file mới, có tạo parent thiếu sau kiểm path; symlink/root/entry guard, NSFileCoordinator cho rename trên Apple. Purge cần explicit confirm, chỉ payload thuộc UUID namespace; dọn lịch sử chỉ trạng thái kết thúc không còn payload.
- Index hỏng/stale được bảo toàn; backup còn giữ khi gặp trạng thái không rõ. Identity dựa device/inode, nên migration filesystem/backup làm đổi inode cần review, không tự suy đoán dữ liệu đúng. Không gọi đây là cơ chế sao lưu toàn bộ app 9C.
- TrashStoreSmoke Linux PASS: round-trip, conflict/retry, purge confirmation giữ file mới, journal-before-move, lỗi ở 3 biên trash + 3 biên restore + purge-final, folder/missing parents, symlink/root guards, pending library metadata, corrupt/stale index, clear finished history. Apple test được nối audit, chưa chạy.
- Chưa có controller/Trash UI, Library.remove và file delete vẫn cần thay; không nói thùng rác đã dùng được. Bước tiếp theo: reserve paths trên MainActor → backend worker, refresh/recover; lưu snapshot LibraryItem trước move, commit removal index sau move, rollback physical nếu index fail; restore library giữ restoredNeedsIndex tới khi save metadata thành công. Không dùng store.write(Data()) để giả delete.
- Build 446060385fe4192560c739b14d6a2ad07aba650d / run 44213739009 đã PASS 2 clean audits, gồm fixtures HTTP/source/tab trên macOS, có artifact IPA/source 14388591883. Phạm vi mốc 1–10; mốc 11–13 chưa thuộc bản đã sạch này.

## Mốc 14 — nối Trash UI, xóa/khôi phục IPA và giao dịch metadata

- Đã thay xóa trực tiếp của LocalFiles thành TrashController worker, giữ lease input/component. Library.remove chuyển async, đưa bản gốc vào trash kèm LibraryItem snapshot; chỉ xóa index sau khi backup durable. Raw IPALibrary vẫn không được mutate ngoài luồng quản lý thư viện.
- Có Trash UI trong menu ... và Settings: trạng thái thật, restore/hoàn tất metadata, recheck, export backup để kiểm tra, dọn lịch sử kết thúc. Purge cần confirmation riêng; không xóa tệp mới tại vị trí gốc. Nếu journal hỏng, giữ nguyên và cho xuất index.
- Thêm trashedNeedsIndex và pendingAction để recover không nhầm thao tác purge dở thành backup có thể restore. Prepared/needsReview có thể đối chiếu lại sau khi xử lý xung đột. Case cũ không đủ bằng chứng vẫn giữ để review, không overwrite.
- Tách NiKTrashLibraryTransaction dùng chung mã production/test: lỗi index removal rollback file, lỗi rollback metadata giữ restoredNeedsIndex; retry idempotent, không ghi đè metadata ID trỏ IPA khác, giữ các tùy chọn mới hơn khi rollback. IndexStore có helper removeForTrash/restoreFromTrash và verify stale data.
- TrashLibraryTransactionSmoke Linux PASS: normal remove/restore, lỗi trước/sau commit index, pending/retry, newer options, foreign metadata conflicts và chuẩn hóa completion chỉ sau recover durable. Core smoke chạy lại PASS, thêm sparse-file quota 4 GB, per-item >4 GB và review/retry. Sparse fixture không đọc/ghi GB vào RAM.
- Chặn hardlink thường nhiều ownership trước move; fixture xác nhận giữ nguyên hai liên kết.
- Export review sao chép sang temp theo tên gốc, giữ backup riêng; không khẳng định tính toàn vẹn nếu record cần review. Nhận diện restore dựa device/inode, không phải full-app backup/migration. Các icon thư viện/IPA đã ký tách riêng chưa có GC khi purge bản gốc; không xóa rộng để dọn rác.
- Native syntax/source/dependency/bash/whitespace qua. UI/controller/mới pending Apple audit; mốc 13 (1ee6be17) đang chạy build, chưa gán kết quả đó cho mốc 14.
- Tiếp theo: gate Apple; bổ sung diagnostic cho trash pending states và clipboard/nền I/O, typed IPA workspace (2C), patch lifecycle/conflicts (5C), OTA/device. Chưa tuyên bố toàn lộ trình hoàn tất.

### Kết quả Apple ở mốc 13 trước khi checkpoint mốc 14

- 1ee6be17e68e8eeb9f23ac70ff0e47e69daf6218 / workflow 44216577081: source-checks và job iOS 134507851088 đều success; gate 2 clean audits đã qua.
- Bản này chứa mốc 11 properties, mốc 12 mutation protection và mốc 13 trash core. Chưa có Trash UI/controller/cross-library metadata transaction của mốc 14, không gán PASS cho mốc 14 từ kết quả này.
- Khi checkpoint mốc 14 xong, fast-forward nhánh codex/niksign-upgrades và chạy audit mới; giữ các IPA đã xác minh 4460603 để đối chiếu.

## Mốc 15 — typed plist engine và semantic diff (chưa nối UI)

- NiKTypedPlistDocument hỗ trợ dictionary/array và String/Int64/UInt64/real/Bool/Data/Date, path có kiểu key/index; replace/insert/remove/append/reorder với mutation atomically vào bản nháp. Gốc không thể xóa, duplicate key/index sai bị từ chối.
- Giữ binary/XML, no-op trả đúng bytes gốc, encoded round-trip so kiểu/giá trị trước cho lưu. Binary Date có phần lẻ được giữ khi sửa field khác; chọn XML làm mất độ chính xác thì từ chối trước I/O. Cả Unicode literal normalization và dấu zero IEEE của real được phân biệt khi xem thay đổi.
- Semantic diff theo key/index, preview mặc định 200 và đếm tổng; array diff theo vị trí, không phải LCS tối thiểu. Format conversion có thể không đổi field, UI phải hiển thị riêng.
- Giới hạn nguồn/output 4 MB, 64 cấp/100.000 node và 8 MB expanded values. Preflight Foundation graph trước tạo Swift tree để tránh bplist lặp reference tới Data/String lớn. Fixture alias là binary plist hợp lệ ~1 MB/20 MB expanded, không chỉ dữ liệu parse lỗi.
- TypedPlistSmoke Swift Linux PASS: typed CRUD/arrays, giữ Bool/Int64/UInt64/Data/fractional Date, no-op bytes, Unicode và negative zero, failed mutation giữ draft, bounds/expansion guard. Binary serialization sau chỉnh có thể đổi thứ tự dictionary nên test state theo semantic value; không giả bytes deterministic ngoài no-op.
- Nối audit Apple; chưa có UI mới hoặc workspace IPA hoàn chỉnh. Bước tiếp: tree/scalar editor, review/save qua recovery snapshot, undo draft, export draft; sau đó immutable-source workspace và package/validation.
- Mốc 14 toàn bộ Trash UI + fix hardlink/deletion được checkpoint ở 4d9b7e25f6642deef9596f7667466afa00bb67c7, nhánh build đang chạy run 44222092235. Mốc 15 chưa thuộc commit đó. Không gán gate cũ cho code mới.

## Mốc 16 — trình sửa plist có kiểu đã nối UI

- .plist trong LocalFiles mở cây dictionary/array; thêm/xóa/thay giá trị, đổi kiểu, dời phần tử mảng, xem diff theo trường và chọn XML/binary. Sửa bản nháp với tối đa 20 bước undo, review rồi mới tạo backup/ghi bằng RecoveryController và SHA-256 stale guard.
- Đóng/lưu/menu ở thanh đáy trong modal để dùng được khi đang ở cấp sâu. Có xác nhận bỏ draft, export draft ra temp để cứu dữ liệu khi save bị conflict, review dùng chính bytes đã kiểm tra (không serialize lại tùy ý sau review).
- Child pages nạp ở worker, mặc định 250 row và load thêm; action giữ revision để không sửa/xóa nhầm index khi cây đã đổi. Root/array/dictionary mutation không ghi đĩa trước Save.
- Scalar draft giữ original khi chưa đổi, bool tách số, số có range check, UInt64 nhỏ canonical về integer, Base64 chỉ bỏ whitespace, từ chối NaN/Inf. Date nhập theo giây từ 2001 UTC để giữ độ chính xác của binary plist, không chuyển qua ISO/XML làm tròn.
- PlistValueDraftSmoke Linux PASS: Date rất nhỏ, negative zero, literal Unicode, numeric/Base64 validation, giữ container khi không đổi. TypedPlistSmoke đã PASS mốc 15; thêm cả hai vào Apple audit. Native syntax/integration/dependency/bash/whitespace PASS. SwiftUI/controller chưa typecheck Apple ở commit này.
- Không gọi đây là workspace IPA đầy đủ: chưa có cây bundle từ IPA/extract immutable source, quản lý component/entitlements, packaged change set/compression backend của 2C. Đây là typed editor dùng được cho tệp riêng, làm nền cho workspace.
- Build 4d9b7e25f6642deef9596f7667466afa00bb67c7 / workflow 44222092235 đã qua 2 clean audits; có Trash UI và toàn bộ mốc 1–14. Typed engine/editor mốc 15–16 chưa thuộc build đó.

### Chốt bàn giao sau mốc 16

- Sửa cancellation của worker phân trang plist và dùng token để task cũ không ghi đè loading/error của lần nạp mới. Export draft khóa busy trong khi tạo bản xuất.
- Native syntax và controller Foundation typecheck harness Swift 6.1.2 / Swift language 5 PASS; harness thay Combine/Recovery bằng stub, không thay thế Apple UI integration.
- Build d30b78d / workflow 44226714053 đang in_progress tại lần kiểm tra bàn giao; source-checks success, chưa gán gate Apple cho typed editor.
- Bản IPA đã xác minh gần nhất: 4d9b7e2, hai clean audits, chưa ký. Không khẳng định cài được trên iPhone 27.2 khi chưa có chứng chỉ/profile và kiểm thử thiết bị.
- Toàn bộ 2C/5C và các mục còn thiếu vẫn chưa hoàn tất; xem BAN-GIAO-HIEN-TAI.md.

### Kết quả Xcode mốc 15–16 — d30b78d

- Workflow 44226714053 đã completed/success. Gate yêu cầu hai clean audits đã qua cho d30b78d014507c80ef487f8330da3ee18e65c295.
- Artifact 14394666987, ZIP SHA256 d881769655b43c704bd2dfc08dd8062ed8a784db66e92e9af4d67cc393fb326a. Tải và verify-ipa.py cả hai IPA PASS: arm64 executable, CRC, bundle ID và localizations.
- IPA pass2 SHA256 048974a776a7cf582c2153ae568fe22a10cdb21bd0e22b886de5704b5f087250; local /workspace/NiKSign-verified-builds/d30b78d/NiKSign-d30b78d-pass2-unsigned.ipa. Chưa ký.
- Không bao gồm fix cancellation/token sau đó ở abcc93b; không gán gate d30b78d cho thay đổi mới. Cần gate riêng trước phát hành code cuối.
- Tiếp theo: ký/cài theo phương thức người dùng có, kiểm tra import/relaunch, typed plist/undo/backup, trash/restore và khả năng 3105 trên iOS 27.2. Chưa có kết quả máy thật.

## Mốc 17 — phản hồi kiểm thử iPhone

- Bỏ banner NiKSign/Ký IPA & sửa tệp còn sót trong RepositoryHome và đổi tiêu đề màn kho sang 3105; giữ luồng tools/import riêng.
- Lỗi ảnh ký là bundle.mismatch; không bỏ guard provisioning. Hiện mọi issue, ưu tiên blocking, hiển thị pattern profile và hướng xử lý. Profile ID cố định có nút áp dụng vào customBundleID mỗi IPA, không đổi IPA gốc hoặc profile; lưu tùy chọn và assess lại. Pattern wildcard vẫn cần ID phù hợp. Chưa xác minh ký/cài trên máy thật, có thể còn lỗi khác sau sửa ID.
- Tệp hệ thống có bật tệp ẩn và thông báo đường dẫn/domain/code khi đọc thất bại. Không coi thư mục trống là chứng cứ sandbox. FileManager không tự có quyền vượt sandbox; đây là cải thiện chẩn đoán, KHÔNG phải đã sửa quyền 3105 trên 27.2.
- Native parse, source/dependency integrity và CertificateCompatibilitySmoke Linux PASS. Cần Xcode cho UI mới và thử thiết bị.

## Mốc 18 — ký giữ nguyên Bundle ID theo yêu cầu

- Bundle/profile mismatch chuyển thành warning trong assessment dùng chung UI và Signer backend; không chặn nút ký hoặc preflight chỉ vì ID khác profile. Không tự đổi Bundle ID. Đổi theo profile vẫn là tùy chọn.
- Phân biệt tạo chữ ký với cài/chạy: provisioning/trust/entitlements vẫn do iOS kiểm tra. Không cam kết ký mọi IPA mã hóa/hỏng hay bỏ qua quyền hệ thống. Các guard certificate expiry/credentials/profile validity hiện hữu giữ nguyên.
- Fixture xác minh fixed/wildcard mismatch cho phép ký, warning vẫn hiện, certificate expired vẫn chặn. Cần Xcode và thử thiết bị cho commit mới.

## Mốc 19 — trạng thái chứng chỉ và đếm ngược

- Saved Certificates hiển thị countdown cập nhật mỗi phút theo hạn sớm hơn cert/profile, báo dữ liệu thiếu và expired. Ngày dùng ceil giờ, không mặc định profile còn hạn nghĩa là cert tốt.
- Nút kiểm tra thu hồi dùng Security trust + OCSP require positive response, network fetch, không upload p12/password tới API bên thứ ba; kết quả good chỉ khi trust evaluation thành công, revoked chỉ khi OSStatus certificate revoked, mọi lỗi khác unknown. Check chạy worker; chống trùng mỗi ID, persist state/time và kiểm fingerprint trước cập nhật. Không tự kiểm tra khi mở app. OCSP dùng chứng chỉ công khai và có thể truy vấn responder/issuer.
- Trạng thái còn mới trong 24h; sau đó hoặc clock rollback chuyển unverified. Không bảo đảm trust/OTA/app entitlement chỉ vì OCSP đạt. Bản lưu cũ decode optional fields không lỗi.
- Fixture countdown/min-expiry/zero, cache TTL/clock rollback/revoked cùng compatibility PASS trên Linux; Native parse/source/dependency PASS. Security API và SwiftUI cần audit Xcode; chưa có live Apple OCSP/device result.

## Mốc 20 — Bundle ID riêng và điều tra lỗi nhập 3105

- Theo yêu cầu mới, mặc định NiKSign chuyển từ com.apple.mobile.MobileHouseArrest sang com.niksign.app. Nối Info.plist/project/build/workflow/verifier/fixtures đồng nhất; custom workflow ID vẫn được stamp vào IPA. Không đổi ID của IPA nhập vào thư viện.
- Đổi Bundle ID có thể cài thành app mới và tách container/chứng chỉ cũ, không xóa app cũ trước khi xuất dữ liệu. Có thể ảnh hưởng khả năng truy cập phụ thuộc MHA, chưa xác minh máy thật. Quyết định này thay thế yêu cầu khóa MHA cũ.
- Ảnh 3105 báo unsupported_version: PatchPackageCodec hiện latestSchemaVersion=3, upstream YangJiiii/3105 main đối chiếu cũng =3. Chưa có tệp patch gây lỗi để xác định envelope/schema/keyAADVersion; chưa sửa codec, không tăng version giả hoặc bỏ validation. Cần tệp .3105 hoặc link tải chính xác để tái hiện. WorkspaceV9 engine riêng không đồng nghĩa codec encrypted .3105 hỗ trợ schema9.

### Chẩn đoán tệp patch người dùng — schema 9

- File SHA256 15d808b2d0db6eb7aeb4ba0a1d2c23ebb99c84d74c8c445bdacf9e6bab47e6e5, 34585 bytes, magic 3105PATCH + binary plist, schema9 public không mật khẩu. AES-GCM authentication thành công; SHA256 replacement khớp manifest.
- Có 1 rule replace/application, 2 directories/application; settings/AppGroups/SystemAppGroups rỗng. Tạo bản tương thích v3 riêng sau strict field-set/semantics guard, bỏ metadata mặc định application/replace tương đương codec3 và metadata rỗng, giữ nguyên bytes thay thế/digest/path/id. Encrypt mới đúng AADv3, roundtrip authenticated/semantic PASS. Không sửa tệp gốc.
- /workspace/NiKSign-patch-diagnostic/CapCut-Pro-compatible-v3.3105. Swift PatchProject decode + production path/target validation PASS; Linux harness chỉ thay localized error string bằng key. Chưa thử import thực tế/áp dụng trên iPhone, không bảo đảm quyền dữ liệu ngoài sandbox.
- Đây là chuyển đổi giới hạn riêng tệp đã kiểm tra, KHÔNG phải hỗ trợ toàn bộ schema9 trong app. Codec app chưa thay đổi; cần importer migration có fixture synthetic/reject unknown semantics trước công bố hỗ trợ9. Không đưa nội dung patch người dùng vào GitHub.

## Mốc 21 — sửa nhập schema 9 trong ứng dụng

- Thêm compatibility overlay PatchPackageCodec thay đúng translation unit qua upstream-overlays/project, giữ nguyên 104 upstream files. Normalize được gọi ở inspect/decode (password và content key)/update, nên bao phủ nhập file, nhập data, tải nguồn, đọc thư viện và sửa/xuất sau nhập. Giữ nguyên file nguồn; dữ liệu xử lý có schema3 và cùng content key/fingerprint/project IDs. Export/sửa tiếp dùng codec3.
- Hỗ trợ có giới hạn: public schema9, replacement/application và directories/application, settings/AppGroups/SystemAppGroups rỗng hoặc vắng. Strict field allowlist từ chối metadata/operation/container lạ; không âm thầm bỏ tính năng. Schema9 có mật khẩu/private chưa hỗ trợ, schema1–3 giữ luồng cũ.
- AES-GCM xác thực AADv9 trước convert; kiểm UUID/project equality, SHA256 key/replacements, production path/target validation; reseal với AADv3. Giới hạn 64MB input/output, graph sâu64/100k node/128MB expanded; cap5000 rules/directories. Normalizer cũng chặn codec input quá64MB; không quảng bá hỗ trợ schema9 toàn bộ.
- Synthetic PatchSchema9Smoke Foundation Linux PASS: giữ semantic project/digests, reject AppGroup/settings/unknown feature/delete/merge/path/private/digest/id, aliased bplist expansion guard. Tệp người dùng chạy qua convertPayload production PASS sau xác thực AES-GCM bằng Python, giữ bytes/digest; không đưa nội dung tệp này vào git/CI. Linux harness chỉ thay localized error rendering và dùng nguyên production validator.
- Apple audit được nối tests crypto: inspect/decode cả hai overload/update/public9, tamper, unknown/protected envelope, unchanged protected legacy. Chưa có Apple result cho mốc21 tại lúc checkpoint.
- Sửa failed CI 6c5030e / run44233772991: certificate harness chưa copy NiKCertificateRevocation.swift nên cannot find symbol; bổ sung dependency và invalid-DER unknown fixture. Không tắt warning gate. Không gọi các mốc18–20 đã build sạch vì run đó thất bại.
- Thông báo unsupported_version đổi thành mô tả phạm vi thật trong UI vi/en/zh, không chỉ yêu cầu cập nhật 3105 mơ hồ. Bước còn lại: gate Apple commit mới, tải/verify IPA, thử nhập và áp dụng trên iPhone. Không khẳng định giải quyết quyền sandbox hay truy cập dữ liệu CapCut trên27.2.

## Mốc 22 — sửa workflow upload lỗi mạng

- Run44235522878/5e43918 đã PASS hai clean audits (schema9 crypto + UI/chứng chỉ đều được Apple compile), nhưng toàn workflow fail ở upload do ETIMEDOUT/ENOTFOUND. Bằng chứng ở BUILD-5e43918-UPLOAD-FAILURE.md; chưa có IPA tải về của commit này.
- Thêm tối đa3 attempts cho từng artifact IPA/source và diagnostics, chờ15/30 giây giữa attempts. Dùng step.outcome để retry, chỉ hai attempts đầu continue-on-error; attempt cuối vẫn làm job fail nếu hết lượt. Không bỏ qua audit và không biến lỗi build thành success. Diagnostics vẫn chạy sau audit fail, trừ khi canceled.
- overwrite:true áp dụng cùng tên artifact của run để xử lý trường hợp upload trả lỗi sau tạo dở. Giữ retention mặc định. YAML anchors dùng chung mapping để path/name không lệch giữa attempts.
- YAML parse/anchor resolution và source/dependency/whitespace checks PASS. Tiếp theo push chạy workflow mới, xác nhận upload đạt rồi tải/verify/checksum IPA; retry không bảo đảm khắc phục được outage kéo dài của dịch vụ GitHub.

## Mốc 23 — lỗi ký mất profile và phân giải container patch

- Người dùng báo Garena ký fail ở structural validator và CapCut patch apply targetAppUnavailable. Không nhầm hai lỗi này với bundle/profile membership hoặc schema9 import.
- Root cause signing tìm thấy trong pinned claration/zsign c4ba9da src/bundle.cpp: SignFolder xóa profile cũ, chỉ ghi embedded.mobileprovision khi bRemoveProvision=true. Wrapper Swift đặt tên removeProvision khiến call false trước đây bỏ profile. Đổi true theo native implementation, giữ Bundle ID, kiểm profile output bytes trùng profile chọn trước zip. Không bỏ validator hoặc xuất IPA thiếu profile.
- Bundle/profile mismatch vốn warning từ mốc18, không chặn. Validator expectedBundleID chỉ kiểm ID của output khớp ID người dùng yêu cầu; không so profile. Tách lỗi thiếu profile/executable/CodeResources/Info/mismatched output ID. Không cam kết cài/chạy với profile không phù hợp.
- DevicePatchService overlay thêm exact-ID LS/API container fallback khi MCM/metadata lookup không có path; canonical app-container validation + read preflight cho mọi target trước transaction. Lỗi unresolved và unreadable riêng; không suy đoán target chưa cài từ lookup fail. Patch detail hiển thị thông báo thật, vẫn giấu thông tin với private package.
- Không có cơ chế tự cấp quyền sandbox mới: custom Bundle ID có thể mất MHA access, iOS27.2 chưa được xác minh. Không được nói patch apply đã sửa triệt để trên máy thật; cần kiểm tra exact target ID/app đã mở/quyền truy cập và log 3105. Không remap ID gần giống hoặc ghi sang app khác.
- PatchContainerAccessSmoke Linux PASS (primary/fallback/invalid/denied); FileToolsSmoke Linux PASS gồm missing-profile error và cấu trúc ZIP. SwiftPM Linux còn warning resource PrivacyInfo.xcprivacy của ZIPFoundation; không gọi Linux run zero-warning. Native syntax/source/dependency PASS; Apple gate của code mới pending. Chưa có Garena IPA/chứng chỉ để tái hiện ký thực trên máy.
- Run44240972874/5f56845 được API kiểm tra completed/success: latest stable CI chứa mốc1–22. Không gán gate đó cho mốc23. Bàn giao Gemini tại BAN-GIAO-GEMINI.md.

## Mốc 24 — rà soát bản mới 28b0ba0/main4fef0b5

- Đồng bộ fast-forward main4fef0b5 (merge PR5), tree trùng 28b0ba0 trên nhánh upgrades. Run44297429836/28b0ba0 completed/success; không gán gate đó cho thay đổi24. Main đã merge tới mốc23 và thay đổi UI người dùng, các đoạn bàn giao nói chưa merge main là lịch sử cũ.
- Phát hiện showSigningProgressSheet được set nhưng chưa có sheet presentation. Nối modal vào detail, theo dõi đúng jobID, chỉ mở sau enqueue thành công và hiện job.error; sửa các mốc tiến độ theo report() thực của Signer.
- Kiểm tra đường dẫn IPA đã ký tồn tại trong Documents/Signed, là file IPA thường, không symlink/ngoài root trước hiển thị badge/install và trước OTA. Giữ signedPath để restore có thể dùng lại; không xóa metadata chỉ vì tệp tạm không có.
- SignedFileAccessSmoke Linux PASS (có file/missing/delete/symlink/outside root); Native parse/source checks PASS. Apple UI/typecheck cần gate mới. Còn cần cải thiện giữ navigation khi đổi tab (switch ZStack mới có thể dựng lại view), xử lý auto-install khi rời detail và xác minh ký/patch/OTA trên thiết bị. Không gọi iOS27.2 system access đã sửa.

### Workflow mốc24 bị thiếu hosted runner, đã yêu cầu retry

- Run44304188705/98d2b9f: source-checks success; iOS job134801440684 cancelled trước bước setup, runner_name rỗng, steps rỗng. Check annotation: “The job was not acquired by Runner of type hosted even after multiple attempts”. Chờ từ12:28:15 tới12:43:17 UTC, chưa chạy Xcode.
- Đã gọi rerun riêng job iOS; không đổi app/runner/warning gate và không push build branch để tránh hủy lượt retry. Chưa kết luận compile pass/fail của mốc24.

## Mốc 25 — sửa tận gốc Zsign mất embedded.mobileprovision

- Ảnh máy thật xác nhận fix23 đổi removeProvision=true vẫn fail. Điều tra toàn bộ native c4ba9da: SignFolder ghi profile khi true, nhưng GenerateCodeResources lại xóa profile khi true. False xóa profile cũ mà không ghi lại. Nhận định mốc23 chỉ “đổi cờ true” chưa đủ và được thay thế bởi fix này.
- Vendor/Zsign là local SwiftPM package từ cùng revision/MIT, đúng source set upstream; sửa DUY NHẤT điều kiện ghi profile thành !bRemoveProvision. Call Swift trở về false. Profile tồn tại trước sealing và hash được ký trong CodeResources, không chèn lại sau ký hoặc bỏ validator. UPSTREAM.json giữ original hashes + patch hash; dependencies-vendor-lock khóa toàn bộ source package, check-dependencies xác minh nguồn gốc và patch.
- Signer dùng bản snapshot p12/profile trong thư mục làm việc riêng, cùng bytes đã preflight; guard embedded bytes với provData snapshot. Không ghi đè profile gốc. Work được xóa qua defer; snapshot nằm ngoài Payload nên không xuất khóa trong IPA.
- Tests/zsign_provisioning_test.py biên dịch NGUYÊN native sources app sẽ dùng, dựng lại bundle.cpp gốc theo hash để tái hiện trước/sau; 12 ca (gốc/sửa × giữ/xóa × exact/wildcard/mismatched ID). Linux PASS: SignFolder chạy trên Mach-O arm64 sở hữu bởi NiKSign, profile binary có NUL, stale old profile được thay, resources hash2 khớp SHA256, original source bytes/Bundle ID không đổi. Đây là ad-hoc signature fixture, KHÔNG chứng minh Apple CMS/trust/install của chứng chỉ người dùng. Trên macOS fixture được compile arm64 bằng xcrun; nối test vào cả hai clean audits. Host C++ được compile với -Werror, không suppress compiler warnings.
- Queue catch lấy lại bản job đã nhận progress trước khi ghi failed/cancelled, tránh fraction quay về0 như ảnh.
- Native syntax/source/dependency/IPA fixtures/local package manifest PASS. Code mới cần Xcode gate và thử ký lại Garena trên thiết bị. Không tuyên bố mọi IPA cài được hoặc quyền sandbox được sửa bởi thay đổi này.

## Mốc26 — sửa warning header Zsign trên Apple

- Run44316629382/54741c3: native before/after provisioning regression PASS lúc14:09:27 UTC, BUILD SUCCEEDED lúc14:29:39 UTC. QA fail vì CPU_TYPE/CPU_SUBTYPE macro redefined trong local mach-o.h, không phải thất bại regression profile. Chưa gọi gate hai lượt thành công.
- Trên Apple dùng mach/machine.h và mach/vm_prot.h; chỉ giữ block portable CPU/VM definitions cho non-Apple. Không suppress warning, không đổi QA gate. UPSTREAM/header provenance và vendor hash cập nhật; check-dependencies hoàn nguyên patch để kiểm hash gốc.
- Native regression thêm Apple header include-order checks cả SDK→portable và portable→SDK, compile với -Werror. Cần audit Xcode mới để xác nhận không còn diagnostics.
