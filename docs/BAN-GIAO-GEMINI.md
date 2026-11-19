# Bàn giao NiKSign cho Gemini — 19/11/2026

## Quy định build mới — 19/11/2026

Theo yêu cầu mới của người dùng: từ nay chỉ build MỘT lượt, kể cả bản phát hành. Workflow chạy audit-ios.sh 1, xuất một IPA; bỏ lượt pass2. Giữ các kiểm tra và tests trong lượt đó. Các yêu cầu hai lượt trong tài liệu cũ đã được thay thế; không tự bật lại.

## Đọc trước, không bắt đầu lại

Người dùng chỉ có iPhone, báo iOS 27.2 chính thức; đã cài và kiểm thử NiKSign. Muốn sửa thực tế, nâng cấp liên tục và cập nhật bàn giao sau mỗi mốc. Không nói đã hoàn tất tính năng chỉ vì build qua. Không đòi xác nhận lại các sửa lỗi/nâng cấp đã được giao. Người dùng yêu cầu riêng: tạo bàn giao này cho Gemini.

Repo: https://github.com/joinalex1122/NiKSign-Build
Nhánh làm việc: `codex/niksign-upgrades`.
Checkpoint: `handoff/niksign-upgrade-checkpoints`.
Main/PR cũ không phản ánh tiến độ mới; chưa merge main. Checkout nhánh nâng cấp, không reset về main.
Lấy SHA chính xác bằng `git rev-parse HEAD` hoặc `SOURCE-COMMIT.txt` trong gói bàn giao. Tài liệu được cập nhật tới mốc31; các trạng thái cũ bên dưới là lịch sử.

Đọc tiếp `docs/UPGRADE-PROGRESS.md` (lịch sử mốc1–31), `docs/APPROVED-UPGRADE-SCOPE.md` (phạm vi đã duyệt). Mốc mới thay thế trạng thái cũ; ghi chú cũ “pending” không có nghĩa vẫn pending nếu đã có kết quả phía sau.

## Cập nhật mốc31 — tuyến cài tiêu chuẩn qua public manifest

Ảnh mới từ user xác nhận bản có counters vẫn 0 kết nối/manifest/IPA, iOS báo127.0.0.1. c289807/run44445164510 build một lượt success. Thay mặc định bằng HTTPS static manifest của SignTools + IPA HTTP loopback chỉ trên thiết bị, có consent lần đầu; không upload IPA/chứng chỉ/appmetadata. Palera dynamic generator được đối chiếu với Feather nhưng probe403/521 nên không dùng. Manifest parser pin port/URL/asset và contract com.foo.bar/Local app, max64KB/không redirect. UI giải thích prompt có thể hiện Local app dù metadata IPA giữ nguyên; iOS27.2 cần thử thực tế, không hứa mọi phiên bản hỗ trợ placeholder. Tuyến HTTPS nội bộ với metadata thật vẫn chọn được; local root không còn bắt buộc cho tuyến chuẩn. URL itms encode nested URL toàn bộ.

Native GCDWebServer phục vụ duy nhất /ota-me và /health, loopback/cổng4000–8999, range/HEAD, held lease/background lifecycle. Đổi phương thức stop/release đúng listener. Không coi HTTP manifest counter0 là lỗi khi manifest thực nằm ở dịch vụ ngoài. Thêm actual ObjC/GCDWebServer host regression vào Apple audit (full/range/HEAD/routes/counters/stop); Linux model/download tests PASS, Apple gate mới pending. Không khẳng định đã cài thành công trên iPhone. Đọc UPGRADE-PROGRESS mốc31 và cần thử Signed→Install→Tiêu chuẩn→đồng ý→xác nhận Local app→xem request IPA, tách lỗi signature nếu file đã tải.

## Cập nhật mốc30 — tin cậy ngay lần mở đầu và ứng dụng đã ký

Mốc29/4170f12 đã qua run44428678083 success. Mốc30 thêm first-launch trust onboarding sau chọn chế độ có ký (có Để sau, mở lại trong Settings), check HTTPS thật qua health route không cần IPA, giữ root Keychain identity-v1 nhưng tạo server leaf CA:FALSE/SAN/EKU ký bởi root đó. Không tự bật trust, không dùng delegate chấp nhận self-signed. Profile public root có identifier theo hash để tránh lặp profile khi tải lại. Bootstrap HTTP profile được probe trước mở Safari; IPA/manifest vẫn HTTPS. Thêm counters connection/TLS errors + thông báo chưa giao manifest/IPA, không coi openURL là cài thành công. Server health-only không phục vụ IPA cũ hết reservation.

Ứng dụng đã ký xuất hiện ở Ký IPA và Tệp: quét Signed độc lập history, cài/chia sẻ/thùng rác; đọc Info.plist nhẹ cho list, full CRC/structure trước install. Local OpenSSL chain regression và FileToolsSmoke PASS; Apple audit mới và thiết bị vẫn cần xác minh. Chưa kết luận ảnh lỗi127.0.0.1 được sửa triệt để, cần thử cài profile/fulltrust→check→install và xem counters/TLS error mới. Chi tiết UPGRADE-PROGRESS mốc30; bổ sung hoàn tất gate theo đúng commit sau push.

## Cập nhật mốc29 — worse_query đã được nối vào code

Mốc29 tích hợp forcequitOS/worse_query GPL trong Vendor/WorseQuery + bridge, wrapper NiKWorseQueryAccess, ContainerStore overlay và DevicePatchService grants giữ qua transaction. Không cấp App Group giả. Cache gốc được bảo toàn bởi NiKGroupCacheTransaction (journal/identity/recovery), từ chối overwrite cache mới; dùng nhóm riêng để tránh tiến trình khác cùng ghi. Chính sách chỉ các container được hỗ trợ/OS đã chọn, không toàn root. Token release ở boundary. Linux safety tests PASS, nhưng native grant trên iPhone và Apple compile của mốc29 còn cần kiểm chứng. Mô tả mốc28 “chưa tích hợp” là trạng thái lịch sử, đã được thay thế về code, chưa thay thế về kết quả thiết bị.

## Cập nhật mốc28 — nguồn chênh lệch đã xác định

Người dùng đưa ảnh3105 gốc2.2 Beta1 chạy27.2.0(24B119), backend worse_query/AppGroup Có, không cần ghép đôi hoặcVPN. Đã xác nhận patch gốc làm được trên máy. NiKSign thiếu backend này; không tiếp tục nói “bật Developer Mode” hoặc chỉ đổi SupportPolicy là xong. Đọc3105-27.2-ACCESS-FINDINGS.md. Mốc28 mới thêm chẩn đoán entitlement của app và ngăn chọn sai legacy kernel trên27.2, CHƯA tích hợp worse_query/CHƯA sửa xong patch. Cần AppGroup được provisioning/chữ ký cho phép và container thật; giữ BundleID riêng có thể được, không mặc định buộcMHA hayenterprise cho tuyến mới. Khi portPoC cần giữ cache/journal/recovery, không dọn cache gốc mù.

## Cập nhật mốc27 — luồng cài và xóa queue

Người dùng xác nhận ký được trên9f28840 (run44328497383 success), nhưng chưa hiện prompt cài. Mốc27 thêm shared installer, URL itms-services:// đúng authority, system HTTPS manifest preflight, hướng dẫn cài public CA profile/full trust localhost qua Safari/Settings, không giả định open URL = cài thành công. Cài từ Saved library/detail/progress và Files/Signed dùng cùng view. Metadata đọc trực tiếp từ IPA nên vẫn cài được sau xóa lịch sử queue. HTTPS service không bị stop theo detail.onDisappear; background expiry vẫn có thể dừng. Cần kiểm thiết bị thật cho flow này.

Queue có swipe/context delete từng mục và clear all có xác nhận; running job giữ journal removalRequested, cancel ở safe boundary rồi mới xóa, phục hồi pending removal sau restart. Không xóa originals hay signed outputs khi xóa history. Xem UPGRADE-PROGRESS mốc27 và các tests mới. Mốc27 Apple gate pending tại lúc viết.

## Cập nhật mốc25 — ưu tiên nội dung này hơn mô tả mốc23 bên dưới

Đổi removeProvision=true ở mốc23 CHƯA sửa được lỗi trên máy. Native Zsign có hai nhánh mâu thuẫn: true ghi profile ở SignFolder rồi xóa ở GenerateCodeResources; false xóa cũ và không ghi lại. Mốc25 dùng local SwiftPM Vendor/Zsign, sửa điều kiện ghi thành !bRemoveProvision, Swift gọi false. Không sửa profile sau ký. UPSTREAM.json và dependencies-vendor-lock.json kiểm provenance. Native before/after regression 12 ca PASS; resource hash2/profile bytes đều kiểm. Không thay thế kiểm thử chứng chỉ và cài máy thật bằng ad-hoc fixture. Signer snapshot credentials riêng tránh đọc file thay đổi giữa preflight và ký; queue giữ progress khi thất bại. Đọc mốc25 trong UPGRADE-PROGRESS để lấy trạng thái mới nhất.

Main đã merge PR5 tới28b0ba0 (main4fef0b5), sau đó mốc24 nằm ở nhánh upgrades98d2b9f. Thông tin “chưa merge main” phía trên chỉ đúng cho thay đổi sau mốc23.

## Hai lỗi được bàn giao từ mốc23 — xem cập nhật25 trước

### Ký IPA Garena thất bại

Ảnh queue báo “IPA đầu ra thiếu executable, profile, tài nguyên chữ ký hoặc sai Bundle ID.” Đây là lỗi structural validator sau Zsign, không phải chứng cứ bị chặn Bundle ID/profile.

Root cause đã tìm trong Zsign được pin `c4ba9da4283031c07efa03bce42c4b8602d22e73`:
https://github.com/claration/zsign/blob/c4ba9da4283031c07efa03bce42c4b8602d22e73/src/bundle.cpp
`SignFolder` xóa profile cũ, rồi `if (bRemoveProvision)` mới ghi `embedded.mobileprovision`. Tên tham số Swift `removeProvision` ngược với logic native.

Mốc23 sửa `Native/Signer.swift` truyền true, kiểm bytes profile được giữ sau ký trước zip. `Native/Services/NiKSignedOutputValidator.swift` giữ kiểm CRC/Mach-O/profile/CodeResources/ID output, tách thông báo lỗi cụ thể. KHÔNG bỏ validator để giả ký thành công. Nếu đổi revision Zsign phải xem lại semantics này.

Bundle/profile mismatch đã chuyển warning ở mốc18 (`Native/Models/NiKCertificateCompatibility.swift`), dùng chung UI và Signer backend. Không tự đổi ID IPA và không chặn chỉ vì ID không khớp profile. Check ID output chỉ để bảo đảm giữ ID người dùng yêu cầu, không đối chiếu profile. Các lỗi mật khẩu, chứng chỉ/profile hết hạn, thiếu Mach-O hoặc binary mã hóa vẫn có thể chặn. Tạo chữ ký không đồng nghĩa iOS cho cài/chạy.

Chưa có IPA Garena, p12/password/profile của người dùng trong workspace để thử ký thật. Không đưa thông tin bí mật lên GitHub. Cần gate Xcode code23, sau đó người dùng thử lại từ bản gốc và đọc thông báo mới nếu còn lỗi.

### CapCut patch nhập được nhưng không áp dụng

Tệp người dùng là public schema9, 1 rule replace/application, 2 directories/application, không settings/AppGroups. Mốc21 đã tích hợp converter trong codec, không còn yêu cầu chuyển tay. Crypto/schema9 fixtures đã qua macOS ở build5e43918 và5f56845.

Ảnh mới báo không tìm/mở được container `com.lemon.lvoverseas`. Không phải lỗi nhập schema. Mốc23 thêm overlay `Native/UpstreamCompatibility/helpers/DevicePatchService.swift`, exact-ID LS/API fallback sau MCM/scan; `NiKPatchContainerAccess.swift` canonical validation + read preflight trước transaction. UI phân biệt unresolved và unreadable. Không dùng container của ID gần giống; không khẳng định chưa cài chỉ vì API lookup fail. Private package không lộ chi tiết target.

Chưa có bằng chứng quyền ngoài sandbox hoạt động trên iOS27.2 với Bundle ID mới. Không thể sửa triệt để quyền OS bằng việc bỏ check lỗi. Cần xác minh CapCut đã cài/đã mở, đúng Bundle ID của bản thực cài, log MCM/LS và trạng thái sandbox. Custom ID mới có thể không có quyền MHA cũ. Giữ backup/transaction, không ghi khi chưa xác định đúng target. Không hứa đổi ID hay ký app tự cấp quyền.

## Trạng thái build thật

- `5f568455dc61fc7682cde5306c65b13a9cfc7da1`, run https://github.com/joinalex1122/NiKSign-Build/actions/runs/44240972874 : API xác nhận completed/success. Chứa mốc1–22, chưa có fix23. Người dùng đã tải artifact; `pass1`/`pass2` là hai build cùng mã nguồn, dùng IPA pass2. Không gọi hai thư mục là hai phiên bản.
- `5e43918a24b56d1a0a8228c6f33a3e3a81e4f07a`, run44235522878: hai clean audits/codecs/IPA verify PASS, workflow fail chỉ vì upload ETIMEDOUT/ENOTFOUND. Xem BUILD-5e43918-UPLOAD-FAILURE.md. Mốc22 thêm3 upload attempts, vẫn fail nếu attempt cuối lỗi; không tắt warning gate.
- Các IPA cũ4d9b7e2/d30b78d không chứa fix mới. Không phát lại chúng dưới tên mới. Toàn bộ IPA là unsigned, không có chứng chỉ của người dùng trong bàn giao.
- Gate bắt buộc: hai clean audits liên tiếp, zero warnings/errors trên mỗi full audit log; build xong chưa đủ, phải upload và tải/verify checksum. Sau đó mới báo có IPA mới.

## Phạm vi schema9 thực sự

`NiKPatchSchema9Compatibility.swift` chỉ nhận gói public schema9 có replacement/application và directory/application, settings/AppGroups trống. AES-GCM AADv9/fingerprint/digests/path/model validation trước reseal nội bộv3. Original source không bị ghi đè. Inspect/decode password/contentKey/update đều gọi normalize. Không nhận schema9 private/password, merge/delete/container khác/dynamic settings; từ chối unknown fields để không bỏ mất nghĩa. Không tăng latestSchemaVersion=9 và không mặc định WorkspaceV9 engine = encrypted codec9 đầy đủ.

Giới hạn64MB input/output, depth64/100k nodes/128MB expanded, 5000 rules/dirs. Giữ nguyên upstream; dùng `upstream-overlays.json`/project excludes. Có fixtures synthetic, không commit nội dung patch CapCut của người dùng.

## Quyết định người dùng đã chốt

- Chọn chỉ ký / chỉ3105 / cả hai lần đầu, đổi trong Settings.
- Giao diện iOS sáng/tối/theo hệ thống, logo NiK navy/cyan/purple. Basic/advanced độc lập, mặc định basic, có chuyển đổi.
- Chứng chỉ hỏi lần đầu, có “Để sau”; nhiều cert/default/chọn riêng IPA; không giới hạn ký vào ID profile. OCSP online có nút kiểm tra, good/revoked/unknown, TTL24h; countdown hạn sớm hơn cert/profile. Offline/timeout không được báo good. OCSP đạt không chứng minh install/launch.
- Bundle ID mặc định CHÍNH NiKSign là `com.niksign.app` từ mốc20, thay yêu cầu MHA khóa cũ. Giữ nguyên ID IPA nhập trừ người dùng sửa. Đổi ID app có thể tạo container/app mới; giữ bản cũ để xuất dữ liệu.
- Bỏ banner ký NiKSign trong kho3105; title3105. Không thêm thanh nổi trùng chức năng.

## Lộ trình còn thiếu — không báo toàn bộ hoàn tất

Phạm vi: 1B 2C 3B 4B 5C 6B 7B 8B 9B 10C.

Đã có: durable sequential signing queue/retry, certificate compatibility, typed plist tree/diff/undo/recovery, streamed source download+hash, tabs/history/favorites, properties/SHA256, leases bảo vệ input job, transactional trash/library rollback, redacted diagnostics, basic/advanced UI, local HTTPS OTA nền tảng.

Còn lớn:
1. 2C: workspace IPA từ immutable original/hash, safe extract/bundle scan, components/entitlements, diff/undo, export change set/compression thật, validated signing integration. Typed editor hiện cho plist riêng, không phải workspace hoàn chỉnh.
2. 4B: clipboard giữa tabs, I/O nền còn lại, staging orphan cleanup sau crash, UI/device verification.
3. 5C: conflict/lifecycle/history/recovery bản vá trên nền transaction; chưa có nâng cấp hoàn chỉnh.
4. 6B/9B: OTA/TLS/install và recovery kill/relaunch trên iPhone; chưa có bằng chứng27.2 truy cập hệ thống. Không chỉ sửa SupportPolicy để gọi là hỗ trợ.
5. 10C: gate cho commit cuối, tải/verify IPA, provenance/checksum, kết quả thật từ thiết bị.

## Kiểm thử và môi trường

Workspace: `/workspace/NiKSign-upgrades`; Linux Swift6.1.2: `/workspace/.niksign-toolchain/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin/swiftc`.
Linux không typecheck SwiftUI/UIKit/Security và không build IPA. Native parse chỉ syntax. Xcode16.4/macOS15 Intel/SDK18.5 ở Actions, iOS deployment17.

Chạy `python3 scripts/check-integration.py`, `python3 scripts/check-dependencies.py`, tests phù hợp; `bash scripts/audit-ios.sh 1` trên macOS. Harness Certificates phải copy OCSP service; lỗi thiếu symbol này đã sửa. Audit có PatchSchema9Smoke và PatchContainerAccessSmoke.
Mốc23 local PASS: FileToolsSmoke (ZIP/CRC/missing profile), PatchContainerAccessSmoke, Native parse và source checks. Linux SwiftPM ZIPFoundation có warning PrivacyInfo.xcprivacy, không gọi Linux zero-warning. Chưa có Apple gate cho code23 tại lúc viết bàn giao.

## Cách tiếp tục

1. Kiểm SHA nhánh mới và workflow gắn SHA đó, xử lý lỗi thật. Không lặp lại gate trên code cũ để chứng minh code mới.
2. Tải IPA pass2 khi upload success, kiểm verify-ipa.py với Bundle ID com.niksign.app, ghi checksum và phát đúng build cho người dùng.
3. Người dùng thử Garena từ bản gốc, CapCut patch; thu thông báo chi tiết và log truy cập đã che dữ liệu nhạy cảm. Sửa đúng tầng signature/profile vs OS container access.
4. Hoàn thành từng mục nâng cấp còn thiếu, cập nhật UPGRADE-PROGRESS sau mỗi mốc.

Không reset các worktree cũ `/workspace/NiKSign-handoff-final`, `/workspace/NiKSign-latest-review` hoặc áp lại stash toàn bộ. Không đưa p12/password/UDID/patch riêng vào repo. Không tuyên bố hoạt động máy thật từ fixture hay BUILD SUCCEEDED.
