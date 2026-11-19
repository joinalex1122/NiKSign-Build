#import "NiKLoopbackServer.h"
#import "GCDWebServer.h"
#import "GCDWebServerFileResponse.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerErrorResponse.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

static NSDictionary *NiKLoopbackOptions(NSUInteger port) {
    NSMutableDictionary *options = [@{GCDWebServerOption_Port:@(port), GCDWebServerOption_BindToLocalhost:@YES} mutableCopy];
#if TARGET_OS_IPHONE
    options[GCDWebServerOption_AutomaticallySuspendInBackground] = @NO;
#endif
    return options;
}

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

    NSDictionary *options = NiKLoopbackOptions(0);
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

- (nullable NSURL *)startTrustProfile:(NSData *)profileData {
    [self stop];
    self.lastError = nil;
    if (profileData.length == 0 || profileData.length > 65536) { return nil; }
    GCDWebServer *server = [GCDWebServer new];
    NSString *route = [NSString stringWithFormat:@"/%@/NiKSign-HTTPS.mobileconfig", [NSUUID UUID].UUIDString];
    [server addHandlerForMethod:@"GET" path:route requestClass:GCDWebServerRequest.class processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        return [GCDWebServerDataResponse responseWithData:profileData contentType:@"application/x-apple-aspen-config"];
    }];
    NSError *error = nil;
    if (![server startWithOptions:NiKLoopbackOptions(0) error:&error]) {
        self.lastError = error; return nil;
    }
    self.server = server;
    self.fileURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%lu%@", (unsigned long)server.port, route]];
#if TARGET_OS_IPHONE
    self.bgTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"NiKSignTrustProfile" expirationHandler:^{ [self stop]; }];
#endif
    return self.fileURL;
}

- (BOOL)isRunning { return self.server.isRunning; }

- (nullable NSURL *)startStaticOTAFile:(NSURL *)fileURL {
    [self stop];
    self.lastError = nil;
    NSNumber *regular = nil;
    [fileURL getResourceValue:&regular forKey:NSURLIsRegularFileKey error:NULL];
    if (!fileURL.isFileURL || !regular.boolValue) { return nil; }
    // Static manifests are available for these ports. Retry occupied ports without
    // falling back to a LAN interface or exposing anything except this one IPA.
    for (NSUInteger attempt = 0; attempt < 32; attempt++) {
        GCDWebServer *server = [GCDWebServer new];
        [server addDefaultHandlerForMethod:@"GET" requestClass:GCDWebServerRequest.class processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
            return [GCDWebServerResponse responseWithStatusCode:404];
        }];
        [server addHandlerForMethod:@"GET" path:@"/health" requestClass:GCDWebServerRequest.class processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
            return [GCDWebServerDataResponse responseWithData:[@"NiKSign Local Payload" dataUsingEncoding:NSUTF8StringEncoding] contentType:@"text/plain"];
        }];
        __weak typeof(self) weakSelf = self;
        __weak GCDWebServer *weakServer = server;
        [server addHandlerForMethod:@"GET" path:@"/ota-me" requestClass:GCDWebServerRequest.class processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (strongSelf.server == weakServer && strongSelf.onIPARequest) { strongSelf.onIPARequest(); }
            });
            GCDWebServerFileResponse *response = [GCDWebServerFileResponse responseWithFile:fileURL.path byteRange:request.byteRange isAttachment:NO];
            return response ?: [GCDWebServerResponse responseWithStatusCode:416];
        }];
        NSUInteger port = 4000 + arc4random_uniform(5000);
        NSError *error = nil;
        if (![server startWithOptions:NiKLoopbackOptions(port) error:&error]) {
            self.lastError = error;
            continue;
        }
        self.server = server;
        self.lastError = nil;
        self.fileURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%lu/ota-me", (unsigned long)server.port]];
#if TARGET_OS_IPHONE
        self.bgTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"NiKSignLocalPayload" expirationHandler:^{ [self stop]; }];
#endif
        return self.fileURL;
    }
    return nil;
}

- (void)stop {
    [self.server stop];
    self.server = nil;
    self.fileURL = nil;
    self.manifestURL = nil;
    self.itmsInstallURL = nil;
    if (self.onStopped) { self.onStopped(); }
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
