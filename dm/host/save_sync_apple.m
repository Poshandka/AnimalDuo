#import "save_sync_apple.h"
#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif
#include <sys/clonefile.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include "game_profile.h"
#include "front.h"

static const NSUInteger maxBytes = 256u << 20, maxFiles = 4096;
NSString *dm_save_sync_text(NSString *key) {
    NSBundle *bundle=NSBundle.mainBundle;const char *lang=getenv("DM_LANG");
    if(lang && !strncmp(lang,"zh",2)){NSString *path=[bundle pathForResource:@"zh-Hans" ofType:@"lproj"];if(path)bundle=[NSBundle bundleWithPath:path];}
    return [bundle localizedStringForKey:key value:key table:@"SaveSync"];
}
static NSError *syncError(NSString *message) {
    return [NSError errorWithDomain:@"nxnative.save-sync" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSString *sha(NSData *data) {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *s = [NSMutableString new]; for (unsigned i = 0; i < sizeof hash; i++) [s appendFormat:@"%02x", hash[i]]; return s;
}
static NSString *actorID(NSString *salt,NSString *host) {
    NSData *data=[[NSString stringWithFormat:@"%@|%@",salt,host]dataUsingEncoding:NSUTF8StringEncoding];unsigned char hash[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,hash);
    return [[NSUUID alloc]initWithUUIDBytes:hash].UUIDString;
}
static NSData *json(id value) { return [NSJSONSerialization isValidJSONObject:value] ? [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil] : nil; }
static BOOL safePath(NSString *path) {
    if (![path isKindOfClass:NSString.class] || !path.length || path.length > 1000 || path.isAbsolutePath || [path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return NO;
    for (NSString *p in [path componentsSeparatedByString:@"/"]) if (!p.length || [p isEqual:@"."] || [p isEqual:@".."] || [p containsString:@":"]) return NO;
    return YES;
}
static BOOL validClock(id clock) {
    if (![clock isKindOfClass:NSDictionary.class] || [clock count] > 64) return NO;
    for (id key in clock) {
        id n = clock[key];
        if (![key isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:key] || ![n isKindOfClass:NSNumber.class] || CFNumberIsFloatType((__bridge CFNumberRef)n) || [n longLongValue] <= 0) return NO;
    }
    return YES;
}
static BOOL dominates(NSDictionary *a, NSDictionary *b) {
    BOOL greater = NO;
    for (NSString *k in b) if ([a[k] unsignedLongLongValue] < [b[k] unsignedLongLongValue]) return NO;
    for (NSString *k in a) if ([a[k] unsignedLongLongValue] > [b[k] unsignedLongLongValue]) greater = YES;
    return greater;
}
static NSDictionary *mergeClocks(NSArray<NSDictionary *> *clocks) {
    NSMutableDictionary *out = [NSMutableDictionary new];
    for (NSDictionary *clock in clocks) for (NSString *k in clock) if ([clock[k] unsignedLongLongValue] > [out[k] unsignedLongLongValue]) out[k] = clock[k];
    return out;
}
static NSString *treeHash(NSDictionary<NSString *,NSData *> *files, NSArray<NSString *> *dirs) {
    NSMutableArray *rows = [NSMutableArray new];
    for (NSString *d in [dirs sortedArrayUsingSelector:@selector(compare:)]) [rows addObject:@[@"d", d]];
    for (NSString *p in [files.allKeys sortedArrayUsingSelector:@selector(compare:)]) [rows addObject:@[@"f", p, @([files[p] length]), sha(files[p])]];
    return sha(json(rows));
}
static NSDictionary *readTree(NSURL *root, NSError **error) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSNumber *link; if (![root getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:error])return nil;
    if(link.boolValue){if(error)*error=syncError(@"The save contains unsupported links or paths.");return nil;}
    char resolved[PATH_MAX];if(!realpath(root.fileSystemRepresentation,resolved)){if(error)*error=syncError(@"The local save folder is unavailable.");return nil;}
    root=[NSURL fileURLWithPath:@(resolved) isDirectory:YES];
    NSString *prefix=[@(resolved) stringByAppendingString:@"/"];
    NSMutableDictionary *files = [NSMutableDictionary new]; NSMutableArray *dirs = [NSMutableArray new]; __block NSError *failure;
    NSDirectoryEnumerator *e = [fm enumeratorAtURL:root includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *url,NSError *err) { (void)url; failure=err; return NO; }];
    NSUInteger bytes = 0;
    for (NSURL *url in e) {
        NSDictionary *r = [url resourceValuesForKeys:@[NSURLIsDirectoryKey,NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLFileSizeKey] error:&failure]; if (!r) break;
        if(![url.path hasPrefix:prefix]){failure=syncError(@"The save contains an unsupported filesystem path.");break;}
        NSString *p = [url.path substringFromIndex:prefix.length];
        if (!safePath(p) || [r[NSURLIsSymbolicLinkKey] boolValue] || files.count+dirs.count >= maxFiles) { failure=syncError(@"The save contains unsupported links or paths."); break; }
        if ([r[NSURLIsDirectoryKey] boolValue]) [dirs addObject:p];
        else if ([r[NSURLIsRegularFileKey] boolValue] && [r[NSURLFileSizeKey] unsignedLongLongValue] <= maxBytes-bytes) {
            NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&failure]; if (!data) break; bytes += data.length; files[p]=data;
        } else { failure=syncError(@"The save exceeds the sync size limit or contains unsupported files."); break; }
    }
    if (failure) { if(error)*error=failure; return nil; }
    return @{@"files":files,@"dirs":dirs,@"hash":treeHash(files,dirs)};
}
static BOOL validateHeader(NSDictionary *r, NSString *title, NSString *version) {
    if (![r isKindOfClass:NSDictionary.class] || ![r[@"format"] isEqual:@1] || ![r[@"title"] isEqual:title] || ![r[@"version"] isEqual:version] || !validClock(r[@"clock"])) return NO;
    for (NSString *k in @[@"id",@"device"]) if (![r[k] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:r[k]]) return NO;
    if (![r[@"label"] isKindOfClass:NSString.class] || ![r[@"date"] isKindOfClass:NSString.class] || ![r[@"hash"] isKindOfClass:NSString.class]) return NO;
    NSMutableDictionary *meta=[r mutableCopy]; [meta removeObjectForKey:@"files"]; [meta removeObjectForKey:@"dirs"]; [meta removeObjectForKey:@"recordHash"];
    NSData *encoded=json(meta);return encoded && [sha(encoded) isEqual:r[@"recordHash"]];
}
static BOOL validateRecord(NSDictionary *r, NSString *title, NSString *version) {
    if(!validateHeader(r,title,version))return NO;
    NSDictionary *files=r[@"files"]; NSArray *dirs=r[@"dirs"];
    if (![files isKindOfClass:NSDictionary.class] || ![dirs isKindOfClass:NSArray.class] || !files.count || files.count+dirs.count > maxFiles) return NO;
    NSMutableSet *seen=[NSMutableSet new]; NSUInteger bytes=0;
    for (id p in dirs) { if (!safePath(p) || [seen containsObject:p]) return NO; [seen addObject:p]; }
    for (id p in files) {
        id data=files[p]; if (!safePath(p) || [seen containsObject:p] || ![data isKindOfClass:NSData.class] || [data length] > maxBytes-bytes) return NO;
        bytes += [data length]; [seen addObject:p];
    }
    for (NSString *p in seen) { NSString *parent=p.stringByDeletingLastPathComponent; while(parent.length) { if (![dirs containsObject:parent]) return NO; parent=parent.stringByDeletingLastPathComponent; } }
    if (![treeHash(files,dirs) isEqual:r[@"hash"]]) return NO;
    return YES;
}

@interface DMSaveSync ()
@property NSURL *local, *cache, *folder;
@property NSString *title, *version, *device, *message, *bookmarkKey;
@property NSDictionary *state;
@property(atomic,copy) NSDictionary *activity;
@property dispatch_queue_t worker;
@property NSFileCoordinator *coordinator;
@property BOOL active, started, accessing, processing;
@property NSURL *pending;
@end
@implementation DMSaveSync
@synthesize message=_message;
+ (instancetype)shared {
    static DMSaveSync *instance; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = getenv("DM_SAVE") ? @(getenv("DM_SAVE")) : @"";
        NSString *title=[NSString stringWithFormat:@"%016llX",(unsigned long long)DM_GAME_PROGRAM_ID];
        NSUserDefaults *d=NSUserDefaults.standardUserDefaults; NSString *key=[@"save-sync-device-" stringByAppendingString:title];
        NSString *salt=[d stringForKey:key]; if (!salt) { salt=NSUUID.UUID.UUIDString; [d setObject:salt forKey:key]; }
        // Restoring preferences onto a second physical device must not clone a
        // vector-clock actor, which could mistake concurrent progress for history.
        NSString *host;
        #if TARGET_OS_IPHONE
        host=UIDevice.currentDevice.identifierForVendor.UUIDString ?: NSUUID.UUID.UUIDString;
        #else
        host=CFBridgingRelease(CFPreferencesCopyValue(CFSTR("host-id"),CFSTR("org.nxnative.save-sync"),kCFPreferencesCurrentUser,kCFPreferencesCurrentHost));
        if(!host){host=NSUUID.UUID.UUIDString;CFPreferencesSetValue(CFSTR("host-id"),(__bridge CFStringRef)host,CFSTR("org.nxnative.save-sync"),kCFPreferencesCurrentUser,kCFPreferencesCurrentHost);CFPreferencesSynchronize(CFSTR("org.nxnative.save-sync"),kCFPreferencesCurrentUser,kCFPreferencesCurrentHost);}
        salt=[salt stringByAppendingString:sha([path dataUsingEncoding:NSUTF8StringEncoding])];
        #endif
        NSString *device=actorID(salt,host);
        instance=[[self alloc] initWithLocalURL:[NSURL fileURLWithPath:path isDirectory:YES] title:title version:[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown" device:device];
        dm_fs_save_observer=dm_save_sync_committed;
        NSData *bookmark=[d dataForKey:instance.bookmarkKey];
        if (bookmark) {
            BOOL stale=NO; NSError *error;
            NSURLBookmarkResolutionOptions options=0;
            #if !TARGET_OS_IPHONE
            options=NSURLBookmarkResolutionWithSecurityScope;
            #endif
            NSURL *url=[NSURL URLByResolvingBookmarkData:bookmark options:options relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
            if (url) { instance.folder=url; instance.accessing=[url startAccessingSecurityScopedResource]; instance.message=@"Cloud folder connected."; }
            else instance.message=@"Choose the cloud folder again to restore access.";
        }
    }); return instance;
}
- (instancetype)initWithLocalURL:(NSURL *)local title:(NSString *)title version:(NSString *)version device:(NSString *)device {
    if ((self=[super init])) {
        _local=local.URLByStandardizingPath; _cache=[NSURL fileURLWithPath:[local.path stringByAppendingString:@".sync"] isDirectory:YES];
        _title=[title copy]; _version=[version copy]; _device=[device copy]; _bookmarkKey=[@"save-sync-folder-" stringByAppendingString:title];
        _worker=dispatch_queue_create("dm.save-sync",DISPATCH_QUEUE_SERIAL); _message=@"Cloud sync is not configured.";
        _state=[NSDictionary dictionaryWithContentsOfURL:[_cache URLByAppendingPathComponent:@"state.plist"]] ?: @{};
        _activity=[NSDictionary dictionaryWithContentsOfURL:[_cache URLByAppendingPathComponent:@"activity.plist"]] ?: @{};
        if(![_activity isKindOfClass:NSDictionary.class])_activity=@{};
        if(!validClock(_state[@"clock"]) || ![_state[@"hash"] isKindOfClass:NSString.class])_state=@{};
    } return self;
}
- (void)dealloc { if (_accessing) [_folder stopAccessingSecurityScopedResource]; }
- (NSDictionary *)status {
    NSURL *folder=self.folder;return @{@"configured":@(folder!=nil),@"needsAccess":@(folder==nil && [NSUserDefaults.standardUserDefaults dataForKey:self.bookmarkKey]!=nil),@"active":@(self.active),@"playing":@(self.started),@"folder":folder.lastPathComponent ?: @"",@"message":self.message ?: @""};
}
- (void)setMessage:(NSString *)message { @synchronized(self) { _message=[message copy]; } fprintf(stderr,"save sync: %s\n",message.UTF8String); }
- (NSString *)message { @synchronized(self) { return _message; } }
- (BOOL)makeCache:(NSError **)error {
    if(![NSFileManager.defaultManager createDirectoryAtURL:self.cache withIntermediateDirectories:YES attributes:nil error:error])return NO;
    [self.cache setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];return YES;
}
- (void)noteActivity:(NSDictionary *)fields {
    NSMutableDictionary *activity=[self.activity mutableCopy];[activity addEntriesFromDictionary:fields];self.activity=activity;
    if([self makeCache:nil])[activity writeToURL:[self.cache URLByAppendingPathComponent:@"activity.plist"] atomically:YES];
}
- (BOOL)selectFolder:(NSURL *)folder error:(NSError **)error {
    if (self.started) { if(error)*error=syncError(@"Change cloud settings before starting the game."); return NO; }
    NSURLBookmarkCreationOptions options=0;
    #if !TARGET_OS_IPHONE
    options=NSURLBookmarkCreationWithSecurityScope;
    #endif
    BOOL access=[folder startAccessingSecurityScopedResource];
    char canonical[PATH_MAX],localPath[PATH_MAX];
    NSString *base=realpath(folder.fileSystemRepresentation,canonical)?@(canonical):folder.path;
    NSString *local=realpath(self.local.fileSystemRepresentation,localPath)?@(localPath):self.local.path;
    NSString *root=[base stringByAppendingPathComponent:[@"nxnative-" stringByAppendingString:self.title]];
    for(NSString *protected in @[local,[local stringByAppendingString:@".sync"]]){
        if([root isEqual:protected] || [root hasPrefix:[protected stringByAppendingString:@"/"]] || [protected hasPrefix:[root stringByAppendingString:@"/"]]){
            if(access)[folder stopAccessingSecurityScopedResource];if(error)*error=syncError(@"Choose a sync folder outside the local save and backup folders.");return NO;
        }
    }
    NSData *bookmark=[folder bookmarkDataWithOptions:options includingResourceValuesForKeys:nil relativeToURL:nil error:error];
    if (!bookmark) { if(access)[folder stopAccessingSecurityScopedResource]; return NO; }
    if(self.accessing)[self.folder stopAccessingSecurityScopedResource];
    BOOL changed=![self.folder.path isEqual:folder.path]; self.folder=folder; self.accessing=access;
    [NSUserDefaults.standardUserDefaults setObject:bookmark forKey:self.bookmarkKey];
    if (changed) { self.state=@{}; [NSFileManager.defaultManager removeItemAtURL:[self.cache URLByAppendingPathComponent:@"state.plist"] error:nil]; }
    self.message=@"Cloud folder connected."; return YES;
}
- (void)disconnect {
    if(self.started)return;
    if(self.accessing)[self.folder stopAccessingSecurityScopedResource]; self.accessing=NO; self.folder=nil;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:self.bookmarkKey]; self.message=@"Cloud sync is not configured.";
}
- (void)cancel { [self.coordinator cancel]; }
- (NSURL *)cloudRoot { return [self.folder URLByAppendingPathComponent:[@"nxnative-" stringByAppendingString:self.title] isDirectory:YES]; }
- (NSArray *)records:(NSError **)error {
    if(!self.folder)return @[];
    NSFileManager *fm=NSFileManager.defaultManager; NSFileCoordinator *c=[[NSFileCoordinator alloc] initWithFilePresenter:nil]; self.coordinator=c;
    __block NSMutableArray *records=[NSMutableArray new]; __block NSError *inner;
    [c coordinateReadingItemAtURL:self.folder options:0 error:error byAccessor:^(NSURL *url) {
        NSURL *root=[url URLByAppendingPathComponent:[@"nxnative-" stringByAppendingString:self.title] isDirectory:YES];
        if(![fm fileExistsAtPath:root.path])return;
        NSNumber *link;[root getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];if(link.boolValue){inner=syncError(@"The save contains unsupported links or paths.");return;}
        NSArray *urls=[fm contentsOfDirectoryAtURL:root includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLFileSizeKey,NSURLUbiquitousItemDownloadingStatusKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:&inner];
        for (NSURL *file in urls) {
            if(![file.pathExtension isEqual:@"nxmeta"])continue;
            NSDictionary *v=[file resourceValuesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLFileSizeKey,NSURLUbiquitousItemDownloadingStatusKey] error:&inner]; if(!v)break;
            NSString *download=v[NSURLUbiquitousItemDownloadingStatusKey];
            if([download isKindOfClass:NSString.class] && ![download isEqual:NSURLUbiquitousItemDownloadingStatusCurrent]) { [fm startDownloadingUbiquitousItemAtURL:file error:nil]; inner=syncError(@"Cloud saves are downloading. Wait for iCloud Drive and try again."); break; }
            if(![v[NSURLIsRegularFileKey] boolValue] || [v[NSURLIsSymbolicLinkKey] boolValue] || [v[NSURLFileSizeKey] unsignedLongLongValue]>(64u<<10)) { inner=syncError(@"A cloud checkpoint is invalid. No save was replaced."); break; }
            NSData *data=[NSData dataWithContentsOfURL:file options:0 error:&inner]; if(!data)break;
            NSDictionary *r=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:&inner];
            if(!validateHeader(r,self.title,self.version) || ![file.lastPathComponent.stringByDeletingPathExtension isEqual:r[@"id"]]) { inner=syncError(@"A cloud checkpoint is incomplete, damaged, or from a different game version."); break; }
            [records addObject:r];
        }
    }]; self.coordinator=nil;
    if(inner) { if(error)*error=inner; return nil; } if(error && *error)return nil; return records;
}
- (NSDictionary *)loadRecord:(NSDictionary *)header error:(NSError **)error {
    NSURL *url=[[self cloudRoot] URLByAppendingPathComponent:[header[@"id"] stringByAppendingPathExtension:@"nxsave"]];
    NSFileCoordinator *c=[[NSFileCoordinator alloc]initWithFilePresenter:nil];self.coordinator=c;__block NSError *inner;__block NSDictionary *record;
    [c coordinateReadingItemAtURL:url options:0 error:error byAccessor:^(NSURL *file){
        NSDictionary *v=[file resourceValuesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLFileSizeKey,NSURLUbiquitousItemDownloadingStatusKey] error:&inner];if(!v)return;
        NSString *download=v[NSURLUbiquitousItemDownloadingStatusKey];
        if([download isKindOfClass:NSString.class] && ![download isEqual:NSURLUbiquitousItemDownloadingStatusCurrent]){[NSFileManager.defaultManager startDownloadingUbiquitousItemAtURL:file error:nil];inner=syncError(@"Cloud saves are downloading. Wait for iCloud Drive and try again.");return;}
        if(![v[NSURLIsRegularFileKey]boolValue] || [v[NSURLIsSymbolicLinkKey]boolValue] || [v[NSURLFileSizeKey]unsignedLongLongValue]>maxBytes){inner=syncError(@"A cloud checkpoint is invalid. No save was replaced.");return;}
        NSData *data=[NSData dataWithContentsOfURL:file options:0 error:&inner];if(!data)return;
        record=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:&inner];
        if(!validateRecord(record,self.title,self.version) || ![record[@"recordHash"]isEqual:header[@"recordHash"]]){record=nil;inner=syncError(@"A cloud checkpoint is incomplete, damaged, or from a different game version.");}
    }];self.coordinator=nil;if(inner){if(error)*error=inner;return nil;}return record;
}
- (NSDictionary *)plan:(NSError **)error {
    // A newly installed device has never mounted its local save. Create the
    // empty destination before inspecting it so its first launch can pull cloud.
    if(![NSFileManager.defaultManager createDirectoryAtURL:self.local withIntermediateDirectories:YES attributes:nil error:error])return nil;
    NSDictionary *tree=readTree(self.local,error); if(!tree)return nil;
    NSArray *remote=[self records:error]; if(!remote)return nil;
    NSMutableArray *heads=[NSMutableArray new];
    for(NSDictionary *r in remote) { BOOL old=NO; for(NSDictionary *q in remote) if(dominates(q[@"clock"],r[@"clock"])) {old=YES;break;} if(!old)[heads addObject:r]; }
    NSMutableDictionary *clock=[(self.state[@"clock"] ?: @{}) mutableCopy];
    BOOL changed=![tree[@"hash"] isEqual:self.state[@"hash"]] && [tree[@"files"] count];
    if(changed)clock[self.device]=@([clock[self.device] unsignedLongLongValue]+1);
    NSMutableArray *choices=[NSMutableArray new],*clocks=[NSMutableArray arrayWithObject:clock];
    if([tree[@"files"] count]) [choices addObject:@{@"id":@"local",@"label":@"This device",@"hash":tree[@"hash"],@"clock":clock,@"date":@""}];
    for(NSDictionary *r in heads) { [clocks addObject:r[@"clock"]]; BOOL old=dominates(clock,r[@"clock"]); if(!old)[choices addObject:r]; }
    // A remote head can supersede an unchanged local save. Never discard a local
    // uncommitted branch solely because another device has a later timestamp.
    if(!changed)for(NSDictionary *r in heads)if(dominates(r[@"clock"],clock)){if(choices.count && [choices[0][@"id"] isEqual:@"local"])[choices removeObjectAtIndex:0];break;}
    NSMutableSet *hashes=[NSMutableSet new];for(NSDictionary *r in choices)[hashes addObject:r[@"hash"]];
    NSMutableArray *ids=[NSMutableArray new];for(NSDictionary *r in heads)[ids addObject:[NSString stringWithFormat:@"%@:%@",r[@"id"],r[@"recordHash"]]];[ids sortUsingSelector:@selector(compare:)];
    NSString *token=sha(json(@[tree[@"hash"],ids,clock]));
    NSMutableArray *publicChoices=[NSMutableArray new];NSMutableSet *listed=[NSMutableSet new];
    for(NSDictionary *r in choices)if(![listed containsObject:r[@"hash"]]){[publicChoices addObject:@{@"id":r[@"id"],@"label":r[@"label"],@"date":r[@"date"],@"hash":r[@"hash"]}];[listed addObject:r[@"hash"]];}
    return @{@"tree":tree,@"heads":heads,@"choices":publicChoices,@"conflict":@(hashes.count>1),@"clock":mergeClocks(clocks),@"localClock":clock,@"token":token};
}
- (NSDictionary *)inspect:(NSError **)error {
    if(self.started){if(error)*error=syncError(@"Cloud saves can only be loaded before the game starts.");return nil;}
    __block NSDictionary *p; __block NSError *e; dispatch_sync(self.worker,^{p=[self plan:&e];}); if(error)*error=e; return p;
}
- (BOOL)saveState:(NSDictionary *)state error:(NSError **)error {
    if(![self makeCache:error])return NO;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if(!data || ![data writeToURL:[self.cache URLByAppendingPathComponent:@"state.plist"] options:NSDataWritingAtomic error:error])return NO;
    self.state=state; return YES;
}
- (NSDictionary *)recordForTree:(NSDictionary *)tree clock:(NSDictionary *)clock {
    NSString *label=@"Mac";
    #if TARGET_OS_IPHONE
    label=UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad ? @"iPad" : @"iPhone";
    #endif
    NSMutableDictionary *r=[@{@"format":@1,@"title":self.title,@"version":self.version,@"id":NSUUID.UUID.UUIDString,@"device":self.device,@"label":label,@"date":[NSISO8601DateFormatter.new stringFromDate:NSDate.date],@"clock":clock,@"hash":tree[@"hash"]} mutableCopy];
    r[@"recordHash"]=sha(json(r)); r[@"files"]=tree[@"files"];r[@"dirs"]=tree[@"dirs"];return r;
}
- (BOOL)publish:(NSDictionary *)record error:(NSError **)error {
    if(![self makeCache:error])return NO;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:error]; if(!data)return NO;
    if(data.length>maxBytes){if(error)*error=syncError(@"The save exceeds the sync size limit.");return NO;}
    NSURL *outbox=[self.cache URLByAppendingPathComponent:@"outbox.nxsave"];
    if(![data writeToURL:outbox options:NSDataWritingAtomic error:error])return NO;
    if(![self saveState:@{@"clock":record[@"clock"],@"hash":record[@"hash"]} error:error])return NO;
    NSFileCoordinator *c=[[NSFileCoordinator alloc] initWithFilePresenter:nil];self.coordinator=c;__block NSError *inner;
    [c coordinateWritingItemAtURL:self.folder options:0 error:error byAccessor:^(NSURL *folder) {
        NSURL *root=[folder URLByAppendingPathComponent:[@"nxnative-" stringByAppendingString:self.title] isDirectory:YES];
        NSFileManager *fm=NSFileManager.defaultManager;
        NSNumber *link;[root getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];if(link.boolValue){inner=syncError(@"The save contains unsupported links or paths.");return;}
        if(![fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&inner])return;
        NSURL *dst=[root URLByAppendingPathComponent:[record[@"id"] stringByAppendingPathExtension:@"nxsave"]];
        if(![data writeToURL:dst options:NSDataWritingAtomic error:&inner])return;
        // The small discovery header is published after the complete checkpoint.
        // Other devices download only the chosen payload, not every historical save.
        NSMutableDictionary *header=[record mutableCopy];[header removeObjectForKey:@"files"];[header removeObjectForKey:@"dirs"];
        NSData *metadata=[NSPropertyListSerialization dataWithPropertyList:header format:NSPropertyListBinaryFormat_v1_0 options:0 error:&inner];
        if(!metadata || ![metadata writeToURL:[dst.URLByDeletingPathExtension URLByAppendingPathExtension:@"nxmeta"] options:NSDataWritingAtomic error:&inner])return;
        // Keep three checkpoints from this device. Never prune another device's
        // branch, an incomplete download, or a non-dominated concurrent branch.
        NSMutableArray *older=[NSMutableArray new];
        for(NSURL *file in [fm contentsOfDirectoryAtURL:root includingPropertiesForKeys:@[NSURLUbiquitousItemDownloadingStatusKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil]) {
            if(![file.pathExtension isEqual:@"nxmeta"] || [file.lastPathComponent.stringByDeletingPathExtension isEqual:record[@"id"]])continue;
            NSString *download;[file getResourceValue:&download forKey:NSURLUbiquitousItemDownloadingStatusKey error:nil];
            if([download isKindOfClass:NSString.class] && ![download isEqual:NSURLUbiquitousItemDownloadingStatusCurrent])continue;
            NSDictionary *old=[NSDictionary dictionaryWithContentsOfURL:file];
            if(validateHeader(old,self.title,self.version) && [old[@"device"] isEqual:self.device] && dominates(record[@"clock"],old[@"clock"]))[older addObject:@{@"url":file,@"counter":old[@"clock"][self.device]}];
        }
        [older sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"counter"] compare:a[@"counter"]];}];
        for(NSUInteger i=2;i<older.count;i++){NSURL *meta=older[i][@"url"];[fm removeItemAtURL:[meta.URLByDeletingPathExtension URLByAppendingPathExtension:@"nxsave"] error:nil];[fm removeItemAtURL:meta error:nil];}
    }];self.coordinator=nil;
    if(inner){if(error)*error=inner;return NO;}if(error&&*error)return NO;
    [NSFileManager.defaultManager removeItemAtURL:outbox error:nil];
    [self noteActivity:@{@"publishedAt":record[@"date"],@"publishedId":record[@"id"],@"publishedFolder":sha([self.folder.absoluteString dataUsingEncoding:NSUTF8StringEncoding])}];
    self.message=@"Checkpoint saved to the cloud folder. Wait for iCloud Drive before switching devices.";return YES;
}
- (BOOL)install:(NSDictionary *)tree error:(NSError **)error {
    NSFileManager *fm=NSFileManager.defaultManager; NSURL *stage=[NSURL fileURLWithPath:[self.local.path stringByAppendingFormat:@".import-%@",NSUUID.UUID.UUIDString] isDirectory:YES];
    if(![fm createDirectoryAtURL:stage withIntermediateDirectories:NO attributes:nil error:error])return NO;
    BOOL ok=NO;
    @try {
        for(NSString *d in tree[@"dirs"])if(![fm createDirectoryAtURL:[stage URLByAppendingPathComponent:d] withIntermediateDirectories:YES attributes:nil error:error])return NO;
        for(NSString *p in tree[@"files"])if(![tree[@"files"][p] writeToURL:[stage URLByAppendingPathComponent:p] options:0 error:error])return NO;
        NSDictionary *actual=readTree(stage,error);if(!actual || ![actual[@"hash"]isEqual:tree[@"hash"]]){if(error && !*error)*error=syncError(@"The cloud save could not be restored exactly. The local save is unchanged.");return NO;}
        NSURL *backups=[self.cache URLByAppendingPathComponent:@"backups" isDirectory:YES];if(![fm createDirectoryAtURL:backups withIntermediateDirectories:YES attributes:nil error:error])return NO;
        NSURL *backup=[backups URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        if(![fm copyItemAtURL:self.local toURL:backup error:error])return NO;
        [fm setAttributes:@{NSFileModificationDate:NSDate.date} ofItemAtPath:backup.path error:nil];
        if(renamex_np(stage.fileSystemRepresentation,self.local.fileSystemRepresentation,RENAME_SWAP)) {if(error)*error=syncError(@"The local save could not be replaced atomically. Your save is unchanged.");return NO;}
        ok=YES;
        NSMutableArray *history=[NSMutableArray new];
        for(NSURL *url in [fm contentsOfDirectoryAtURL:backups includingPropertiesForKeys:@[NSURLContentModificationDateKey,NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey] options:0 error:nil]) {
            NSDictionary *v=[url resourceValuesForKeys:@[NSURLContentModificationDateKey,NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey] error:nil];
            if([[NSUUID alloc]initWithUUIDString:url.lastPathComponent] && [v[NSURLIsDirectoryKey]boolValue] && ![v[NSURLIsSymbolicLinkKey]boolValue])[history addObject:@{@"url":url,@"date":v[NSURLContentModificationDateKey]?:NSDate.distantPast}];
        }
        [history sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"date"]compare:a[@"date"]];}];
        for(NSUInteger i=10;i<history.count;i++)[fm removeItemAtURL:history[i][@"url"] error:nil];
    } @finally {[fm removeItemAtURL:stage error:nil];} return ok;
}
- (BOOL)prepareChoice:(NSString *)choice token:(NSString *)token error:(NSError **)error {
    if(self.started){if(error)*error=syncError(@"Cloud saves can only be loaded before the game starts.");return NO;}
    __block BOOL ok=NO;__block NSError *e;
    dispatch_sync(self.worker,^{
        NSDictionary *p=[self plan:&e];if(!p)return;
        if(token.length && ![token isEqual:p[@"token"]]){e=syncError(@"The local or cloud save changed. Refresh before choosing.");return;}
        if([p[@"conflict"] boolValue] && !choice.length){e=syncError(@"Different devices have different progress. Choose which complete save to use.");return;}
        NSDictionary *tree=p[@"tree"],*selected=nil;
        if(!choice.length) {for(NSDictionary *r in p[@"heads"])if(!dominates(p[@"localClock"],r[@"clock"])){selected=r;break;}}
        else if(![choice isEqual:@"local"]) {for(NSDictionary *r in p[@"heads"])if([r[@"id"] isEqual:choice])selected=r;if(!selected){e=syncError(@"The selected checkpoint is no longer available.");return;}}
        if(selected && ![selected[@"hash"] isEqual:tree[@"hash"]]){NSDictionary *full=[self loadRecord:selected error:&e];if(!full || ![self install:full error:&e])return;tree=full;}
        NSMutableDictionary *clock=[p[@"clock"] mutableCopy];
        if(![tree[@"files"] count]){ok=YES;self.message=@"No cloud save yet. The next game save will create one.";return;}
        // A resolution acknowledges all known branches. Normal pulls do not invent
        // new progress; a changed local save or explicit choice creates a checkpoint.
        NSURL *outbox=[self.cache URLByAppendingPathComponent:@"outbox.nxsave"];
        BOOL needsPublish=choice.length || ![self.state[@"hash"] isEqual:tree[@"hash"]] || [NSFileManager.defaultManager fileExistsAtPath:outbox.path];
        if(selected && !choice.length)needsPublish=NO;
        if(needsPublish){
            NSDictionary *pending=[NSDictionary dictionaryWithContentsOfURL:outbox];
            if(!choice.length && validateRecord(pending,self.title,self.version) && [pending[@"hash"]isEqual:tree[@"hash"]] && [pending[@"clock"]isEqual:clock])ok=[self publish:pending error:&e];
            else{clock[self.device]=@([clock[self.device] unsignedLongLongValue]+1);ok=[self publish:[self recordForTree:tree clock:clock] error:&e];}
        }
        else {ok=[self saveState:@{@"clock":clock,@"hash":tree[@"hash"]} error:&e];if(ok && selected)[NSFileManager.defaultManager removeItemAtURL:outbox error:nil];self.message=@"Cloud save ready.";}
    });if(error)*error=e;return ok;
}
- (void)beginSession { self.started=YES; self.active=self.folder!=nil; }
- (void)beginOfflineSession { self.started=YES; self.active=NO; }
- (void)captureCommit:(NSString *)path {
    // Foundation and the host can spell the same save through different aliases
    // (/var versus /private/var, for example). Match the committed directory's
    // identity so a successful game save cannot silently skip its checkpoint.
    struct stat committed,local;
    if(stat(path.fileSystemRepresentation,&committed) || stat(self.local.fileSystemRepresentation,&local) || committed.st_dev!=local.st_dev || committed.st_ino!=local.st_ino)return;
    NSString *date=[NSISO8601DateFormatter.new stringFromDate:NSDate.date];
    dispatch_async(self.worker,^{[self noteActivity:@{@"localSavedAt":date}];});
    if(!self.active)return;
    NSError *error;if(![self makeCache:&error]){self.message=error.localizedDescription;return;}
    NSURL *stage=[self.cache URLByAppendingPathComponent:[@"capture-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    if(clonefile(path.fileSystemRepresentation,stage.fileSystemRepresentation,0)){self.message=@"Local save succeeded, but its cloud checkpoint could not be captured.";return;}
    @synchronized(self){if(self.pending)[NSFileManager.defaultManager removeItemAtURL:self.pending error:nil];self.pending=stage;if(self.processing)return;self.processing=YES;}
    dispatch_async(self.worker,^{@autoreleasepool {
        for(;;){NSURL *snapshot;@synchronized(self){snapshot=self.pending;self.pending=nil;if(!snapshot){self.processing=NO;break;}}
            NSError *e;NSDictionary *tree=readTree(snapshot,&e);
            if(tree && [tree[@"files"] count] && ![tree[@"hash"] isEqual:self.state[@"hash"]]){
                NSMutableDictionary *clock=[(self.state[@"clock"]?:@{}) mutableCopy];clock[self.device]=@([clock[self.device] unsignedLongLongValue]+1);
                if(![self publish:[self recordForTree:tree clock:clock] error:&e])self.message=@"Local save succeeded. Cloud upload is pending; open cloud saves before switching devices.";
            }else if(e)self.message=e.localizedDescription;
            [NSFileManager.defaultManager removeItemAtURL:snapshot error:nil];
        }
    }});
}
- (void)flush { dispatch_sync(self.worker,^{}); }
- (NSURL *)checkpointRoot { return [self.cache URLByAppendingPathComponent:@"checkpoints" isDirectory:YES]; }
- (NSString *)providerUploadState {
    if(!self.folder)return @"Not connected";
    NSDictionary *a=self.activity;NSString *identifier=a[@"publishedId"];
    if(![identifier isKindOfClass:NSString.class] || ![[NSUUID alloc]initWithUUIDString:identifier] || ![a[@"publishedFolder"]isEqual:sha([self.folder.absoluteString dataUsingEncoding:NSUTF8StringEncoding])])return @"No checkpoint published yet";
    NSURL *root=[self cloudRoot];BOOL uploaded=YES;
    for(NSString *ext in @[@"nxsave",@"nxmeta"]) {
        NSURL *url=[root URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:ext]];
        NSDictionary *v=[url resourceValuesForKeys:@[NSURLIsUbiquitousItemKey,NSURLUbiquitousItemIsUploadedKey,NSURLUbiquitousItemIsUploadingKey,NSURLUbiquitousItemUploadingErrorKey] error:nil];
        if(![v[NSURLIsUbiquitousItemKey]isEqual:@YES])return @"Written to folder; provider upload unconfirmed";
        if([v[NSURLUbiquitousItemUploadingErrorKey]isKindOfClass:NSError.class])return @"iCloud reports an upload error";
        if([v[NSURLUbiquitousItemIsUploadingKey]isEqual:@YES])return @"iCloud is uploading";
        uploaded &= [v[NSURLUbiquitousItemIsUploadedKey]isEqual:@YES];
    }
    return uploaded ? @"iCloud reports uploaded; other devices have not confirmed reading" : @"Waiting for iCloud upload confirmation";
}
- (NSArray *)checkpointRows:(NSString *)localHash {
    NSFileManager *fm=NSFileManager.defaultManager;NSMutableArray *rows=[NSMutableArray new];
    for(NSURL *url in [fm contentsOfDirectoryAtURL:self.checkpointRoot includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey] options:0 error:nil]) {
        if(![url.pathExtension isEqual:@"nxmeta"] || ![[NSUUID alloc]initWithUUIDString:url.lastPathComponent.stringByDeletingPathExtension])continue;
        @autoreleasepool {
            NSDictionary *v=[url resourceValuesForKeys:@[NSURLIsSymbolicLinkKey,NSURLFileSizeKey] error:nil];if([v[NSURLIsSymbolicLinkKey]boolValue] || [v[NSURLFileSizeKey]unsignedLongLongValue]>1024*1024)continue;
            NSDictionary *record=[NSDictionary dictionaryWithContentsOfURL:url];if(!validateHeader(record,self.title,self.version) || ![record[@"id"]isEqual:url.lastPathComponent.stringByDeletingPathExtension])continue;
            NSString *identifier=[@"manual:" stringByAppendingString:record[@"id"]];
            NSString *name=[record[@"note"]isKindOfClass:NSString.class] ? record[@"note"] : @"Named checkpoint";
            [rows addObject:@{@"id":identifier,@"name":name,@"date":record[@"date"],@"kind":@"manual",@"hash":record[@"hash"],@"token":sha(json(@[identifier,localHash,record[@"hash"]]))}];
        }
    }
    NSURL *backups=[self.cache URLByAppendingPathComponent:@"backups" isDirectory:YES];
    for(NSURL *url in [fm contentsOfDirectoryAtURL:backups includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey,NSURLContentModificationDateKey] options:0 error:nil]) {
        if(![[NSUUID alloc]initWithUUIDString:url.lastPathComponent])continue;
        @autoreleasepool {
            NSDictionary *v=[url resourceValuesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey,NSURLContentModificationDateKey] error:nil];if(![v[NSURLIsDirectoryKey]boolValue] || [v[NSURLIsSymbolicLinkKey]boolValue])continue;
            NSDictionary *tree=readTree(url,nil);if(![tree[@"files"]count])continue;
            NSString *identifier=[@"backup:" stringByAppendingString:url.lastPathComponent];
            [rows addObject:@{@"id":identifier,@"name":@"Before save replacement",@"date":[NSISO8601DateFormatter.new stringFromDate:v[NSURLContentModificationDateKey] ?: NSDate.distantPast],@"kind":@"backup",@"hash":tree[@"hash"],@"token":sha(json(@[identifier,localHash,tree[@"hash"]]))}];
        }
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"date"]compare:a[@"date"]];}];return rows;
}
- (NSDictionary *)saveCenter:(NSError **)error {
    __block NSDictionary *result;__block NSError *e;
    dispatch_sync(self.worker,^{@autoreleasepool {
        NSDictionary *tree=[NSFileManager.defaultManager fileExistsAtPath:self.local.path] ? readTree(self.local,&e) : @{@"files":@{},@"hash":@""};if(!tree)return;
        result=@{@"localHash":tree[@"hash"],@"fileCount":@([tree[@"files"]count]),@"history":[self checkpointRows:tree[@"hash"]],@"localSavedAt":self.activity[@"localSavedAt"] ?: @"",@"publishedAt":self.activity[@"publishedAt"] ?: @"",@"uploadState":[self providerUploadState],@"playing":@(self.started)};
    }});if(error)*error=e;return result;
}
- (BOOL)createCheckpoint:(NSString *)name error:(NSError **)error {
    if(self.started){if(error)*error=syncError(@"Checkpoints can only be changed before starting the game.");return NO;}
    __block BOOL ok=NO;__block NSError *e;
    dispatch_sync(self.worker,^{@autoreleasepool {
        NSDictionary *tree=readTree(self.local,&e);if(!tree)return;
        if(![tree[@"files"]count]){e=syncError(@"There is no local save to back up yet.");return;}
        NSUInteger count=0;for(NSDictionary *row in [self checkpointRows:tree[@"hash"]])if([row[@"kind"]isEqual:@"manual"])count++;
        if(count>=20){e=syncError(@"Keep up to 20 named checkpoints. Delete one before creating another.");return;}
        if(![NSFileManager.defaultManager createDirectoryAtURL:self.checkpointRoot withIntermediateDirectories:YES attributes:nil error:&e])return;
        NSMutableDictionary *record=[[self recordForTree:tree clock:@{self.device:@1}]mutableCopy];
        NSString *label=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        record[@"note"]=label.length ? [label substringWithRange:[label rangeOfComposedCharacterSequencesForRange:NSMakeRange(0,MIN(label.length,80))]] : @"Named checkpoint";
        NSMutableDictionary *header=[record mutableCopy];[header removeObjectForKey:@"files"];[header removeObjectForKey:@"dirs"];[header removeObjectForKey:@"recordHash"];record[@"recordHash"]=sha(json(header));
        NSData *data=[NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:&e];
        NSURL *payload=[self.checkpointRoot URLByAppendingPathComponent:[record[@"id"]stringByAppendingPathExtension:@"nxsave"]];
        if(!data || ![data writeToURL:payload options:NSDataWritingAtomic error:&e])return;
        NSMutableDictionary *metadata=[record mutableCopy];[metadata removeObjectForKey:@"files"];[metadata removeObjectForKey:@"dirs"];
        NSData *index=[NSPropertyListSerialization dataWithPropertyList:metadata format:NSPropertyListBinaryFormat_v1_0 options:0 error:&e];
        ok=index && [index writeToURL:[payload.URLByDeletingPathExtension URLByAppendingPathExtension:@"nxmeta"] options:NSDataWritingAtomic error:&e];
        if(!ok)[NSFileManager.defaultManager removeItemAtURL:payload error:nil];
    }});if(error)*error=e;return ok;
}
- (BOOL)restoreCheckpoint:(NSString *)identifier token:(NSString *)token error:(NSError **)error {
    if(self.started){if(error)*error=syncError(@"Checkpoints can only be changed before starting the game.");return NO;}
    __block BOOL ok=NO;__block NSError *e;
    dispatch_sync(self.worker,^{@autoreleasepool {
        NSDictionary *local=readTree(self.local,&e);if(!local)return;
        NSDictionary *selected;for(NSDictionary *row in [self checkpointRows:local[@"hash"]])if([row[@"id"]isEqual:identifier])selected=row;
        if(!selected || ![selected[@"token"]isEqual:token]){e=syncError(@"The local save or checkpoint changed. Refresh before restoring.");return;}
        NSString *uuid=[[identifier componentsSeparatedByString:@":"]lastObject];NSDictionary *tree;
        if([selected[@"kind"]isEqual:@"manual"]){
            NSURL *payload=[self.checkpointRoot URLByAppendingPathComponent:[uuid stringByAppendingPathExtension:@"nxsave"]];
            NSDictionary *attributes=[payload resourceValuesForKeys:@[NSURLIsSymbolicLinkKey,NSURLFileSizeKey] error:&e];
            if(!attributes || [attributes[NSURLIsSymbolicLinkKey]boolValue] || [attributes[NSURLFileSizeKey]unsignedLongLongValue]>maxBytes+8*1024*1024){if(!e)e=syncError(@"The checkpoint failed its integrity check.");return;}
            tree=[NSDictionary dictionaryWithContentsOfURL:payload];if(!validateRecord(tree,self.title,self.version))tree=nil;
        }
        else tree=readTree([[self.cache URLByAppendingPathComponent:@"backups"]URLByAppendingPathComponent:uuid],&e);
        if(!tree || ![tree[@"hash"]isEqual:selected[@"hash"]]){if(!e)e=syncError(@"The checkpoint failed its integrity check.");return;}
        ok=[self install:tree error:&e];if(ok)self.message=@"Local checkpoint restored. Check cloud progress before starting.";
    }});if(error)*error=e;return ok;
}
- (BOOL)deleteCheckpoint:(NSString *)identifier error:(NSError **)error {
    NSString *uuid=[identifier hasPrefix:@"manual:"] ? [identifier substringFromIndex:7] : @"";
    if(self.started || ![[NSUUID alloc]initWithUUIDString:uuid]){if(error)*error=syncError(@"Only named checkpoints can be deleted before starting the game.");return NO;}
    __block BOOL ok;__block NSError *e;dispatch_sync(self.worker,^{
        NSURL *payload=[self.checkpointRoot URLByAppendingPathComponent:[uuid stringByAppendingPathExtension:@"nxsave"]];
        if([NSFileManager.defaultManager fileExistsAtPath:payload.path] && ![NSFileManager.defaultManager removeItemAtURL:payload error:&e])return;
        ok=[NSFileManager.defaultManager removeItemAtURL:[payload.URLByDeletingPathExtension URLByAppendingPathExtension:@"nxmeta"] error:&e];
    });if(error)*error=e;return ok;
}
@end
void dm_save_sync_committed(const char *path) { [[DMSaveSync shared] captureCommit:@(path)]; }
