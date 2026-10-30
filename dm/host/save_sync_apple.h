// Complete, immutable save checkpoints in a user-selected document-provider folder.
// Configure/prepare before guest boot. Live commits only publish; they never pull.
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface DMSaveSync : NSObject
+ (instancetype)shared;
- (instancetype)initWithLocalURL:(NSURL *)local title:(NSString *)title version:(NSString *)version device:(NSString *)device;
@property(readonly) NSDictionary *status;
- (BOOL)selectFolder:(NSURL *)folder error:(NSError **)error;
- (void)disconnect;
- (NSDictionary * _Nullable)inspect:(NSError **)error;
- (BOOL)prepareChoice:(NSString *)choice token:(NSString *)token error:(NSError **)error;
- (void)beginSession;
- (void)beginOfflineSession;
- (void)cancel;
- (void)captureCommit:(NSString *)path;
- (void)flush; // Wait for queued local checkpoint processing; not a cloud-upload acknowledgement.
- (NSDictionary * _Nullable)saveCenter:(NSError **)error;
- (BOOL)createCheckpoint:(NSString *)name error:(NSError **)error;
- (BOOL)restoreCheckpoint:(NSString *)identifier token:(NSString *)token error:(NSError **)error;
- (BOOL)deleteCheckpoint:(NSString *)identifier error:(NSError **)error;
@end
NSString *dm_save_sync_text(NSString *key);
void dm_save_sync_committed(const char *path);
// The Mac UI gates guest startup; headless runs never open a dialog.
void dm_save_sync_mac_prepare(void (^ready)(void));
void dm_save_sync_mac_menu(void);
NS_ASSUME_NONNULL_END
