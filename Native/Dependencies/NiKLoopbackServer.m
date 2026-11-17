#import "NiKLoopbackServer.h"
#import "GCDWebServer.h"
#import "GCDWebServerFileResponse.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerErrorResponse.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

@interface NiKLoopbackServer ()
@property(nonatomic, strong) GCDWebServer *server;
@property(nonatomic, strong, readwrite, nullable) NSError *lastError;
@property(nonatomic, strong, readwrite, nullable) NSURL *fileURL;
@property(nonatomic, strong, readwrite, nullable) NSURL *manifestURL;
@property(nonatomic, strong, readwrite, nullable) NSURL *itmsInstallURL;
#if TARGET_OS_IPHONE
@property(nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
#endif
@end

@implementation NiKLoopbackServer

- (instancetype)init {
    if (self = [super init]) {
#if TARGET_OS_IPHONE
        _bgTask = UIBackgroundTaskInvalid;
#endif
    }
    return self;
}

- (nullable NSURL *)startFile:(NSURL *)fileURL {
    return [self startFile:fileURL
                  bundleID:@"com.apple.mobile.MobileHouseArrest"
                   version:@"1.0"
                     title:@"NiKSign App"
                 httpsHost:nil];
}

- (nullable NSURL *)startFile:(NSURL *)fileURL
                     bundleID:(NSString *)bundleID
                      version:(NSString *)version
                        title:(NSString *)title
                    httpsHost:(nullable NSString *)httpsHost {
    [self stop];
    self.lastError = nil;
    if ([httpsHost stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0) {
        self.lastError = [NSError errorWithDomain:@"NiKSign" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Máy chủ nội bộ chỉ hỗ trợ HTTP. Domain HTTPS không tự cung cấp TLS; hãy dùng dịch vụ HTTPS thực tế để cài OTA."}];
        return nil;
    }
    if (!fileURL.isFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:fileURL.path]) {
        self.lastError = [NSError errorWithDomain:@"NiKSign" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Không tìm thấy IPA đã xuất."}];
        return nil;
    }

    GCDWebServer *server = [GCDWebServer new];
    NSString *token = [NSUUID UUID].UUIDString;
    NSString *ipaRoute = [NSString stringWithFormat:@"/%@/app.ipa", token];
    NSString *manifestRoute = [NSString stringWithFormat:@"/%@/manifest.plist", token];

    NSString *safeBundleID = bundleID.length > 0 ? bundleID : @"app.niksign.signed";
    NSString *safeVersion = version.length > 0 ? version : @"1.0";
    NSString *safeTitle = title.length > 0 ? title : @"Signed App";

    // Serve only the selected IPA file and its generated OTA manifest; never expose directories, .p12 or profiles.
    [server addHandlerForMethod:@"GET" path:ipaRoute requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        return [GCDWebServerFileResponse responseWithFile:fileURL.path isAttachment:YES]
            ?: [GCDWebServerResponse responseWithStatusCode:404];
    }];

    __weak typeof(self) weakSelf = self;
    [server addHandlerForMethod:@"GET" path:manifestRoute requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        typeof(self) strongSelf = weakSelf;
        NSString *packageURLString = strongSelf.fileURL.absoluteString ?: @"";
        NSDictionary *manifest = @{
            @"items": @[
                @{
                    @"assets": @[
                        @{
                            @"kind": @"software-package",
                            @"url": packageURLString
                        }
                    ],
                    @"metadata": @{
                        @"bundle-identifier": safeBundleID,
                        @"bundle-version": safeVersion,
                        @"kind": @"software",
                        @"title": safeTitle
                    }
                }
            ]
        };
        NSError *plistError = nil;
        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:manifest
                                                                       format:NSPropertyListXMLFormat_v1_0
                                                                      options:0
                                                                        error:&plistError];
        if (!plistData) {
            return [GCDWebServerResponse responseWithStatusCode:500];
        }
        return [GCDWebServerDataResponse responseWithData:plistData contentType:@"application/xml"];
    }];

    NSDictionary *options = @{GCDWebServerOption_Port:@0,
        GCDWebServerOption_BindToLocalhost:@YES,
        GCDWebServerOption_AutomaticallySuspendInBackground:@NO};
    NSError *error = nil;
    if (![server startWithOptions:options error:&error]) {
        self.lastError = error;
        return nil;
    }

#if TARGET_OS_IPHONE
    UIApplication *app = [UIApplication sharedApplication];
    self.bgTask = [app beginBackgroundTaskWithName:@"NiKSignOTALoopback" expirationHandler:^{
        [self stop];
    }];
#endif

    self.server = server;
    unsigned long port = (unsigned long)server.port;

    NSString *baseOrigin = [NSString stringWithFormat:@"http://127.0.0.1:%lu", port];
    self.fileURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", baseOrigin, ipaRoute]];
    self.manifestURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", baseOrigin, manifestRoute]];
    // GCDWebServer serves HTTP. DNS or a URL scheme change cannot add TLS.
    // An actual HTTPS hosting/forwarding service is required before offering OTA.
    self.itmsInstallURL = nil;
    return self.fileURL;
}

- (void)stop {
    [self.server stop];
    self.server = nil;
    self.fileURL = nil;
    self.manifestURL = nil;
    self.itmsInstallURL = nil;
#if TARGET_OS_IPHONE
    if (self.bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
#endif
}

- (void)dealloc {
    [_server stop];
#if TARGET_OS_IPHONE
    if (_bgTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
        _bgTask = UIBackgroundTaskInvalid;
    }
#endif
}
@end
