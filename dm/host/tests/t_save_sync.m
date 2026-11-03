// Real checkpoint IO, vector-clock branches, atomic restore and immutable capture.
#import "../save_sync_apple.m"
#include <assert.h>
void (*dm_fs_save_observer)(const char *path);
static NSURL *testRoot;
static NSURL *directory(NSString *name) {
    NSURL *url=[testRoot URLByAppendingPathComponent:name isDirectory:YES];
    assert([NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil]); return url;
}
static void put(NSURL *root,NSString *text) {
    assert([[text dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[root URLByAppendingPathComponent:@"main.dat"] atomically:YES]);
}
static NSString *get(NSURL *root) { return [NSString stringWithContentsOfURL:[root URLByAppendingPathComponent:@"main.dat"] encoding:NSUTF8StringEncoding error:nil]; }
static DMSaveSync *client(NSString *name,NSURL *cloud) {
    DMSaveSync *s=[[DMSaveSync alloc] initWithLocalURL:directory(name) title:@"test" version:@"1" device:NSUUID.UUID.UUIDString];
    s.folder=cloud; return s;
}
static NSDictionary *plan(DMSaveSync *s) { NSError *e;NSDictionary *p=[s inspect:&e];if(e)fprintf(stderr,"plan failed: %s\n",e.localizedDescription.UTF8String);assert(p && !e);return p; }
static void prepare(DMSaveSync *s,NSString *choice) { NSError *e;NSDictionary *p=plan(s);assert([s prepareChoice:choice token:p[@"token"] error:&e] && !e); }
@interface ReadbackFailureSync:DMSaveSync
@property BOOL corruptReadback;
@property NSString *corruptExtension;
@end
@implementation ReadbackFailureSync
- (BOOL)verifyPublishedData:(NSData *)data atURL:(NSURL *)url error:(NSError **)error {
    if(self.corruptReadback && (!self.corruptExtension || [url.pathExtension isEqual:self.corruptExtension]))[NSData.data writeToURL:url atomically:YES];
    return [super verifyPublishedData:data atURL:url error:error];
}
@end
int main(int argc,const char **argv) { @autoreleasepool {
    testRoot=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSURL *cloud=directory(@"cloud"); DMSaveSync *a=client(@"a",cloud),*b=client(@"b",cloud);
    assert([actorID(@"same restored preferences",@"host-a") isEqual:actorID(@"same restored preferences",@"host-a")]);
    assert(![actorID(@"same restored preferences",@"host-a") isEqual:actorID(@"same restored preferences",@"host-b")]);
    if(argc==2){
        [NSFileManager.defaultManager removeItemAtURL:a.local error:nil];
        assert([NSFileManager.defaultManager copyItemAtURL:[NSURL fileURLWithPath:@(argv[1]) isDirectory:YES] toURL:a.local error:nil]);
        prepare(a,@"");prepare(b,@"");assert([readTree(a.local,nil)[@"hash"]isEqual:readTree(b.local,nil)[@"hash"]]);
        [NSFileManager.defaultManager removeItemAtURL:testRoot error:nil];puts("Real save full-tree cloud checkpoint roundtrip PASS");return 0;
    }
    put(a.local,@"one");prepare(a,@"");
    prepare(b,@"");assert([get(b.local) isEqual:@"one"]);
    put(b.local,@"two");prepare(b,@"");prepare(a,@"");assert([get(a.local) isEqual:@"two"]);
    NSArray *backups=[NSFileManager.defaultManager contentsOfDirectoryAtURL:[a.cache URLByAppendingPathComponent:@"backups"] includingPropertiesForKeys:nil options:0 error:nil];assert(backups.count);
    [a beginSession];[b beginSession];put(a.local,@"branch-a");[a captureCommit:a.local.path];[a flush];
    put(b.local,@"branch-b");[b captureCommit:b.local.path];[b flush];
    a.started=NO;b.started=NO; // Simulate closing both guests before deciding which branch to load.
    NSDictionary *conflict=plan(a);assert([conflict[@"conflict"] boolValue]);NSError *e;
    assert(![a prepareChoice:@"" token:conflict[@"token"] error:&e]);assert([get(a.local) isEqual:@"branch-a"]);
    NSString *chosen=nil;for(NSDictionary *r in conflict[@"heads"])if([r[@"device"] isEqual:b.device])chosen=r[@"id"];assert(chosen);
    a.active=NO;prepare(a,chosen);assert([get(a.local) isEqual:@"branch-b"]);assert(![plan(b)[@"conflict"] boolValue]);
    NSDictionary *old=plan(a);put(a.local,@"changed-after-preview");e=nil;
    assert(![a prepareChoice:@"local" token:old[@"token"] error:&e]);assert([get(a.local) isEqual:@"changed-after-preview"]);
    prepare(a,@"local");[a beginSession];put(a.local,@"captured");[a captureCommit:a.local.path];put(a.local,@"later-write");[a flush];
    DMSaveSync *c=client(@"c",cloud);prepare(c,@"");assert([get(c.local) isEqual:@"captured"]);
    put(a.local,@"captured-through-alias");[a captureCommit:[a.local.path stringByAppendingString:@"/."]];[a flush];prepare(c,@"");assert([get(c.local)isEqual:@"captured-through-alias"]);
    for(int i=0;i<6;i++){put(a.local,[NSString stringWithFormat:@"revision-%d",i]);[a captureCommit:a.local.path];[a flush];}
    NSUInteger owned=0;for(NSDictionary *r in [a records:nil])if([r[@"device"] isEqual:a.device])owned++;assert(owned==3);
    // A fresh installation has no local save directory yet, including its parent.
    DMSaveSync *fresh=client(@"new-install/save",cloud);[NSFileManager.defaultManager removeItemAtURL:fresh.local.URLByDeletingLastPathComponent error:nil];
    prepare(fresh,@"");assert([get(fresh.local)isEqual:@"revision-5"]);
    // Invalid checkpoint paths are refused even if the content fingerprint is valid.
    NSDictionary *tree=@{@"files":@{@"../escape":NSData.data},@"dirs":@[],@"hash":treeHash(@{@"../escape":NSData.data},@[])};
    assert(!validateRecord([a recordForTree:tree clock:@{a.device:@1}],@"test",@"1"));
    NSMutableDictionary *invalid=[[a recordForTree:readTree(a.local,nil) clock:@{a.device:@1}]mutableCopy];invalid[@"unsupported"]=NSData.data;
    assert(!validateHeader(invalid,@"test",@"1"));
    // A failed upload must leave an outbox and retry an unchanged local save.
    DMSaveSync *d=client(@"d",cloud);put(d.local,@"offline");NSURL *file=[testRoot URLByAppendingPathComponent:@"not-a-directory"];[NSData.data writeToURL:file atomically:YES];d.folder=file;e=nil;
    assert(![d prepareChoice:@"" token:plan(d)[@"token"] error:&e]);assert([NSFileManager.defaultManager fileExistsAtPath:[d.cache URLByAppendingPathComponent:@"outbox.nxsave"].path]);
    d.folder=directory(@"other-cloud");prepare(d,@"");assert([d records:nil].count==1);assert(![NSFileManager.defaultManager fileExistsAtPath:[d.cache URLByAppendingPathComponent:@"outbox.nxsave"].path]);
    // A valid discovery header must not allow a damaged payload to replace a save.
    NSDictionary *header=[d records:nil].firstObject;NSURL *payload=[[d cloudRoot]URLByAppendingPathComponent:[header[@"id"]stringByAppendingPathExtension:@"nxsave"]];
    [NSData.data writeToURL:payload atomically:YES];DMSaveSync *damaged=client(@"damaged",d.folder);e=nil;
    assert(![damaged prepareChoice:@"" token:plan(damaged)[@"token"] error:&e] && e);assert(!get(damaged.local));
    DMSaveSync *center=client(@"save-center",directory(@"center-cloud"));put(center.local,@"named-original");e=nil;
    assert([center createCheckpoint:@"Before editing" error:&e] && !e);
    NSDictionary *overview=[center saveCenter:&e];assert([overview[@"fileCount"]unsignedIntValue]==1 && [overview[@"history"]count]==1);
    NSDictionary *named=overview[@"history"][0];assert([named[@"name"]isEqual:@"Before editing"]);
    put(center.local,@"new-progress");e=nil;
    assert(![center restoreCheckpoint:named[@"id"] token:named[@"token"] error:&e] && e && [get(center.local)isEqual:@"new-progress"]);
    named=[center saveCenter:nil][@"history"][0];e=nil;
    assert([center restoreCheckpoint:named[@"id"] token:named[@"token"] error:&e] && !e && [get(center.local)isEqual:@"named-original"]);
    assert([[center saveCenter:nil][@"history"]count]==2); // Automatic pre-restore backup is visible too.
    center.started=YES;e=nil;assert(![center createCheckpoint:@"Blocked in game" error:&e] && e);center.started=NO;
    NSDictionary *freshNamed;for(NSDictionary *row in [center saveCenter:nil][@"history"])if([row[@"kind"]isEqual:@"manual"])freshNamed=row;assert(freshNamed);
    NSString *uuid=[freshNamed[@"id"]substringFromIndex:7];NSURL *namedPayload=[center.checkpointRoot URLByAppendingPathComponent:[uuid stringByAppendingPathExtension:@"nxsave"]];
    [NSData.data writeToURL:namedPayload atomically:YES];e=nil;
    assert(![center restoreCheckpoint:freshNamed[@"id"] token:freshNamed[@"token"] error:&e] && e && [get(center.local)isEqual:@"named-original"]);
    e=nil;assert([center deleteCheckpoint:freshNamed[@"id"] error:&e] && !e);
    center.active=NO;[center captureCommit:center.local.path];[center flush];assert([[center saveCenter:nil][@"localSavedAt"]length]>0);
    assert([[a saveCenter:nil][@"uploadState"]isEqual:@"Written to folder; provider upload unconfirmed"]);
    // A local state hash cannot acknowledge deleted or incomplete folder data.
    DMSaveSync *repair=client(@"repair-local",directory(@"repair-cloud"));put(repair.local,@"same complete island");prepare(repair,@"");
    assert([repair records:nil].count==1);assert([NSFileManager.defaultManager removeItemAtURL:repair.cloudRoot error:nil]);
    assert(![[repair saveCenter:nil][@"folderMatchesLocal"]boolValue]);prepare(repair,@"");assert([repair records:nil].count==1);
    NSDictionary *repairHeader=plan(repair)[@"heads"][0];NSURL *repairPayload=[repair.cloudRoot URLByAppendingPathComponent:[repairHeader[@"id"]stringByAppendingPathExtension:@"nxsave"]];
    assert([NSFileManager.defaultManager removeItemAtURL:repairPayload error:nil]);prepare(repair,@"");
    DMSaveSync *receiver=client(@"repaired-receiver",repair.folder);prepare(receiver,@"");assert([get(receiver.local)isEqual:@"same complete island"]);
    assert([[repair saveCenter:nil][@"folderMatchesLocal"]boolValue]);put(repair.local,@"new unsent progress");
    assert(![[repair saveCenter:nil][@"folderMatchesLocal"]boolValue]);assert(![[repair saveCenter:nil][@"uploadState"]isEqual:@"Written to folder; provider upload unconfirmed"]);
    // A provider write followed by bad readback retains the outbox, publishes
    // no discovery header and never claims a verified folder checkpoint.
    ReadbackFailureSync *fault=[[ReadbackFailureSync alloc]initWithLocalURL:directory(@"readback-local") title:@"test" version:@"1" device:NSUUID.UUID.UUIDString];fault.folder=directory(@"readback-cloud");put(fault.local,@"verified body");fault.corruptReadback=YES;e=nil;
    assert(![fault prepareChoice:@"" token:plan(fault)[@"token"] error:&e] && e);assert([fault records:nil].count==0);
    assert([NSFileManager.defaultManager fileExistsAtPath:[fault.cache URLByAppendingPathComponent:@"outbox.nxsave"].path]);assert(!fault.activity[@"publishedAt"]);
    fault.corruptReadback=NO;prepare(fault,@"");assert([fault records:nil].count==1 && [[fault saveCenter:nil][@"folderMatchesLocal"]boolValue]);
    DMSaveSync *verifiedReceiver=client(@"verified-receiver",fault.folder);prepare(verifiedReceiver,@"");assert([get(verifiedReceiver.local)isEqual:@"verified body"]);
    ReadbackFailureSync *badIndex=[[ReadbackFailureSync alloc]initWithLocalURL:directory(@"index-local") title:@"test" version:@"1" device:NSUUID.UUID.UUIDString];badIndex.folder=directory(@"index-cloud");badIndex.corruptReadback=YES;badIndex.corruptExtension=@"nxmeta";put(badIndex.local,@"index verified body");e=nil;
    assert(![badIndex prepareChoice:@"" token:plan(badIndex)[@"token"] error:&e] && e && [badIndex records:nil].count==0);
    assert([NSFileManager.defaultManager fileExistsAtPath:[badIndex.cache URLByAppendingPathComponent:@"outbox.nxsave"].path]);badIndex.corruptReadback=NO;prepare(badIndex,@"");assert([badIndex records:nil].count==1);
    puts("Save sync verification: missing cloud rebuilt, same-hash missing payload repaired, bad readback retained for retry and current-progress status PASS");
    puts("Save center: named full-tree checkpoints, stale restore rejection, pre-restore backup, live-game guard, corrupt payload rejection and offline commit status PASS");
    NSURL *bad=[[d cloudRoot] URLByAppendingPathComponent:@"broken.nxmeta"];[NSData.data writeToURL:bad atomically:YES];e=nil;assert(![d inspect:&e] && e);assert([get(d.local) isEqual:@"offline"]);
    [NSFileManager.defaultManager removeItemAtURL:testRoot error:nil];puts("Save sync: sequential devices, concurrent branches, resolution, stale choice, capture, retention, outbox retry and corrupt paths PASS");
} }
