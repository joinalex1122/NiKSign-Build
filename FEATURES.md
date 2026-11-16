# Phạm vi NiKSign 3.3-dev — đối chiếu nguồn thực tế & phần bổ sung 3105 2.0

Đã ghép toàn bộ 66 đơn vị biên dịch Swift/Objective-C/C trong cây nguồn công
khai của 3105 tại commit `a72617ed4c764a65d8aac1e91aca95231e72a2cb`, kết hợp
các module Sign IPA 3.2 và **bổ sung đầy đủ 4 nhóm chức năng 3105 2.0** theo đặc
tả tại `Vendor/3105/docs/PATCH_GUIDE.vi.md` và `Vendor/3105/README.vi.md`.

| Nhóm chức năng | Mã được nối vào app | Trạng thái |
|---|---|---|
| Trang chủ, Mới, Nguồn, Tìm kiếm, Đã cài | ContentView, RepositoryHomeView, RepositorySourcesView, RepositoryMarketplaceView, PackageRepositoryStore | Đã tích hợp nguồn và navigation |
| Duyệt data container ứng dụng | ContainerStore, ContainerIdentityResolver, ContainerBrowserLogic, AppDataBrowserView | Đã tích hợp; phụ thuộc quyền thiết bị |
| Workspace, nhiều tab tệp, thao tác file/folder, ZIP | FileManagerService, FileOperationCoordinator, FileBrowserView, FilesTabControls, ZIPArchiveWriter/Extractor | Đã tích hợp |
| Dự án patch, draft từ tệp/folder, nhập/xuất | PatchProjectStore/Library, PatchDraftService/Coordinator, PatchProjectsView, PatchProjectEditorView | Đã tích hợp |
| Gói 3105PATCH và mật khẩu/Keychain | PatchPackageCodec, PatchKeyStore, PatchProjectModels | Đã tích hợp nguyên bản upstream |
| Áp dụng thay tệp, sao lưu, restore, reset, rollback | DevicePatchService, PatchTransaction | Đã tích hợp; chưa thử ghi dữ liệu thật |
| Cleaner giới hạn theo danh mục & cài/gỡ tính năng | CleanerCatalog, LimitedCleanerService, CleanerView, NiKSystemFeaturesStore | Đã tích hợp đầy đủ (3.3) |
| Wallpaper/.tendies | WallpaperLabService/Models/View, WallpaperInstaller, SecureZIPArchive, wallpaper_zip.c | Đã tích hợp |
| Hỗ trợ iOS, MHA-C2 và kernel path upstream | SupportPolicy, KernelExploit, SBX, MG, exploit/, kexploit/ | Giữ nguyên nguồn upstream |
| Workspace Application/AppGroup, settings.json, schema v9, merge plist/JSON (`%3105_Overwrite%`, `%3105_MatchPrefix%`, `%3105_Remove%`) | NiKPatchV9Engine, NiKDynamicPayloadMerger, NiKWorkspaceV9Service, NiKContainerResolver | Đã triển khai theo đặc tả PATCH_GUIDE.vi.md (3.3) |
| Dialer `.3105pass` (nhận diện Sáng / Tối / Chữ đậm, sao lưu & khôi phục) | NiKDialerService, NiK3105V2HubView, Info.plist UTType | Đã triển khai (3.3) |
| Footnote màn hình khóa & Supervised | NiKSystemFeaturesStore, NiK3105V2HubView | Đã triển khai (3.3) |
| Quản lý nhiều chứng chỉ `.p12`/`.mobileprovision` & Keychain | NiKCertificateStore, NiKCertificateKeychain | Đã tích hợp (3.2) |
| Ký IPA Zsign, tùy biến Info.plist & tiến trình 6 bước | Signer, NiKSignToolsView | Đã tích hợp (3.2) |
| Chèn Tweak `.dylib` & giải nén `.deb` | NiKDylibInjector | Đã tích hợp (3.2) |
| Máy chủ OTA `manifest.plist` & `itms-services://` | NiKLoopbackServer.h/.m | Đã tích hợp (3.2) |
| Trình duyệt kho AltSource JSON & tải IPA | NiKAltSourceStore, NiKAltSourceView | Đã tích hợp (3.2) |
