#import "NiKAccessEnvironmentReader.h"
#import <dlfcn.h>

NSArray<NSString *> *NiKSignedAppGroupIdentifiers(NSError **error) {
    typedef CFTypeRef (*CreateTask)(CFAllocatorRef);
    typedef CFTypeRef (*CopyValue)(CFTypeRef, CFStringRef, CFErrorRef *);
    CreateTask create = (CreateTask)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    CopyValue copy = (CopyValue)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!create || !copy) {
        if (error) *error = [NSError errorWithDomain:@"NiKSign.Access" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Không đọc được entitlement của tiến trình hiện tại."}];
        return nil;
    }
    CFTypeRef task = create(kCFAllocatorDefault);
    if (!task) return nil;
    CFErrorRef failure = NULL;
    CFTypeRef value = copy(task, CFSTR("com.apple.security.application-groups"), &failure);
    CFRelease(task);
    if (failure) {
        NSError *detail = CFBridgingRelease(failure);
        if (value) CFRelease(value);
        // errSecMissingEntitlement is distinct from a reader failure.
        if (detail.code == -34018) return @[];
        if (error) *error = detail;
        return nil;
    }
    if (!value) return @[];
    id object = CFBridgingRelease(value);
    if (![object isKindOfClass:NSArray.class] || [object count] > 128) return nil;
    NSMutableOrderedSet<NSString *> *groups = [NSMutableOrderedSet orderedSet];
    for (id item in object) {
        if (![item isKindOfClass:NSString.class] || [item length] == 0 || [item length] > 255) return nil;
        [groups addObject:item];
    }
    return groups.array;
}
