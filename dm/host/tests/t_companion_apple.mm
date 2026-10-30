// Exercise the Apple adapter with a synthetic C-ABI module, without game files or a UI.
#import "../companion_apple.h"
#import <Metal/Metal.h>
#include "../companion.h"
#include "../../third_party/eden_duo/core/mods/dsmod_module_abi.h"
#include "../../third_party/eden_duo/core/mods/dsmod_module_extensions.h"
#include <atomic>
#include <cassert>
#include <cstring>
#include <unistd.h>
static std::atomic<int> build,creates,samples,input,argument,pauseSample;
static std::atomic<int> moduleButton{1};
static std::atomic<int> forbidOldModuleButton,staleModulePublications;
static dispatch_semaphore_t entered,released;
static EdenDsmodHostExtensions codecs;
static EdenDsmodHostWriteApi writer;
static std::atomic<int> batches,imageLoads;
uint64_t dm_companion_title_id(void) { return UINT64_C(0x01006F8002326000); }
int dm_companion_guest_info(dm_companion_guest *g) { memset(g,0,sizeof *g);g->title_id=dm_companion_title_id();strcpy(g->build_id,build ? "ff1d1c05670db6021c85b624a710b963" : "00000000000000000000000000000000");g->main_base=0x10000;g->main_size=0x10000;return 1; }
int dm_companion_guest_mapped(uint64_t,size_t) { return 0; }
int dm_companion_guest_read(uint64_t,void*,size_t) { return 0; }
int dm_companion_guest_write_batch(const dm_companion_write_op *ops,uint32_t count) { assert(count==1 && ops[0].address==0x20000 && ops[0].size==1 && ops[0].expect && ops[0].value);++batches;return 1; }
void dm_companion_input(uint64_t mask) { if(forbidOldModuleButton && (mask&1))++staleModulePublications;input=(int)mask; }
void dm_companion_input_reset(void) { input=0; }
static EdenDsmodBool supports(const char *s) { return !strcmp(s,"ff1d1c05670db6021c85b624a710b963"); }
static void *create(const EdenDsmodHostApi *h,const char *) { assert(!h->write_memory && !h->queue_guest_call && !h->get_read_pointer);char data[4]={0};assert(h->read_romfs(h->userdata,"/fixture",0,nullptr,0)==4);assert(h->read_romfs(h->userdata,"fixture",1,data,3)==3 && !memcmp(data,"bcd",3));assert(!h->read_romfs(h->userdata,"../fixture",0,nullptr,0));assert(!h->read_romfs(h->userdata,"fixture",3,data,2));++creates;return &creates; }
static void sample(void*,const EdenDsmodHostApi *h) { ++samples;int button=moduleButton;if(pauseSample.exchange(0)){dispatch_semaphore_signal(entered);dispatch_semaphore_wait(released,DISPATCH_TIME_FOREVER);}h->publish_i64(h->userdata,"acnh.ready",1);h->publish_i64(h->userdata,"pdrv.a",button);h->publish_text(h->userdata,"island.name","Synthetic island"); }
static void configure(void*,const EdenDsmodHostExtensions *h) { codecs=*h;assert(!h->mailbox_address && !h->store_u32 && h->decode_astc); }
static EdenDsmodBool action(void*,const char*,int64_t n) { argument=(int)n;return 1; }
static EdenDsmodBool image(void*,const EdenDsmodHostApi *h,const char *key,void *r,EdenDsmodImageSink sink) { ++imageLoads;assert(!h->write_memory && !h->publish_i64 && !h->get_text);assert(h->get_i64(h->userdata,"missing",42)==42);assert(h->get_i64(h->userdata,"__relocation_delta",42)==0);uint8_t pixels[]={255,0,0,255,0,255,0,128};sink(r,strstr(key,"oversize") ? 4097 : 2,1,pixels,sizeof pixels);return 1; }
const EdenDsmodModuleApi *eden_dsmod_get_module(uint32_t v,uint64_t hash) { assert(v==EDEN_DSMOD_MODULE_ABI_VERSION && hash==EDEN_DSMOD_MODULE_ABI_HASH);static const EdenDsmodModuleApi api={.abi_version=v,.struct_size=sizeof(EdenDsmodModuleApi),.abi_hash=hash,.title_id=dm_companion_title_id(),.name="Synthetic",.supports_build=supports,.create=create,.sample=sample};return &api; }
const EdenDsmodModuleExtensions *eden_dsmod_get_extensions(uint32_t v,uint64_t hash) { static const EdenDsmodModuleExtensions ext={.version=v,.struct_size=sizeof(EdenDsmodModuleExtensions),.abi_hash=hash,.configure=configure,.on_action=action,.load_image=image};return &ext; }
static void configureWrite(void*,const EdenDsmodHostWriteApi *h) { assert(h->version==EDEN_DSMOD_WRITE_EXT_VERSION && h->struct_size==sizeof *h && h->abi_hash==EDEN_DSMOD_WRITE_EXT_HASH);writer=*h; }
const EdenDsmodModuleWriteExtensions *eden_dsmod_get_write_extensions(uint32_t v,uint64_t hash) { assert(v==EDEN_DSMOD_WRITE_EXT_VERSION && hash==EDEN_DSMOD_WRITE_EXT_HASH);static const EdenDsmodModuleWriteExtensions ext={.version=v,.struct_size=sizeof(EdenDsmodModuleWriteExtensions),.abi_hash=hash,.configure=configureWrite};return &ext; }
static void until(BOOL (^condition)(void)) { for(int i=0;i<200 && !condition();i++)usleep(10000);assert(condition()); }
int main(void) { @autoreleasepool {
    char path[]="/tmp/dm-companion-test-XXXXXX";assert(mkdtemp(path));NSString *root=@(path);
    [@"{\"input_gates\":{\"pdrv.a\":1,\"pdrv.b\":2},\"write_builds\":[\"ff1d1c05670db6021c85b624a710b963\"]}" writeToFile:[root stringByAppendingPathComponent:@"companion.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"abcd" writeToFile:[root stringByAppendingPathComponent:@"fixture"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    setenv("DM_ROMFS",path,1);setenv("DM_NVN_SHMAP",[root stringByAppendingPathComponent:@"shader.tsv"].fileSystemRepresentation,1);
    entered=dispatch_semaphore_create(0);released=dispatch_semaphore_create(0);
    DMCompanion *c=DMCompanion.shared;assert(c.supported);[c start];
    until(^{return [c.snapshot[@"host.unsupported"]boolValue];});assert(creates==0);
    build=1;until(^{return [c.snapshot[@"acnh.ready"]boolValue];});assert(creates==1);
    assert(input==1);assert(writer.write_batch);
    uint8_t old=1,value=2;EdenDsmodWriteOp op={.address=0x20000,.size=1,.reserved=0,.expect=&old,.value=&value};
    assert(writer.write_batch(writer.userdata,&op,1) && batches==1);
    op.reserved=1;assert(!writer.write_batch(writer.userdata,&op,1) && batches==1);op.reserved=0;
    assert(!writer.write_batch(writer.userdata,&op,33) && !writer.write_batch(writer.userdata,nullptr,1));
    assert([c.snapshot[@"island.name"]isEqual:@"Synthetic island"]);
    [c action:@"ui_open" argument:4];until(^{return argument==4;});
    moduleButton=0;until(^{return input==0;});
    [c action:@"host.press.b" argument:500];until(^{return input==2;});
    [c setVisible:NO];assert(input==0);[c setVisible:YES];usleep(100000);assert(input==0);
    [c action:@"host.press.unknown" argument:500];usleep(100000);assert(input==0);
    moduleButton=1;until(^{return input==1;});
    // Input edges and their release remain prompt while a passive-page sample is blocked.
    pauseSample=1;assert(!dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)));
    [c action:@"host.press.b" argument:120];assert(input==3);
    usleep(200000);assert(input==1);
    [c action:@"host.press.b" argument:150];usleep(70000);
    [c action:@"host.press.b" argument:500];usleep(180000);assert(input==3);
    [c setVisible:NO];[c setVisible:YES];[c action:@"host.press.b" argument:500];assert(input==2);
    usleep(350000);assert(input==2); // The older pulse cannot release this newer one.
    [c setVisible:NO];assert(input==0);dispatch_semaphore_signal(released);usleep(200000);assert(input==0);
    [c setVisible:YES];until(^{return input==1;});
    puts("companion Apple: immediate input, independent timed release and stale-release cancellation passed");
    pauseSample=1;assert(!dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)));
    [c setVisible:NO];moduleButton=0;forbidOldModuleButton=1;[c setVisible:YES];
    [c action:@"host.press.b" argument:500];assert(input==2);dispatch_semaphore_signal(released);
    usleep(250000);assert(staleModulePublications==0 && (input&1)==0);
    forbidOldModuleButton=0;[c setVisible:NO];moduleButton=1;[c setVisible:YES];until(^{return input==1;});
    puts("companion Apple: sample from an earlier presentation cannot restore old input after resume");
    pauseSample=1;assert(!dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)));
    [c setVisible:NO];dispatch_semaphore_signal(released);usleep(150000);assert(input==0);
    assert(!writer.write_batch(writer.userdata,&op,1) && batches==1);
    int count=samples;usleep(150000);assert(samples==count);
    [c setVisible:YES];until(^{return samples>count;});assert(input==1);
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [c image:@"module:test" completion:^(NSData *d,NSUInteger w,NSUInteger h){assert(w==2 && h==1 && d.length==8);dispatch_semaphore_signal(done);}];
    assert(!dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)));
    [c image:@"module:oversize" completion:^(NSData *d,NSUInteger,NSUInteger){assert(!d);dispatch_semaphore_signal(done);}];
    assert(!dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)));
    [c image:@"file:bad" completion:^(NSData *d,NSUInteger,NSUInteger){assert(!d);dispatch_semaphore_signal(done);}];
    assert(!dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC)));
    for(unsigned i=0;i<1024;i++){@autoreleasepool{
        [c image:[NSString stringWithFormat:@"module:oversize-%u",i] completion:^(NSData *d,NSUInteger,NSUInteger){assert(!d);dispatch_semaphore_signal(done);}];
        assert(!dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)));
    }}
    assert([[c valueForKey:@"failedImages"]count]<=512 && [[c valueForKey:@"failedImageKeys"]count]<=512);
    int beforeRetry=imageLoads;
    [c image:@"module:oversize-1023" completion:^(NSData *d,NSUInteger,NSUInteger){assert(!d);dispatch_semaphore_signal(done);}];
    assert(!dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC)) && imageLoads==beforeRetry);
    usleep(1100000);
    [c image:@"module:oversize-1023" completion:^(NSData *d,NSUInteger,NSUInteger){assert(!d);dispatch_semaphore_signal(done);}];
    assert(!dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC)) && imageLoads==beforeRetry+1);
    assert([[c valueForKey:@"failedImages"]count]==1 && [[c valueForKey:@"failedImageKeys"]count]==1);
    puts("companion Apple: bounded failure metadata, cooldown and expiry passed");
    // The host suite also runs on virtual CI Macs without a native Apple GPU.
    // Keep all bridge tests there; require exact decoded pixels on supported hardware.
    if([MTLCreateSystemDefaultDevice() supportsFamily:MTLGPUFamilyApple1]){
        uint8_t block[]={0xfc,0xfd,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0,0,0,0,0xff,0xff},rgba[64]={0};
        assert(codecs.decode_astc(codecs.userdata,4,4,4,4,block,sizeof block,rgba,sizeof rgba));
        for(unsigned i=0;i<sizeof rgba;i+=4)assert(rgba[i]==255 && rgba[i+1]==0 && rgba[i+2]==0 && rgba[i+3]==255);
        assert(!codecs.decode_astc(codecs.userdata,4,4,4,4,block,15,rgba,sizeof rgba));
        assert(!codecs.decode_astc(codecs.userdata,4,4,3,3,block,16,rgba,sizeof rgba));
        puts("companion Apple: known ASTC pixels passed");
    }else puts("companion Apple: ASTC pixels skipped (native Apple GPU required)");
    [c setVisible:NO];[NSFileManager.defaultManager removeItemAtPath:root error:nil];puts("companion Apple: build gate, bounded RomFS, actions, lifecycle race and image bounds passed");return 0;
} }
