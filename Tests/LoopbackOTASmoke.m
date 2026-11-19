#import <Foundation/Foundation.h>
#import "NiKLoopbackServer.h"
#include <stdio.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) { return 2; }
        NSURL *file = [NSURL fileURLWithPath:@(argv[1])];
        NSString *stopPath = @(argv[2]);
        NiKLoopbackServer *server = [NiKLoopbackServer new];
        NSURL *endpoint = [server startFile:file];
        if (!endpoint || !server.isRunning) { return 3; }
        printf("HTTP_READY %s\n", endpoint.absoluteString.UTF8String);
        fflush(stdout);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
        while ([deadline timeIntervalSinceNow] > 0 && ![NSFileManager.defaultManager fileExistsAtPath:stopPath]) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        [server stop];
        if (server.isRunning || server.fileURL) { return 4; }
        printf("HTTP_STOPPED\n");
        fflush(stdout);
    }
    return 0;
}
