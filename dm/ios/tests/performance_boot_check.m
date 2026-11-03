// Production iOS startup and recorder, with only Documents and guest loading
// replaced by fixture boundaries. No explicit DM_ROOT is supplied in normal use.
#import <UIKit/UIKit.h>
static NSString *fixtureDocuments;
static NSArray<NSString *> *fixturePaths(NSSearchPathDirectory directory,NSSearchPathDomainMask domain,BOOL expand) {
    (void)directory;(void)domain;(void)expand;return @[fixtureDocuments];
}
#define NSSearchPathForDirectoriesInDomains fixturePaths
#define main fixture_ios_entry
#include "../Sources/main.m"
#undef main
#undef NSSearchPathForDirectoriesInDomains
#include "../../host/performance_apple.m"

static NSString *preloadRoot;
void dm_host_preload_start(int argc,char **argv){(void)argc;(void)argv;const char *p=getenv("DM_ROOT");preloadRoot=p ? @(p):nil;}
int dm_main(int argc,char **argv){(void)argc;(void)argv;return 0;}
UIViewController *front_ios_root(void){return nil;}
void front_ios_focus_event(int ev){(void)ev;}
void front_ios_geometry_changed(void){}
void front_ios_audio_session(void){}
UIInterfaceOrientationMask front_ios_orientation_mask(void){return UIInterfaceOrientationMaskLandscape;}

int main(int argc,char **argv){@autoreleasepool{
    if(argc!=3)return 2;
    NSURL *base=[NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
    fixtureDocuments=[[base URLByAppendingPathComponent:@"Documents" isDirectory:YES]path];
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *romfs=[fixtureDocuments stringByAppendingPathComponent:@"romfs"];
    [fm createDirectoryAtPath:romfs withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createFileAtPath:[romfs stringByAppendingPathComponent:@DM_GAME_ROMFS_MARKER] contents:NSData.data attributes:nil];
    BOOL enabled=strcmp(argv[2],"off")!=0,override=strcmp(argv[2],"override")==0;
    unsetenv("DM_ROOT");unsetenv("DM_ROMFS");unsetenv("DM_SAVE");unsetenv("DM_TEMP");
    NSString *expected=override ? [[base URLByAppendingPathComponent:@"custom" isDirectory:YES]path]:fixtureDocuments;
    if(override)setenv("DM_ROOT",expected.fileSystemRepresentation,1);
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"DmPerformanceRecord":@(enabled)} forName:NSArgumentDomain];
    BOOL booted=boot_env();
    NSURL *folder=[[NSURL fileURLWithPath:expected isDirectory:YES]URLByAppendingPathComponent:@"performance" isDirectory:YES];
    dm_performance_presented(1);
    NSUInteger immediateFiles=[fm contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil].count;
    for(int i=1;i<340;i++)dm_performance_presented(1+i/30.0);
    dm_performance_flush();
    NSArray<NSURL *> *files=[fm contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil];
    int windows=0;BOOL validRows=YES;
    for(NSURL *file in files){
        NSString *body=[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil];
        for(NSString *line in [body componentsSeparatedByString:@"\n"]){
            if(!line.length)continue;
            NSDictionary *row=[NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if(!row){validRows=NO;continue;}
            if([row[@"event"]isEqual:@"window"]){windows++;validRows&=fabs([row[@"fps"]doubleValue]-30)<.01 && [row[@"footprint_bytes"]unsignedLongLongValue]>0;}
        }
    }
    BOOL rootReady=[preloadRoot isEqual:expected],browserReady=[NSProcessInfo.processInfo.environment[@"DM_ROOT"]isEqual:expected];
    BOOL saved=enabled ? files.count==1 && windows==1 && validRows:files.count==0;
    BOOL ok=booted && rootReady && browserReady && saved && immediateFiles==(enabled?1:0);
    NSDictionary *result=@{@"status":ok?@"PASS":@"FAIL",@"mode":@(argv[2]),@"booted":@(booted),@"root_ready_before_preload":@(rootReady),@"browser_root_ready":@(browserReady),@"report_files_after_first_frame":@(immediateFiles),@"report_files":@(files.count),@"complete_windows":@(windows),@"valid_rows":@(validRows),@"recording_opt_in":@(enabled)};
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:nil];
    puts([[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding].UTF8String);return ok?0:1;
}}
