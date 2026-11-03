// Exercise production startup before installation and after a thin replacement.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <assert.h>
static NSString *fixtureDocuments,*fixtureSupport;
static NSBundle *fixtureBundle;
static NSArray *fixturePaths(NSSearchPathDirectory directory,NSSearchPathDomainMask domain,BOOL expand){
    (void)domain;(void)expand;return @[directory==NSApplicationSupportDirectory?fixtureSupport:fixtureDocuments];
}
static id fixtureMainBundle(id object,SEL selector){(void)object;(void)selector;return fixtureBundle;}
#define NSSearchPathForDirectoriesInDomains fixturePaths
#define main fixture_ios_entry
#include "../Sources/main.m"
#undef main
#undef NSSearchPathForDirectoriesInDomains
static int preloadCount;
static NSString *preloadMetadata;
void dm_host_preload_start(int argc,char **argv){assert(argc==2);preloadCount++;preloadMetadata=@(argv[1]);}
int dm_main(int argc,char **argv){(void)argc;(void)argv;return 0;}
UIViewController *front_ios_root(void){return nil;}
void front_ios_focus_event(int event){(void)event;}
void front_ios_geometry_changed(void){}
void front_ios_audio_session(void){}
UIInterfaceOrientationMask front_ios_orientation_mask(void){return UIInterfaceOrientationMaskAll;}
static void clearPaths(void){for(NSString *key in @[@"DM_ROOT",@"DM_ROMFS",@"DM_SAVE",@"DM_TEMP",@"DM_MSL_DIR",@"DM_FONT_DIR",@"DM_AOC_DIR",@"DM_PSO_BUNDLE",@"DM_NVN_SHMAP"])unsetenv(key.UTF8String);}
int main(int argc,const char **argv){@autoreleasepool{
    if(argc!=4)return 2;
    NSFileManager *fm=NSFileManager.defaultManager;
    fixtureDocuments=[@(argv[3])stringByAppendingPathComponent:@"Documents"];fixtureSupport=[@(argv[3])stringByAppendingPathComponent:@"Library/Application Support"];
    [fm createDirectoryAtPath:fixtureDocuments withIntermediateDirectories:YES attributes:nil error:nil];
    fixtureBundle=[NSBundle bundleWithPath:@(argv[1])];assert(fixtureBundle);
    method_setImplementation(class_getClassMethod(NSBundle.class,@selector(mainBundle)),(IMP)fixtureMainBundle);
    clearPaths();assert(!boot_env() && preloadCount==0 && g_resources);
    NSURL *save=[NSURL fileURLWithPath:[fixtureDocuments stringByAppendingPathComponent:@"save/main.dat"]];NSData *island=[@"current fixture progress" dataUsingEncoding:NSUTF8StringEncoding];assert([island writeToURL:save atomically:YES]);
    assert([g_resources installWithProgress:nil cancelled:nil error:nil]);
    assert(boot_game_paths() && preloadCount==1);
    assert([@(getenv("DM_ROOT"))isEqual:fixtureDocuments]);
    assert([@(getenv("DM_ROMFS"))isEqual:[g_resources.directory URLByAppendingPathComponent:@"romfs"].path]);
    assert([@(getenv("DM_SAVE"))isEqual:save.URLByDeletingLastPathComponent.path]);
    assert([@(getenv("DM_MSL_DIR"))isEqual:[g_resources.directory URLByAppendingPathComponent:@"msl"].path]);
    assert([@(getenv("DM_FONT_DIR"))isEqual:[g_resources.directory URLByAppendingPathComponent:@"dm/font"].path]);
    assert([preloadMetadata isEqual:[@(argv[1])stringByAppendingPathComponent:@"dm"]]);
    assert([fm moveItemAtPath:@(argv[1]) toPath:[@(argv[1])stringByAppendingString:@".removed"] error:nil]);
    fixtureBundle=[NSBundle bundleWithPath:@(argv[2])];assert(fixtureBundle);
    clearPaths();assert(boot_env() && preloadCount==2 && ![g_resources hasInstaller]);
    assert([preloadMetadata isEqual:[@(argv[2])stringByAppendingPathComponent:@"dm"]]);
    assert([[NSData dataWithContentsOfURL:save]isEqual:island]);
    NSDictionary *critical=g_resources.requirements[@"checks"][0];NSURL *file=[g_resources.directory URLByAppendingPathComponent:critical[@"path"]];assert([fm removeItemAtURL:file error:nil]);
    clearPaths();assert(!boot_env() && preloadCount==2);
    puts("production boot: preload deferred, persistent ROMFS/MSL/fonts, unchanged save root, cold thin replacement and damaged-cache gate PASS");return 0;
}}
