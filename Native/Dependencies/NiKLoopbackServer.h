#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface NiKLoopbackServer : NSObject
@property(nonatomic, strong, readonly, nullable) NSError *lastError;
@property(nonatomic, strong, readonly, nullable) NSURL *fileURL;
@property(nonatomic, strong, readonly, nullable) NSURL *manifestURL;
@property(nonatomic, strong, readonly, nullable) NSURL *itmsInstallURL;
- (nullable NSURL *)startFile:(NSURL *)fileURL NS_SWIFT_NAME(start(file:));
- (nullable NSURL *)startFile:(NSURL *)fileURL
                     bundleID:(NSString *)bundleID
                      version:(NSString *)version
                        title:(NSString *)title
                    httpsHost:(nullable NSString *)httpsHost
    NS_SWIFT_NAME(start(file:bundleID:version:title:httpsHost:));
- (nullable NSURL *)startTrustProfile:(NSData *)profileData NS_SWIFT_NAME(startTrustProfile(data:));
@property(nonatomic, copy, nullable) void (^onStopped)(void);
@property(nonatomic, readonly, getter=isRunning) BOOL running;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
