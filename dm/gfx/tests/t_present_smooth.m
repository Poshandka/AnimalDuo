// Real Metal/Video Toolbox checks without game files: intermediate positions,
// original pixels, ticket isolation, allocator fences and bounded pending work.
#include "../nvn/nvn_mtl.m"
#import <objc/runtime.h>
static NSProcessInfoThermalState test_thermal;
static NSProcessInfoThermalState thermal_state(id object,SEL selector){(void)object;(void)selector;return test_thermal;}
static CAMetalLayer *test_layer;
void *front_metal_layer(void){return (__bridge void *)test_layer;}
module_t *module_of(const void *p){(void)p;return NULL;}
module_t g_mod[MAX_MOD];int g_nmod;
void svc_thread_dump(void){}
uint64_t now_ns(void){return bp_now();}
static int checks,failed;
#define CHECK(label,ok) do{checks++;if(!(ok)){failed++;fprintf(stderr,"FAIL: %s\n",label);}else printf("PASS: %s\n",label);}while(0)
static tex_t source(uint64_t serial,int x) {
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1280 height:720 mipmapped:NO];
    d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> t=[g_dev newTextureWithDescriptor:d];uint8_t *bytes=malloc(1280*720*4);
    for(int j=0;j<720;j++)for(int i=0;i<1280;i++){uint8_t v=i>=x && i<x+120 && j>=250 && j<370?220:40;size_t k=(j*1280+i)*4;bytes[k]=bytes[k+1]=bytes[k+2]=v;bytes[k+3]=255;}
    [t replaceRegion:MTLRegionMake2D(0,0,1280,720) mipmapLevel:0 withBytes:bytes bytesPerRow:1280*4];free(bytes);
    res_add(t);res_commit();serial_put(serial,t);
    return (tex_t){.magic=MAGIC('T','E','X',0),.serial=serial};
}
static BOOL processed(uint64_t ticket) {
    double end=CACurrentMediaTime()+10;__block BOOL done=NO;
    while(!done && CACurrentMediaTime()<end){dispatch_sync(smooth_worker,^{done=smooth_previous_ticket>=ticket;});if(!done)usleep(1000);}
    return done;
}
static double centre(CVPixelBufferRef b) {
    CVPixelBufferLockBaseAddress(b,kCVPixelBufferLock_ReadOnly);
    const uint8_t *p=CVPixelBufferGetBaseAddress(b);size_t stride=CVPixelBufferGetBytesPerRow(b);double sum=0,n=0;
    for(int y=270;y<350;y++)for(int x=100;x<450;x++)if(p[y*stride+x*4]>160){sum+=x;n++;}
    CVPixelBufferUnlockBaseAddress(b,kCVPixelBufferLock_ReadOnly);return n?sum/n:-1;
}
static BOOL original_pixels(DmSmoothFrame *frame,int left) {
    CVPixelBufferLockBaseAddress(frame->pixels,kCVPixelBufferLock_ReadOnly);
    const uint8_t *p=CVPixelBufferGetBaseAddress(frame->pixels);size_t stride=CVPixelBufferGetBytesPerRow(frame->pixels);int bad=0;
    for(int y=0;y<720;y++)for(int x=0;x<1280;x++){uint8_t want=x>=left && x<left+120 && y>=250 && y<370?220:40;const uint8_t *v=p+y*stride+x*4;bad+=v[0]!=want || v[1]!=want || v[2]!=want || v[3]!=255;}
    CVPixelBufferUnlockBaseAddress(frame->pixels,kCVPixelBufferLock_ReadOnly);return !bad;
}
static id<CAMetalDrawable> drawable(NSMutableArray *layers) {
    CAMetalLayer *l=[CAMetalLayer layer];l.device=g_dev;l.pixelFormat=MTLPixelFormatBGRA8Unorm;l.framebufferOnly=NO;l.drawableSize=CGSizeMake(1280,720);
    [g_q4 addResidencySet:l.residencySet];[layers addObject:l];return [l nextDrawable];
}
static dispatch_semaphore_t fourth_done;
static tex_t held_source;
static id<CAMetalDrawable> held_drawable;
static DmSmoothFrame *held_middle;
static void *fourth(void *unused) {
    (void)unused;@autoreleasepool{present_picture(&held_source,0,11,0,NULL,held_drawable,0,held_middle->middle,held_middle,1);}
    dispatch_semaphore_signal(fourth_done);return NULL;
}
int main(int argc,char **argv){@autoreleasepool{
    method_setImplementation(class_getInstanceMethod(object_getClass(NSProcessInfo.processInfo),@selector(thermalState)),(IMP)thermal_state);
    if(argc>1){
        unsetenv("DM_PRESENT_SMOOTH");
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];
        CHECK("mobile smoothing defaults off",!smooth_requested(1));
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"DmMotionSmoothing":@YES} forName:NSArgumentDomain];
        CHECK("an explicit mobile preference enables smoothing",smooth_requested(1));
        setenv("DM_PRESENT_SMOOTH","0",1);
        CHECK("an explicit environment off overrides the saved preference",!smooth_requested(1));
        if(!strcmp(argv[1],"off")){
            CHECK("disabled smoothing never starts an image worker",!smooth_on() && !smooth_worker && !smooth_processor);
        } else {
            setenv("DM_PRESENT_SMOOTH","1",1);test_thermal=!strcmp(argv[1],"critical") ? NSProcessInfoThermalStateCritical:NSProcessInfoThermalStateSerious;
            CHECK("a hot launch cannot start smoothing",!smooth_on() && atomic_load(&smooth_stopped)==1 && !smooth_worker && !smooth_processor);
            test_thermal=NSProcessInfoThermalStateNominal;
            CHECK("cooling does not restart the processor in this session",!smooth_on());
        }
        return failed!=0;
    }
    alarm(40);setbuf(stdout,NULL);setenv("DM_PRESENT_SMOOTH","1",1);setenv("DM_PRESENT_LINK","0",1);setenv("DM_NVN_ENC_THREAD","0",1);setenv("DM_FPS","30",1);
    mtl_init();test_layer=[CAMetalLayer layer];test_layer.device=g_dev;test_layer.pixelFormat=MTLPixelFormatBGRA8Unorm;
    if(!smooth_on()){puts("SKIP: low-latency interpolation is unavailable");return 0;}
    g_dm_present_link=2;g_link_mode=2;g_link_started=1;link_sync();
    CHECK("30 fps interpolation selects 60 Hz even with a 120 Hz override",g_link_mode==1);
    g_dm_present_link=0;g_link_started=0;
    smooth_start(1280,720);dispatch_sync(smooth_worker,^{});
    CHECK("processor prepares off the display callback",atomic_load(&smooth_ready));if(!atomic_load(&smooth_ready))return 1;
    tex_t a=source(95001,200),b=source(95002,220);
    atomic_store(&g_origin_ll,1);
    smooth_prepare(&a,10,1./30,NULL);CHECK("first original copied",processed(10));
    DmSmoothFrame *first=smooth_frames[@10];CHECK("source copy preserves every original pixel",first && original_pixels(first,200));
    smooth_prepare(&b,11,1./30,NULL);CHECK("next original processed",processed(11));
    DmSmoothFrame *middle=smooth_middle(11,10);CHECK("adjacent originals produce an intermediate",middle!=nil);if(!middle)return 1;
    double c=centre(middle->middlePixels);printf("intermediate rectangle centre: %.3f (expected 269.5)\n",c);
    CHECK("moving object is halfway between its original positions",fabs(c-269.5)<3);
    CHECK("next original pixels remain unchanged",original_pixels(middle,220));
    CHECK("a skipped original cannot use the wrong intermediate",smooth_middle(11,9)==nil);
    atomic_store(&g_origin_ll,0);
    // All intermediate tickets are zero; they must never reuse allocator zero
    // before its own GPU feedback or publish a fake game present/acquire ticket.
    id<MTLSharedEvent> gate=[g_dev newSharedEvent];[g_q4 waitForEvent:gate value:1];
    NSMutableArray *layers=[NSMutableArray array];uint64_t saved_done=g_pq_done;g_pres[0]=(pres_ent){987,123};
    for(int i=0;i<3;i++)present_picture(&b,0,11,0,NULL,drawable(layers),0,middle->middle,middle,1);
    CHECK("three intermediates can be in flight",g_pq_inflight==3);
    held_source=b;held_middle=middle;held_drawable=drawable(layers);fourth_done=dispatch_semaphore_create(0);pthread_t thread;pthread_create(&thread,NULL,fourth,NULL);
    BOOL early=dispatch_semaphore_wait(fourth_done,dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC))==0;
    CHECK("intermediate allocator waits for its own GPU work",!early);gate.signaledValue=1;
    CHECK("intermediate resumes after GPU completion",early || dispatch_semaphore_wait(fourth_done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);pthread_join(thread,NULL);
    [g_q4 signalEvent:gate value:2];CHECK("intermediate rendering completes",[gate waitUntilSignaledValue:2 timeoutMS:5000]);
    CHECK("intermediates do not release game acquire tickets",g_pq_done==saved_done);
    CHECK("intermediates do not overwrite game present statistics",g_pres[0].n==987 && g_pres[0].t==123);
    smooth_retire(11);CHECK("retirement prevents stale intermediate reuse",smooth_middle(11,10)==nil);
    [g_q4 waitForEvent:gate value:3];double start=CACurrentMediaTime();
    for(uint64_t n=20;n<40;n++)smooth_prepare(&b,n,1./30,NULL);
    CHECK("pending copies never wait for the GPU",CACurrentMediaTime()-start<1);
    CHECK("pending frame count remains bounded",smooth_frames.count<=6);
    int copies=0;for(int i=0;i<6;i++)copies+=smooth_copies[i].allocator!=nil;
    CHECK("at most six source command allocators are created",copies<=6);
    test_thermal=NSProcessInfoThermalStateSerious;
    CHECK("thermal protection stops new work immediately",!smooth_on() && !atomic_load(&smooth_ready));
    CHECK("thermal protection never displays a stale intermediate",smooth_middle(11,10)==nil);
    smooth_prepare(&a,41,1./30,NULL);CHECK("thermal protection adds no source copy",smooth_frames[@41]==nil);
    g_dm_present_link=1;g_link_mode=1;g_link_started=1;link_sync();
    CHECK("thermal protection restores the 30 Hz display mode",g_link_mode==3);g_dm_present_link=0;g_link_started=0;
    gate.signaledValue=3;[g_q4 signalEvent:gate value:4];CHECK("retired source copies still finish safely",[gate waitUntilSignaledValue:4 timeoutMS:5000]);
    dispatch_sync(smooth_worker,^{});CHECK("retirement frees all pending frame slots",smooth_frames.count==0);
    CHECK("thermal protection releases processor and image pools",!smooth_processor && !smooth_previous && !smooth_inputs && !smooth_outputs && !smooth_yuvs && !smooth_cache);
    CHECK("queued callbacks cannot prepare another image after cutoff",atomic_load(&smooth_prepared)==1);
    test_thermal=NSProcessInfoThermalStateNominal;
    CHECK("cooling keeps smoothing off until next launch",!smooth_on());
    CHECK("thermal protection keeps the opt-in preference",smooth_requested(1));
    uint64_t original=g_pq_done+1;
    CHECK("original rendering remains available after cutoff",present_now(&b,1./30,42,original,NULL,drawable(layers),0));
    [g_q4 signalEvent:gate value:5];BOOL gpu_done=[gate waitUntilSignaledValue:5 timeoutMS:5000];
    pthread_mutex_lock(&g_pq_mu);
    while(g_pq_inflight)pthread_cond_wait(&g_pq_cv,&g_pq_mu);
    CHECK("original game completion still advances",gpu_done && g_pq_done==original);pthread_mutex_unlock(&g_pq_mu);
    puts("Original game timing is covered by t_link_ticks/t_present_snap and the gameplay route.");
    printf("motion smoothing: %d checks, %d failed\n",checks,failed);return failed!=0;
}}
