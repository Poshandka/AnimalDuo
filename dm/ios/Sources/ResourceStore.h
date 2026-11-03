// Immutable game assets survive app-bundle replacement in Application Support.
#pragma once
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface DMResourceStore:NSObject
@property(readonly) NSURL *bundle,*directory;
@property(readonly) NSDictionary *requirements;
- (instancetype)initWithBundle:(NSURL *)bundle support:(NSURL *)support title:(NSString * _Nullable)title version:(NSString *)version chain:(NSString *)chain;
- (BOOL)ready:(NSError * _Nullable * _Nullable)error;
- (BOOL)hasInstaller;
- (BOOL)installWithProgress:(void (^ _Nullable)(uint64_t,uint64_t,NSUInteger,NSUInteger))progress cancelled:(BOOL (^ _Nullable)(void))cancelled error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
