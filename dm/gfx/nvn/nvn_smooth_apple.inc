// Optional Apple motion interpolation. Game presents and simulation remain at their original rate.
// Copies run after the frame on its Metal 4 queue; a serial worker performs image processing.
// The display callback only uses a ready frame between two adjacent original tickets.
#if TARGET_OS_OSX || (TARGET_OS_IOS && !TARGET_OS_SIMULATOR)
#import <VideoToolbox/VTFrameProcessor.h>
#import <VideoToolbox/VTPixelTransferSession.h>
#import <VideoToolbox/VTFrameProcessor_LowLatencyFrameInterpolation.h>
#import <CoreVideo/CoreVideo.h>
@interface DmSmoothFrame : NSObject {
@public
    uint64_t ticket, previous;
    _Atomic int ready, retired;
    CVPixelBufferRef pixels, middlePixels;
    CVMetalTextureRef inputView, middleView;
    id<MTLTexture> input, middle;
}
@end
@implementation DmSmoothFrame
- (void)dealloc {
    res_remove(input);res_remove(middle);
    if(inputView)CFRelease(inputView);if(middleView)CFRelease(middleView);
    if(pixels)CVPixelBufferRelease(pixels);if(middlePixels)CVPixelBufferRelease(middlePixels);
}
@end
static pthread_mutex_t smooth_mu=PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t smooth_cache_mu=PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary<NSNumber *,DmSmoothFrame *> *smooth_frames;
static dispatch_queue_t smooth_worker;
static CVMetalTextureCacheRef smooth_cache;
static CVPixelBufferPoolRef smooth_inputs,smooth_outputs,smooth_yuvs;
static VTFrameProcessor *smooth_processor;
static VTPixelTransferSessionRef smooth_transfer;
static CVPixelBufferRef smooth_previous;
static uint64_t smooth_previous_ticket;
static _Atomic int smooth_ready;
static _Atomic int smooth_stopped; // Latched until restart: 1 thermal protection, 2 unavailable/failed.
static NSUInteger smooth_width,smooth_height;
static _Atomic uint64_t smooth_prepared,smooth_used,smooth_missed,smooth_skipped;
// Allocators are reset only after their own GPU feedback. Creating one per frame
// made driver command memory grow despite the image resources being retired.
static struct {id<MTL4CommandAllocator> allocator;id<MTL4CommandBuffer> commands;id<MTL4ArgumentTable> args;id<MTLBuffer> uv;_Atomic int busy;} smooth_copies[6];
static void smooth_retire(uint64_t through);
// Runs only on the image worker, after any in-progress processor call. Existing
// GPU feedback retains its source frame until the source copy has finished.
static void smooth_cleanup(void) {
    smooth_retire(UINT64_MAX);
    [smooth_processor endSession];smooth_processor=nil;
    if(smooth_previous){CVPixelBufferRelease(smooth_previous);smooth_previous=NULL;}smooth_previous_ticket=0;
    if(smooth_transfer){VTPixelTransferSessionInvalidate(smooth_transfer);CFRelease(smooth_transfer);smooth_transfer=NULL;}
    pthread_mutex_lock(&smooth_mu);
    if(smooth_inputs){CFRelease(smooth_inputs);smooth_inputs=NULL;}
    if(smooth_outputs){CFRelease(smooth_outputs);smooth_outputs=NULL;}
    if(smooth_yuvs){CFRelease(smooth_yuvs);smooth_yuvs=NULL;}
    pthread_mutex_unlock(&smooth_mu);
    pthread_mutex_lock(&smooth_cache_mu);
    if(smooth_cache){CVMetalTextureCacheFlush(smooth_cache,0);CFRelease(smooth_cache);smooth_cache=NULL;}
    pthread_mutex_unlock(&smooth_cache_mu);
}
static void smooth_stop(int reason) {
    int expected=0;if(!atomic_compare_exchange_strong(&smooth_stopped,&expected,reason))return;
    atomic_store(&smooth_ready,0);
    MLOG("motion smoothing stopped until next launch: %s; original game presentation continues",reason==1?"serious/critical thermal state":"processor unavailable or failed");
    pthread_mutex_lock(&smooth_mu);dispatch_queue_t worker=smooth_worker;pthread_mutex_unlock(&smooth_mu);
    if(worker)dispatch_async(worker,^{smooth_cleanup();});
}
static int smooth_requested(int mobile) {
    const char *e=getenv("DM_PRESENT_SMOOTH");
    id preference=[NSUserDefaults.standardUserDefaults objectForKey:@"DmMotionSmoothing"];
    // A desktop bundle default must never opt a mobile device in accidentally.
    return e ? atoi(e)>0 : preference ? [preference boolValue] : !mobile && [NSBundle.mainBundle.infoDictionary[@"DMFrameSmoothingDefault"]boolValue];
}
static int smooth_on(void) {
    static dispatch_once_t once;static int on;
    dispatch_once(&once,^{
        on=smooth_requested(TARGET_OS_IOS);
        if(on) {
            if(@available(macOS 26.0,iOS 26.0,*)){if(!VTLowLatencyFrameInterpolationConfiguration.isSupported)on=0;}
            else on=0;
            MLOG("motion smoothing: %s",on?"enabled for 30 fps presents; game timing is unchanged":"unavailable on this system");
        }
    });
    if(!on || atomic_load(&smooth_stopped))return 0;
    if(NSProcessInfo.processInfo.thermalState>=NSProcessInfoThermalStateSerious){smooth_stop(1);return 0;}
    return 1;
}
static CVPixelBufferPoolRef smooth_pool(int width,int height,OSType format) {
    CVPixelBufferPoolRef pool=NULL;
    CVPixelBufferPoolCreate(NULL,NULL,(__bridge CFDictionaryRef)@{(id)kCVPixelBufferWidthKey:@(width),(id)kCVPixelBufferHeightKey:@(height),(id)kCVPixelBufferPixelFormatTypeKey:@(format),(id)kCVPixelBufferIOSurfacePropertiesKey:@{},(id)kCVPixelBufferMetalCompatibilityKey:@YES},&pool);
    return pool;
}
static CVPixelBufferRef smooth_buffer(CVPixelBufferPoolRef pool,int cap) {
    CVPixelBufferRef b=NULL;if(pool)CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(NULL,pool,(__bridge CFDictionaryRef)@{(id)kCVPixelBufferPoolAllocationThresholdKey:@(cap)},&b);
    if(b){CVBufferSetAttachment(b,kCVImageBufferColorPrimariesKey,kCVImageBufferColorPrimaries_ITU_R_709_2,kCVAttachmentMode_ShouldPropagate);CVBufferSetAttachment(b,kCVImageBufferTransferFunctionKey,kCVImageBufferTransferFunction_sRGB,kCVAttachmentMode_ShouldPropagate);CVBufferSetAttachment(b,kCVImageBufferYCbCrMatrixKey,kCVImageBufferYCbCrMatrix_ITU_R_709_2,kCVAttachmentMode_ShouldPropagate);}
    return b;
}
static id<MTLTexture> smooth_texture(CVPixelBufferRef b,CVMetalTextureRef *view) {
    if(!b)return nil;
    pthread_mutex_lock(&smooth_cache_mu);
    CVReturn r=smooth_cache ? CVMetalTextureCacheCreateTextureFromImage(NULL,smooth_cache,b,(__bridge CFDictionaryRef)@{(id)kCVMetalTextureUsage:@(MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead)},MTLPixelFormatBGRA8Unorm,CVPixelBufferGetWidth(b),CVPixelBufferGetHeight(b),0,view) : kCVReturnError;
    pthread_mutex_unlock(&smooth_cache_mu);
    return r==kCVReturnSuccess?CVMetalTextureGetTexture(*view):nil;
}
static void smooth_start(NSUInteger width,NSUInteger height) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        smooth_width=width;smooth_height=height;
        pthread_mutex_lock(&smooth_mu);smooth_frames=[NSMutableDictionary dictionary];
        smooth_worker=dispatch_queue_create("dm.motion-interpolation",DISPATCH_QUEUE_SERIAL);
        pthread_mutex_unlock(&smooth_mu);
        dispatch_async(smooth_worker,^{@autoreleasepool{
            if(!smooth_on())return;
            NSUInteger w=MIN(width,1280),h=((height*w/width)/2)*2;w=(w/2)*2;
            VTLowLatencyFrameInterpolationConfiguration *c=[[VTLowLatencyFrameInterpolationConfiguration alloc]initWithFrameWidth:w frameHeight:h numberOfInterpolatedFrames:1];
            smooth_processor=[VTFrameProcessor new];NSError *error=nil;double t=CACurrentMediaTime();
            if(!c || ![smooth_processor startSessionWithConfiguration:c error:&error]){MLOG("motion smoothing unavailable: %s",error.description.UTF8String);smooth_stop(2);return;}
            if(CVMetalTextureCacheCreate(NULL,NULL,g_dev,NULL,&smooth_cache)!=kCVReturnSuccess || VTPixelTransferSessionCreate(NULL,&smooth_transfer)){MLOG("motion smoothing could not create image transfer resources");smooth_stop(2);return;}
            smooth_inputs=smooth_pool(width,height,kCVPixelFormatType_32BGRA);smooth_outputs=smooth_pool(w,h,kCVPixelFormatType_32BGRA);smooth_yuvs=smooth_pool(w,h,kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
            if(!smooth_inputs || !smooth_outputs || !smooth_yuvs){MLOG("motion smoothing could not create bounded pixel buffer pools");smooth_stop(2);return;}
            if(!smooth_on())return;
            MLOG("motion interpolation ready: %lux%lu, model prepared in %.1f ms off the render thread",(unsigned long)w,(unsigned long)h,(CACurrentMediaTime()-t)*1000);
            atomic_store(&smooth_ready,1);
        }});
    });
}
static void smooth_process(DmSmoothFrame *frame) { @autoreleasepool {
    if(!smooth_on() || !atomic_load(&smooth_ready) || atomic_load(&frame->retired))return;
    CVPixelBufferRef current=smooth_buffer(smooth_yuvs,4),output=smooth_buffer(smooth_yuvs,4);
    if(!current || !output || VTPixelTransferSessionTransferImage(smooth_transfer,frame->pixels,current))goto finish;
    if(smooth_previous && smooth_previous_ticket+1==frame->ticket) {
        frame->middlePixels=smooth_buffer(smooth_outputs,6);if(!frame->middlePixels)goto remember;
        VTFrameProcessorFrame *before=[[VTFrameProcessorFrame alloc]initWithBuffer:smooth_previous presentationTimeStamp:CMTimeMake(2*smooth_previous_ticket,60)];
        VTFrameProcessorFrame *now=[[VTFrameProcessorFrame alloc]initWithBuffer:current presentationTimeStamp:CMTimeMake(2*frame->ticket,60)];
        VTFrameProcessorFrame *mid=[[VTFrameProcessorFrame alloc]initWithBuffer:output presentationTimeStamp:CMTimeMake(2*frame->ticket-1,60)];
        VTLowLatencyFrameInterpolationParameters *parameters=[[VTLowLatencyFrameInterpolationParameters alloc]initWithSourceFrame:now previousFrame:before interpolationPhase:@[@0.5] destinationFrames:@[mid]];
        NSError *error=nil;double start=CACurrentMediaTime();
        if([smooth_processor processWithParameters:parameters error:&error] && !VTPixelTransferSessionTransferImage(smooth_transfer,output,frame->middlePixels)) {
            if(!smooth_on() || atomic_load(&frame->retired))goto finish;
            frame->middle=smooth_texture(frame->middlePixels,&frame->middleView);
            if(frame->middle){res_add(frame->middle);res_commit();frame->previous=smooth_previous_ticket;atomic_store(&frame->ready,1);smooth_prepared++;}
        } else {MLOG("motion interpolation failed: %s",error.description.UTF8String);smooth_stop(2);goto finish;}
        if(smooth_prepared && smooth_prepared%300==0)MLOG("motion interpolation: prepared %llu, used %llu, unavailable %llu, processing %.2f ms",smooth_prepared,smooth_used,smooth_missed,1000*(CACurrentMediaTime()-start));
    }
remember:
    if(smooth_previous)CVPixelBufferRelease(smooth_previous);smooth_previous=current;current=NULL;smooth_previous_ticket=frame->ticket;
finish:
    if(current)CVPixelBufferRelease(current);if(output)CVPixelBufferRelease(output);
} }
static void smooth_prepare(const tex_t *t,uint64_t ticket,double period,const int crop[4]) {
    if(!smooth_on() || period<.03 || period>.034)return;
    CAMetalLayer *layer=(__bridge CAMetalLayer *)front_metal_layer();
    if(!layer || layer.pixelFormat!=MTLPixelFormatBGRA8Unorm)return;
    id<MTLTexture> src=tex_mtl(t);NSUInteger rect[4];
    if(!src || !present_crop_rect(src,crop,rect) || rect[0] || rect[1] || rect[2]!=src.width || rect[3]!=src.height)return;
    if(src.pixelFormat!=MTLPixelFormatRGBA8Unorm && src.pixelFormat!=MTLPixelFormatRGBA8Unorm_sRGB && src.pixelFormat!=MTLPixelFormatBGRA8Unorm && src.pixelFormat!=MTLPixelFormatBGRA8Unorm_sRGB)return;
    smooth_start(src.width,src.height);
    if(!atomic_load(&smooth_ready) || src.width!=smooth_width || src.height!=smooth_height)return;
    pthread_mutex_lock(&smooth_mu);BOOL full=smooth_frames.count>=6;pthread_mutex_unlock(&smooth_mu);
    if(full){smooth_skipped++;return;}
    pthread_mutex_lock(&smooth_mu);CVPixelBufferPoolRef pool=atomic_load(&smooth_ready)?smooth_inputs:NULL;if(pool)CFRetain(pool);pthread_mutex_unlock(&smooth_mu);
    if(!pool)return;
    DmSmoothFrame *frame=[DmSmoothFrame new];frame->ticket=ticket;frame->pixels=smooth_buffer(pool,6);CFRelease(pool);frame->input=smooth_texture(frame->pixels,&frame->inputView);
    if(!frame->input)return;
    int slot;for(slot=0;slot<6;++slot)if(!atomic_exchange(&smooth_copies[slot].busy,1))break;if(slot==6)return;
    if(!smooth_copies[slot].allocator){
        smooth_copies[slot].allocator=[g_dev newCommandAllocator];smooth_copies[slot].commands=[g_dev newCommandBuffer];smooth_copies[slot].uv=[g_dev newBufferWithLength:32 options:MTLResourceStorageModeShared];
        MTL4ArgumentTableDescriptor *ad=[MTL4ArgumentTableDescriptor new];ad.maxBufferBindCount=1;ad.maxTextureBindCount=1;ad.maxSamplerStateBindCount=1;smooth_copies[slot].args=[g_dev newArgumentTableWithDescriptor:ad error:nil];res_add(smooth_copies[slot].uv);
    }
    id<MTL4CommandAllocator> allocator=smooth_copies[slot].allocator;id<MTL4CommandBuffer> cb=smooth_copies[slot].commands;
    if(!allocator || !cb || !smooth_copies[slot].uv || !smooth_copies[slot].args){atomic_store(&smooth_copies[slot].busy,0);return;}
    res_add(frame->input);res_commit();[allocator reset];
    [cb beginCommandBufferWithAllocator:allocator];
    int encoded=present_encode_m4_args(cb,src,frame->input,crop,smooth_copies[slot].uv,NULL,smooth_copies[slot].args,0);
    [cb endCommandBuffer];if(!encoded){atomic_store(&smooth_copies[slot].busy,0);return;}
    MTL4CommitOptions *options=[MTL4CommitOptions new];
    [options addFeedbackHandler:^(id<MTL4CommitFeedback> feedback){atomic_store(&smooth_copies[slot].busy,0);if(!feedback.error)dispatch_async(smooth_worker,^{smooth_process(frame);});}];
    pthread_mutex_lock(&smooth_mu);
    if(atomic_load(&smooth_stopped)){pthread_mutex_unlock(&smooth_mu);atomic_store(&smooth_copies[slot].busy,0);return;}
    smooth_frames[@(ticket)]=frame;pthread_mutex_unlock(&smooth_mu);
    if(rec_on() && g_rb_started) {
        if(on_sub_thread())rec_publish();rec_blk *block=rec_own_begin();rec_t *r=rec_own_put(block,RO_COMMIT_REAL,2);r->a[0]=rec_obj(options);r->a[1]=rec_obj(cb);rec_own_push(block);
    } else {pthread_mutex_lock(&g_res_mu);[g_q4 commit:&cb count:1 options:options];pthread_mutex_unlock(&g_res_mu);}
}
static DmSmoothFrame *smooth_middle(uint64_t ticket,uint64_t previous) {
    if(!smooth_on() || !atomic_load(&smooth_ready))return nil;
    pthread_mutex_lock(&smooth_mu);DmSmoothFrame *frame=smooth_frames[@(ticket)];pthread_mutex_unlock(&smooth_mu);
    if(frame && atomic_load(&frame->ready) && frame->previous==previous && !atomic_load(&frame->retired)){smooth_used++;return frame;}
    smooth_missed++;return nil;
}
static void smooth_retire(uint64_t through) {
    NSMutableArray *done=[NSMutableArray array];pthread_mutex_lock(&smooth_mu);
    for(NSNumber *key in smooth_frames)if(key.unsignedLongLongValue<=through){DmSmoothFrame *frame=smooth_frames[key];atomic_store(&frame->retired,1);[done addObject:frame];}
    for(DmSmoothFrame *frame in done)[smooth_frames removeObjectForKey:@(frame->ticket)];pthread_mutex_unlock(&smooth_mu);
}
#else
static int smooth_on(void){return 0;}
static void smooth_prepare(const tex_t *t,uint64_t ticket,double period,const int crop[4]){(void)t;(void)ticket;(void)period;(void)crop;}
static void smooth_retire(uint64_t ticket){(void)ticket;}
#endif
