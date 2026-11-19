# Kiểm chứng NiKSign Sign-only 3.4.0 (340) — 2026-11-19

**PASS trên macOS/Xcode.** [GitHub Actions](https://github.com/joinalex1122/NiKSign-Build/actions/runs/44535871357) chạy commit `01cbc2f186478ced39e4f9167f31b95b1e58fbcc`, runner macos-15-intel / Xcode 16.4. Workflow success; một lượt audit và một lượt build app trong lần chạy đạt này.

| Lệnh/kiểm chứng bắt buộc | Kết quả |
|---|---|
| `python3 scripts/check-integration.py` | PASS, 74 Swift units, một app entry, nguồn Sign-only |
| `python3 scripts/check-dependencies.py` | PASS, 8 thư viện, license/hash/provenance và overlay máy chủ |
| `bash -n scripts/*.sh` | PASS trong source-checks; tất cả shell scripts cũng được kiểm từng file cục bộ |
| `xcodegen generate` | PASS trên macOS |
| `xcodebuild -sdk iphoneos ... CODE_SIGNING_ALLOWED=NO ... ARCHS=arm64 build` | BUILD SUCCEEDED, 0 warning/error diagnostics |
| `python3 scripts/verify-ipa.py ...` | PASS: thin arm64 MH_EXECUTE, ZIP CRCs, Bundle ID, URL scheme |

Audit có 45 dòng PASS, gồm native GCDWebServer full/Range/HEAD/shutdown, native Zsign profile seal, CMS/page/special-slot hashes và tamper rejection, app/extension identity/debug flags, lịch OCSP, hàng đợi xóa/hủy an toàn, download/hash/cleanup, recovery/trash, archive/CRC, PKCS12 cũ/mới, Keychain và chuỗi CA/server TLS. Fixtures CMS dùng khóa tổng hợp, không chứng minh quyền cài đặt Apple.

## Artifact chính xác

- IPA artifact: [14536028345](https://github.com/joinalex1122/NiKSign-Build/actions/runs/44535871357/artifacts/14536028345), chứa đúng một IPA và một source ZIP.
- IPA: `NiKSign-SignOnly-3.4.0-01cbc2f-unsigned.ipa` — 5,484,504 bytes.
- SHA-256 IPA: `310d65f1eec68eabf2fed87dad763e8795f39e28f10f74734c3c304244e718ac`.
- Source ZIP xuất trực tiếp từ CI: `NiKSign-SignOnly-3.4.0-01cbc2f-source.zip`, SHA-256 `a61dc0ba6e86f1d9c5a0298b18d7ef9520845742d1803ea2aa6196f2bf682db3`.
- Diagnostics artifact: [14536028349](https://github.com/joinalex1122/NiKSign-Build/actions/runs/44535871357/artifacts/14536028349), có audit log, Xcode log, binary info và Package.resolved.
- Bundle ID: `com.niksign.app`; version `3.4.0`; build `340`; scheme chỉ `niksign`.

Kiểm tra lại artifact sau tải: CRC/hash khớp, binary arm64; các marker `worse_query`, `bad_query`, `com.apple.mobile.MobileHouseArrest`, `kexploit_opa334`, `NiKPatchV9Engine`, `NiK3105V2HubView`, `NiKHubPreview`, `MCMActivateContainerPath` đều có 0 lần xuất hiện trong executable. Source ZIP không còn cây Vendor/3105, Vendor/WorseQuery hoặc Native/UpstreamCompatibility.

## Giới hạn kiểm chứng

Chưa thử trên iPhone thực tế. IPA build ra chưa có chữ ký cài đặt: cần ký bằng bộ chứng chỉ/profile phù hợp của người dùng. OCSP mạng và việc trình cài iOS chấp nhận chứng chỉ/profile/HTTPS cần thử trên máy. Không coi việc mở itms-services là bằng chứng đã cài thành công.

Kiểm tra thiết bị tiếp theo: khởi động/nhập IPA; chọn chứng chỉ riêng và ký batch; tải AltSource vào queue; xem/xóa hàng đợi; cài trust profile/full trust và thử cài từ mục Ứng dụng đã ký qua HTTPS/Safari. Giữ NiKSign chạy khi iOS tải IPA. Danh sách xóa/sửa file đầy đủ trong [SIGN-ONLY-REFACTOR.md](SIGN-ONLY-REFACTOR.md).

## Lịch sử sửa lỗi CI

- 44533181646: regression HTTP phát hiện fallback 501; đã thêm 404 handler trước token routes.
- 44533648315: regression và Xcode compile/IPA verification PASS; QA chặn cảnh báo AppIntents metadata.
- 44535871357: liên kết AppIntents.framework public của SDK để bộ tạo metadata Xcode 16 làm việc đúng; toàn bộ workflow PASS với 0 diagnostics. Không có source/capability exploit được khôi phục.

Các commit ghi kết quả sau build chỉ sửa tài liệu, dùng [skip ci] để không build app lặp lại. Mã được biên dịch là commit nêu ở trên.
