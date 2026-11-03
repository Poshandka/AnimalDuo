// Real persistent installation and bundle-replacement IO with owned toy data.
#include "../Sources/ResourceStore.inc"
#include <assert.h>
int main(int argc,const char **argv){@autoreleasepool{
    if(argc!=4)return 2;
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *full=[NSURL fileURLWithPath:@(argv[1]) isDirectory:YES],*thin=[NSURL fileURLWithPath:@(argv[2]) isDirectory:YES],*support=[NSURL fileURLWithPath:@(argv[3]) isDirectory:YES];
    DMResourceStore *store=[[DMResourceStore alloc]initWithBundle:full support:support title:@"01006F8002326000" version:@"3.0.3" chain:@"fixture"];
    assert(![store ready:nil] && [store hasInstaller]);
    NSURL *save=[support URLByAppendingPathComponent:@"save/main.dat"];assert([fm createDirectoryAtURL:save.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]);NSData *island=[@"current island never belongs to the asset set" dataUsingEncoding:NSUTF8StringEncoding];assert([island writeToURL:save atomically:YES]);
    __block BOOL stop=NO;NSError *e=nil;
    BOOL ok=[store installWithProgress:^(uint64_t done,uint64_t total,NSUInteger files,NSUInteger count){(void)total;(void)count;if(done && files)stop=YES;} cancelled:^BOOL{return stop;} error:&e];
    assert(!ok && e.code==2 && ![store ready:nil]);
    e=nil;assert([store installWithProgress:nil cancelled:nil error:&e] && !e && [store ready:nil]);
    assert([fm fileExistsAtPath:[store.directory URLByAppendingPathComponent:@"romfs/Empty"].path]);
    NSDictionary *manifest=[NSDictionary dictionaryWithContentsOfURL:[full URLByAppendingPathComponent:@"dm/resource-files.plist"]];
    for(NSDictionary *row in manifest[@"files"]){NSURL *file=[store.directory URLByAppendingPathComponent:row[@"path"]];assert([resourceFileHash(file,nil,nil)isEqual:row[@"sha256"]]);}
    NSURL *moved=[full URLByAppendingPathExtension:@"old-bundle"];assert([fm moveItemAtURL:full toURL:moved error:nil]);
    DMResourceStore *update=[[DMResourceStore alloc]initWithBundle:thin support:support title:@"01006F8002326000" version:@"3.0.3" chain:@"fixture"];
    assert(![update hasInstaller] && [update ready:nil] && [update installWithProgress:nil cancelled:nil error:nil]);
    assert([update.directory isEqual:store.directory] && [[NSData dataWithContentsOfURL:save]isEqual:island]);
    DMResourceStore *wrongVersion=[[DMResourceStore alloc]initWithBundle:thin support:support title:@"01006F8002326000" version:@"other" chain:@"fixture"];
    e=nil;assert(![wrongVersion ready:&e] && e);
    DMResourceStore *wrongChain=[[DMResourceStore alloc]initWithBundle:thin support:support title:@"01006F8002326000" version:@"3.0.3" chain:@"different"];
    e=nil;assert(![wrongChain ready:&e] && e);
    NSDictionary *critical=store.requirements[@"checks"][0];NSURL *file=[store.directory URLByAppendingPathComponent:critical[@"path"]];NSData *original=[NSData dataWithContentsOfURL:file];NSMutableData *corrupt=[original mutableCopy];if(corrupt.length)((uint8_t *)corrupt.mutableBytes)[0]^=1;
    assert([corrupt writeToURL:file atomically:YES] && ![update ready:nil]);assert([original writeToURL:file atomically:YES] && [update ready:nil]);
    puts("persistent resources: interrupted/resumed SHA256 install, empty directories, complete bundle removal, small update reuse, save preservation, version/chain gate and critical-file corruption PASS");return 0;
}}
