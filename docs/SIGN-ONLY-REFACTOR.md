# Bàn giao refactor Sign-only — 2026-11-19

Working tree: `/workspace/NiKSign-upgrades`, base `38226a33a0c325a11e4d47dbecd75358b81d1c5f`. Người dùng đã xác nhận nhánh CI tạm. Bản 3.4.0 (340), commit 01cbc2f186478ced39e4f9167f31b95b1e58fbcc đã PASS toàn bộ workflow 44535871357 trên macOS/Xcode với 0 warning/error diagnostics.

## Đã thực hiện

1. Gỡ AppState/auto exploit/chọn chế độ; ba tab Ký IPA / Tệp / Cài đặt. Onboarding và tiếng Việt/Anh dùng nik.language. Giữ import IPA, p12/profile/dylib/deb.
2. Xóa toàn bộ cây Vendor/3105, Vendor/WorseQuery, overlay, bridge và engine liên quan. Các file UI trộn được tách theo view/hàm, giữ phần signer/cert/injection/local files. Tạo NiKPathValidator độc lập. Bundle ID mặc định com.niksign.app, chặn namespace com.apple.* ở signer và build helper.
3. Ký ngay, ký hàng loạt, menu từng IPA và AltSource cùng dùng NiKSigningQueue với ID chứng chỉ và snapshot options riêng. Import thành công trả về chính item mới, tránh suy đoán theo vị trí danh sách.
4. Cài HTTPS qua NiKHTTPSOTAServer, identity Keychain và trust profile; manifest metadata thật, snapshot tệp bất biến, Safari landing page escape HTML, QR/link chỉ chính iPhone. Bỏ public static manifest “Local app”. Kết quả và hàng đợi có nút cài.
5. OCSP khi app hoạt động/chọn chứng chỉ; chống kiểm tra trùng, backoff lỗi, đếm ngược và cảnh báo còn <=7 ngày. Không coi lỗi mạng là tốt.
6. Native Zsign sửa application-identifier cụ thể từ App ID seed từng app/extension; XML/DER nhất quán; giá trị get-task-allow đúng. Stage profile trong mọi app/appex trước resource seal và kiểm tra CMS/entitlement identity sau ký. Không bypass provisioning của iOS.
7. Viết lại README/FEATURES/VALIDATION/DEPENDENCIES/THIRD_PARTY_NOTICES; chuyển tài liệu cũ vào docs/history với prefix pre-sign-only. Giữ giấy phép GPL của NiKSign và giấy phép các thư viện đang dùng.

## Kiểm chứng hoàn tất

- PASS: check-integration.py, check-dependencies.py, bash syntax.
- PASS trên macOS: xcodegen generate; xcodebuild iphoneos arm64 với CODE_SIGNING_ALLOWED=NO; 0 compiler warnings/errors; IPA CRC/arm64/metadata validator.
- PASS: toàn bộ regression native/Swift trong audit, 45 dòng PASS, gồm CMS thật (khóa tổng hợp), profile seal, từng extension, queue cancellation/removal, Keychain/PKCS12, TLS, download/hash, xử lý/khôi phục tệp.
- IPA 3.4.0 (340): 5,484,504 bytes, SHA-256 310d65f1eec68eabf2fed87dad763e8795f39e28f10f74734c3c304244e718ac. Artifact 14536028345 chứa đúng một IPA.
- Binary scan: 8 marker query/exploit/identity cũ đều 0; source ZIP không chứa các cây vendor/overlay đã gỡ.
- Chưa kiểm thử iPhone: cần người dùng ký cài IPA, kiểm tra luồng thực tế và OTA. Kết quả test synthetic không chứng minh Apple chấp nhận chứng chỉ.

Xem [bằng chứng build](VERIFIED-SIGN-ONLY-3.4.0.md) và [workflow 44535871357](https://github.com/joinalex1122/NiKSign-Build/actions/runs/44535871357). Commit ghi kết quả sau đó chỉ sửa tài liệu, không thay mã đã build và không chạy app build lần hai.

## File đã xóa (169)

- `Native/Dependencies/NiK3105V2HubView.swift`
- `Native/Dependencies/NiKAccessEnvironmentReader.h`
- `Native/Dependencies/NiKAccessEnvironmentReader.m`
- `Native/Dependencies/NiKDialerService.swift`
- `Native/Dependencies/NiKPatchV9Engine.swift`
- `Native/Dependencies/NiKSystemFeaturesService.swift`
- `Native/Integration/RepositoryHomeView.swift`
- `Native/Integration/SupportPolicy.swift`
- `Native/Licenses/TrollFools-LICENSE.txt`
- `Native/Licenses/WorseQuery-LICENSE.txt`
- `Native/Licenses/ellekit-LICENSE.txt`
- `Native/Licenses/optool-LICENSE.txt`
- `Native/Models/NiK3105AccessAssessment.swift`
- `Native/Models/NiKSemiLocalOTA.swift`
- `Native/Models/NiKWorseQueryPolicy.swift`
- `Native/Services/NiKGroupCacheTransaction.swift`
- `Native/Services/NiKPatchContainerAccess.swift`
- `Native/Services/NiKPatchSchema9Compatibility.swift`
- `Native/Services/NiKWorseQueryAccess.swift`
- `Native/UpstreamCompatibility/ContentView.swift`
- `Native/UpstreamCompatibility/helpers/ContainerStore.swift`
- `Native/UpstreamCompatibility/helpers/DevicePatchService.swift`
- `Native/UpstreamCompatibility/helpers/DisplayIdentityAttribution.swift`
- `Native/UpstreamCompatibility/helpers/Localization.swift`
- `Native/UpstreamCompatibility/helpers/PatchPackageCodec.swift`
- `Native/UpstreamCompatibility/kexploit/kexploit_opa334.m`
- `Native/UpstreamCompatibility/kexploit/krw.m`
- `Native/UpstreamCompatibility/views/LogView.swift`
- `Native/UpstreamCompatibility/views/PatchProjectsView.swift`
- `Native/Views/NiK3105AccessView.swift`
- `NiKSign-Web-Standalone.html`
- `Tests/CodecSmoke.swift`
- `Tests/PatchContainerAccessSmoke.swift`
- `Tests/PatchSchema9Smoke.swift`
- `Tests/PatchV9Smoke.swift`
- `Tests/PatchV9TransactionSmoke.swift`
- `Tests/WorseQuerySafetySmoke.swift`
- `Tests/browser.cjs`
- `Tests/patch_v9_test.py`
- `Tests/web-preview.png`
- `Tests/web.test.js`
- `Vendor/3105/CHANGELOG.md`
- `Vendor/3105/LICENSE`
- `Vendor/3105/README.md`
- `Vendor/3105/README.vi.md`
- `Vendor/3105/THIRD_PARTY_NOTICES.md`
- `Vendor/3105/ThreeOneOSFive.xcodeproj/project.pbxproj`
- `Vendor/3105/ThreeOneOSFive/App.swift`
- `Vendor/3105/ThreeOneOSFive/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- `Vendor/3105/ThreeOneOSFive/Assets.xcassets/AppIcon.appiconset/Contents.json`
- `Vendor/3105/ThreeOneOSFive/Assets.xcassets/Contents.json`
- `Vendor/3105/ThreeOneOSFive/ContentView.swift`
- `Vendor/3105/ThreeOneOSFive/Info.plist`
- `Vendor/3105/ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h`
- `Vendor/3105/ThreeOneOSFive/en.lproj/Localizable.strings`
- `Vendor/3105/ThreeOneOSFive/exploit/bad_query.c`
- `Vendor/3105/ThreeOneOSFive/exploit/bad_query.h`
- `Vendor/3105/ThreeOneOSFive/exploit/mcm_bridge.h`
- `Vendor/3105/ThreeOneOSFive/exploit/mcm_bridge.m`
- `Vendor/3105/ThreeOneOSFive/exploit/wallpaper_zip.c`
- `Vendor/3105/ThreeOneOSFive/exploit/wallpaper_zip.h`
- `Vendor/3105/ThreeOneOSFive/helpers/AntiDetection.m`
- `Vendor/3105/ThreeOneOSFive/helpers/AppIconHelper.h`
- `Vendor/3105/ThreeOneOSFive/helpers/AppIconHelper.m`
- `Vendor/3105/ThreeOneOSFive/helpers/AppTabNavigationState.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/CleanerCatalog.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/ContainerBrowserLogic.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/ContainerIdentityResolver.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/ContainerStore.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/DevicePatchService.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/DisplayIdentity.h`
- `Vendor/3105/ThreeOneOSFive/helpers/DisplayIdentity.m`
- `Vendor/3105/ThreeOneOSFive/helpers/DisplayIdentityAttribution.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/FileBrowserMetadata.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/FileManagerService.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/FileOperationCoordinator.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/FileReplacementService.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/KernelExploit.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/LimitedCleanerService.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/Localization.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/MG.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/PackageRepositoryModels.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/PackageRepositoryStore.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/PatchDraftCoordinator.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/PatchDraftService.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/PatchKeyStore.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/PatchPackageCodec.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/PatchProjectLibrary.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/PatchProjectModels.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/PatchProjectStore.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/PatchTransaction.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/PatchWorkspaceService.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/RepositoryPresentationSupport.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/SBX.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/SecureZIPArchive.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/SupportPolicy.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/Utils.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/WallpaperInstaller.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/WallpaperLabModels.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/WallpaperLabService.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/ZIPArchiveExtractor.swift`
- `Vendor/3105/ThreeOneOSFive/helpers/ZIPArchiveWriter.swift`
- `Vendor/3105/ThreeOneOSFive/kexploit/kexploit_opa334.h`
- `Vendor/3105/ThreeOneOSFive/kexploit/kexploit_opa334.m`
- `Vendor/3105/ThreeOneOSFive/kexploit/krw.h`
- `Vendor/3105/ThreeOneOSFive/kexploit/krw.m`
- `Vendor/3105/ThreeOneOSFive/kexploit/kutils.h`
- `Vendor/3105/ThreeOneOSFive/kexploit/kutils.m`
- `Vendor/3105/ThreeOneOSFive/kexploit/machine_info.h`
- `Vendor/3105/ThreeOneOSFive/kexploit/offsets.h`
- `Vendor/3105/ThreeOneOSFive/kexploit/offsets.m`
- `Vendor/3105/ThreeOneOSFive/kexploit/sandbox_escape.h`
- `Vendor/3105/ThreeOneOSFive/kexploit/sandbox_escape.m`
- `Vendor/3105/ThreeOneOSFive/kexploit/vnode.h`
- `Vendor/3105/ThreeOneOSFive/kexploit/vnode.m`
- `Vendor/3105/ThreeOneOSFive/kexploit/xpaci.h`
- `Vendor/3105/ThreeOneOSFive/vi.lproj/Localizable.strings`
- `Vendor/3105/ThreeOneOSFive/views/AppDataBrowserView.swift`
- `Vendor/3105/ThreeOneOSFive/views/CleanerView.swift`
- `Vendor/3105/ThreeOneOSFive/views/DesignSystem.swift`
- `Vendor/3105/ThreeOneOSFive/views/FileBrowserView.swift`
- `Vendor/3105/ThreeOneOSFive/views/FilesTabControls.swift`
- `Vendor/3105/ThreeOneOSFive/views/FilesTabSwitcherView.swift`
- `Vendor/3105/ThreeOneOSFive/views/FolderPatchSelectionView.swift`
- `Vendor/3105/ThreeOneOSFive/views/LogView.swift`
- `Vendor/3105/ThreeOneOSFive/views/OnboardingView.swift`
- `Vendor/3105/ThreeOneOSFive/views/PatchProjectEditorView.swift`
- `Vendor/3105/ThreeOneOSFive/views/PatchProjectsView.swift`
- `Vendor/3105/ThreeOneOSFive/views/RepositoryHomeView.swift`
- `Vendor/3105/ThreeOneOSFive/views/RepositoryMarketplaceView.swift`
- `Vendor/3105/ThreeOneOSFive/views/RepositorySourcesView.swift`
- `Vendor/3105/ThreeOneOSFive/views/SettingsView.swift`
- `Vendor/3105/ThreeOneOSFive/views/WallpaperLabView.swift`
- `Vendor/3105/ThreeOneOSFive/zh-Hans.lproj/Localizable.strings`
- `Vendor/3105/docs/PATCH_GUIDE.md`
- `Vendor/3105/docs/PATCH_GUIDE.vi.md`
- `Vendor/3105/docs/REPOSITORY_GUIDE.vi.md`
- `Vendor/3105/docs/images/app-icon.png`
- `Vendor/3105/docs/images/cleaner.png`
- `Vendor/3105/docs/images/home-2.0.png`
- `Vendor/3105/docs/images/home.png`
- `Vendor/3105/docs/images/installed-2.0.png`
- `Vendor/3105/docs/images/patches.png`
- `Vendor/3105/docs/images/sources-2.0.png`
- `Vendor/3105/docs/releases/1.0.1.md`
- `Vendor/WorseQuery/LICENSE`
- `Vendor/WorseQuery/UPSTREAM.json`
- `Vendor/WorseQuery/worse_query.h`
- `Vendor/WorseQuery/worse_query.m`
- `docs/3105-27.2-ACCESS-FINDINGS.md`
- `docs/APPROVED-UPGRADE-SCOPE.md`
- `docs/BAN-GIAO-HIEN-TAI.md`
- `docs/BUILD-5e43918-UPLOAD-FAILURE.md`
- `docs/ERROR-CHECK-2026-11-17.md`
- `docs/HANDOFF-2026-11-17.md`
- `docs/LATEST-REVIEW.md`
- `docs/UPGRADE-PROGRESS.md`
- `docs/VERIFIED-BUILD-4460603.md`
- `docs/VERIFIED-BUILD-4d9b7e2.md`
- `docs/VERIFIED-BUILD-5229db4.md`
- `docs/ZSIGN-PROVISIONING-FIX.md`
- `docs/reliability-build.md`
- `docs/ui-preview.md`
- `scripts/fetch-reference-sources.py`
- `upstream-lock.json`
- `upstream-overlays.json`
- `web/app.js`
- `web/core.js`
- `web/index.html`

## File đã sửa (45)

| File | Thay đổi |
|---|---|
| `.github/workflows/build.yml` | Gỡ test patch/web; audit/build một lượt, artifact một IPA; archive nguồn chỉ các file hiện tồn tại. |
| `DEPENDENCIES.md` | Vai trò/pinning/license của signer dependencies và sửa Zsign. |
| `FEATURES.md` | Bảng chức năng signer, cert, queue, source, OTA, file sandbox và lịch OCSP. |
| `Native/Dependencies/NiKAltSourceView.swift` | Tải & xếp hàng với chứng chỉ được chụp khi bấm, hoặc chỉ tải thư viện. |
| `Native/Dependencies/NiKBinaryInspector.swift` | Postcondition mọi slice phải có CMS và application/team entitlements khớp bundle. |
| `Native/Dependencies/NiKCertificateStore.swift` | Lịch OCSP selected profile, chống trùng, backoff và hiển thị lỗi auto-check. |
| `Native/Dependencies/NiKHTTPSOTAServer.swift` | Trang cài Safari HTTPS token riêng, metadata escape HTML; expose landingURL. |
| `Native/Dependencies/NiKLoopbackServer.h` | Bỏ API static public-manifest transport. |
| `Native/Dependencies/NiKLoopbackServer.m` | Bỏ static transport/Apple identity mặc định; HTTP file/token hỗ trợ Range; giữ bootstrap trust profile. |
| `Native/Info.plist` | Chỉ URL scheme niksign và các kiểu tài liệu cho signer; bỏ metadata/quyền liên quan app cũ. |
| `Native/Integration/App.swift` | Entry Sign-only, gỡ exploit/state cũ, giữ import; monitor OCSP chứng chỉ đang chọn khi app active. |
| `Native/Licenses/components.json` | Danh mục 8 thư viện thực dùng, gỡ dependency đã bỏ. |
| `Native/Models/NiKOTAURLs.swift` | Chỉ chấp nhận manifest HTTPS loopback; giữ encoding URL lồng nhau. |
| `Native/NiKFilePicker.swift` | Giữ document picker/QuickLook và liên kết sandbox NiKSign; bỏ duyệt container ứng dụng khác. |
| `Native/NiKFileViews.swift` | Tách bỏ Hub/dashboard, giữ viewer, file models, share/folder picker và IPA icon. |
| `Native/NiKPreviewUI.swift` | Ba tab cố định; import trả item cụ thể; enqueue chọn chứng chỉ; thêm hành động xếp hàng bên cạnh ký ngay. |
| `Native/NiKSettingsView.swift` | Bỏ mode/access UI cũ; giữ signer/cert/OTA/theme/language. |
| `Native/NiKSign-Bridging-Header.h` | Chỉ bridge ZIP check và HTTP loopback phục vụ signer. |
| `Native/NiKSignToolsView.swift` | Gỡ patch/password/editor liên quan; giữ p12/profile/dylib/deb; ký qua queue, kết quả cài HTTPS, components lưu Documents. |
| `Native/Services/NiKInstallationController.swift` | Chỉ local HTTPS với snapshot/reservation, system trust, counters; bỏ consent/public service. |
| `Native/Signer.swift` | Validator riêng; cấm com.apple.*; stage profile mọi app/appex trước seal, kiểm tra profile/CMS/identity sau ký. |
| `Native/Views/NiKCertificateStatusView.swift` | Cảnh báo <=7 ngày; hiển thị lỗi kiểm tra định kỳ. |
| `Native/Views/NiKInstallIPAView.swift` | QR/link/copy/share và Safari, trust setup, chỉ số tải; không tự coi open URL là cài thành công. |
| `Native/Views/NiKSigningQueueView.swift` | Chọn chứng chỉ mỗi dòng batch; cài HTTPS từ output; giữ xóa/hủy an toàn. |
| `Native/Views/NiKTrustSetupView.swift` | Hướng dẫn local HTTPS riêng và nút Để sau, không còn public-manifest mode. |
| `README.md` | Mô tả công cụ resign IPA, build và hướng dẫn local OTA đúng giới hạn. |
| `THIRD_PARTY_NOTICES.md` | Thông báo các thư viện còn phân phối; giữ GPL cho NiKSign. |
| `Tests/FileImportSmoke.swift` | Gỡ support-policy assertions; giữ regression import/Unicode/duplicate/cleanup. |
| `Tests/LoopbackOTASmoke.m` | Chạy API tokenized HTTP file thật, kiểm shutdown. |
| `Tests/OTAURLsSmoke.swift` | Kiểm local-only itms URL encoding và chống chèn HTML từ metadata. |
| `Tests/loopback_ota_test.py` | Full/Range/HEAD, token route isolation và shutdown của API giữ lại. |
| `Tests/verify_ipa_test.py` | Fixture scheme mới, giữ 7 regression validator. |
| `VALIDATION.md` | Kết quả bản hiện tại; phân biệt Linux PASS với Xcode/iPhone chưa kiểm chứng. |
| `Vendor/Zsign/UPSTREAM.json` | Hash và replacements có thể đảo ngược cho patch native entitlement/debug flags. |
| `Vendor/Zsign/src/archo.cpp` | Chuẩn hóa application ID/keychain theo bundle/profile seed; XML/DER cùng nguồn; sửa get-task-allow flags. |
| `dependencies-vendor-lock.json` | Hash Zsign bản sửa; bỏ nguồn vendor bị gỡ. |
| `docs/BAN-GIAO-GEMINI.md` | Chuyển bàn giao hiện hành tới báo cáo refactor này. |
| `project.yml` | Gỡ nguồn/header exploit/private frameworks; giữ target signer và bundle namespace riêng. |
| `scripts/audit-ios.sh` | Gỡ test nguồn đã xóa; thêm path/OCSP/CMS; một bộ audit, một build, output audit-results/build. |
| `scripts/build-ios.sh` | Chặn namespace Apple/custom ID sai trước build; mặc định com.niksign.app. |
| `scripts/check-dependencies.py` | Kiểm tra 8 deps/license/hash, provenance native gốc và server overlay; gỡ module cũ. |
| `scripts/check-integration.py` | Kiểm tra nguồn Sign-only/entry/routing/metadata/overlay; từ chối symbol đã gỡ. |
| `scripts/github-package.sh` | Không tự commit/push khi thiếu Xcode; yêu cầu audit macOS trước review/commit. |
| `scripts/test-certificates.sh` | Thêm production OCSP schedule vào harness CertificateSmoke. |
| `scripts/verify-ipa.py` | Chỉ scheme niksign; bỏ yêu cầu localization resource của app cũ, vẫn kiểm arm64/CRC/bounds. |

## File thêm mới / lịch sử chuyển vị trí

- `Native/Models/NiKOTALandingPage.swift`
- `Native/Models/NiKRevocationSchedule.swift`
- `Native/Services/NiKPathValidator.swift`
- `Tests/PathValidatorSmoke.swift`
- `Tests/RevocationScheduleSmoke.swift`
- `Tests/ZsignCMS/main.cpp`
- `Tests/zsign_cms_test.py`
- `docs/SIGN-ONLY-REFACTOR.md`
- `docs/history/pre-sign-only-3105-27.2-ACCESS-FINDINGS.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-APPROVED-UPGRADE-SCOPE.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-BAN-GIAO-GEMINI.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-BAN-GIAO-HIEN-TAI.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-BUILD-5e43918-UPLOAD-FAILURE.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-ERROR-CHECK-2026-11-17.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-HANDOFF-2026-11-17.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-LATEST-REVIEW.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-UPGRADE-PROGRESS.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-VERIFIED-BUILD-4460603.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-VERIFIED-BUILD-4d9b7e2.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-VERIFIED-BUILD-5229db4.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-ZSIGN-PROVISIONING-FIX.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-reliability-build.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.
- `docs/history/pre-sign-only-ui-preview.md` — tài liệu lịch sử, không phải cấu hình/hướng dẫn hiện hành.

Các file production mới: `NiKPathValidator.swift` (bundle/path riêng), `NiKRevocationSchedule.swift` (lịch/backoff OCSP), `NiKOTALandingPage.swift` (HTML cài đặt escape an toàn). Các test mới: `PathValidatorSmoke`, `RevocationScheduleSmoke`, `ZsignCMS/main.cpp`, `zsign_cms_test.py`.

## Đối chiếu main và kết quả CI

Đã nhập history main 39d17db vào nhánh CI, giữ hai chỉnh sửa padding của người dùng; các thay đổi Apple identity/exploit được thay thế đúng yêu cầu Sign-only. Pre-copy profile mở rộng cho app/appex và build một lượt được giữ. AppIntents.framework chỉ là framework public của SDK, được liên kết để giải quyết cảnh báo metadata Xcode 16.

Hai lỗi CI đã sửa: fallback HTTP 501→404; cảnh báo thiếu SDK metadata framework. Lần cuối 44535871357 PASS. Không gỡ test hay hạ cổng QA. Mã build 01cbc2f là ancestor của commit ghi kết quả tài liệu.

File tài liệu xác nhận thêm sau build: `docs/VERIFIED-SIGN-ONLY-3.4.0.md`. Các cập nhật cuối ở VALIDATION.md, DEPENDENCIES.md và hai file bàn giao chỉ ghi kết quả và giới hạn kiểm chứng.
