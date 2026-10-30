// No filesystem or cloud IO: exercise the production Swift presentation model.
#import "cloud_save_stub.h"
#include <stdatomic.h>
static _Atomic int selections,inspections,preparations,sessions,failSelection;
int cloud_test_selects(void){return atomic_load(&selections);}
int cloud_test_inspections(void){return atomic_load(&inspections);}
int cloud_test_prepares(void){return atomic_load(&preparations);}
int cloud_test_sessions(void){return atomic_load(&sessions);}
void cloud_test_fail_selection(int fail){atomic_store(&failSelection,fail);}
@implementation DMSaveSync {
    BOOL configured;
    NSString *folder;
}
+ (instancetype)shared {static DMSaveSync *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
- (NSDictionary *)status {@synchronized(self){return @{@"configured":@(configured),@"folder":folder ?: @"",@"message":configured ? @"Cloud folder connected.":@"Cloud sync is not configured."};}}
- (BOOL)selectFolder:(NSURL *)url error:(NSError **)error {
    atomic_fetch_add(&selections,1);
    if(atomic_load(&failSelection)){if(error)*error=[NSError errorWithDomain:@"cloud-test" code:13 userInfo:@{NSLocalizedDescriptionKey:@"Selection failed."}];return NO;}
    @synchronized(self){configured=YES;folder=url.lastPathComponent;}return YES;
}
- (void)disconnect {@synchronized(self){configured=NO;folder=nil;}}
- (NSDictionary *)inspect:(NSError **)error {(void)error;atomic_fetch_add(&inspections,1);return @{@"token":@"test-token",@"conflict":@NO,@"choices":@[]};}
- (BOOL)prepareChoice:(NSString *)choice token:(NSString *)token error:(NSError **)error {(void)choice;(void)token;(void)error;atomic_fetch_add(&preparations,1);return YES;}
- (void)beginSession {atomic_fetch_add(&sessions,1);}
- (void)beginOfflineSession {}
- (void)cancel {}
- (NSDictionary *)saveCenter:(NSError **)error {(void)error;return @{@"history":@[],@"fileCount":@0,@"uploadState":@"Not connected"};}
- (BOOL)createCheckpoint:(NSString *)name error:(NSError **)error {(void)name;(void)error;return YES;}
- (BOOL)restoreCheckpoint:(NSString *)identifier token:(NSString *)token error:(NSError **)error {(void)identifier;(void)token;(void)error;return YES;}
- (BOOL)deleteCheckpoint:(NSString *)identifier error:(NSError **)error {(void)identifier;(void)error;return YES;}
@end
NSString *dm_save_sync_text(NSString *key){return key;}
