#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Reads only this process's signed App Group entitlement; never reads pairing records.
FOUNDATION_EXPORT NSArray<NSString *> * _Nullable NiKSignedAppGroupIdentifiers(NSError * _Nullable * _Nullable error) NS_SWIFT_NOTHROW;
NS_ASSUME_NONNULL_END
