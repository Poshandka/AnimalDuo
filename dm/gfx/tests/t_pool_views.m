// Real Metal ownership checks for every descriptor view of a finalized pool.
#ifndef POOL_VIEW_SOURCE
#define POOL_VIEW_SOURCE "../nvn/nvn_mtl.m"
#endif
#include POOL_VIEW_SOURCE
uint64_t g_t0_ns;
int dm_guest_as_contains(uintptr_t a) { (void)a; return 0; }
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks,failures;
#define CHECK(c,label) do { checks++; if(!(c)){failures++;fprintf(stderr,"FAIL: %s\n",label);} } while(0)
static void finish_retirement(int open) {
    if(!open)mtl_sub_begin();uint64_t fence=mtl_sub_commit();
    CHECK(mtl_wait(fence,5000000000ull),"retirement fence completes");defer_drain();res_commit();
}
static id<MTLTexture> texture(void) {
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Float width:512 height:512 mipmapped:NO];
    d.textureType=MTLTextureType2DArray;d.arrayLength=1;d.storageMode=MTLStorageModeShared;d.usage=MTLTextureUsageShaderRead|MTLTextureUsagePixelFormatView;
    id<MTLTexture> t=[g_dev newTextureWithDescriptor:d];size_t bytes=512*512*4;uint32_t *input=malloc(bytes);
    for(size_t i=0;i<bytes/4;i++)input[i]=0x35353535;
    [t replaceRegion:MTLRegionMake2D(0,0,512,512) mipmapLevel:0 slice:0 withBytes:input bytesPerRow:512*4 bytesPerImage:bytes];free(input);
    res_add(t);return t;
}
static void pixel(id<MTLTexture> t) {
    uint32_t value=0;[t getBytes:&value bytesPerRow:4 bytesPerImage:4 fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 slice:0];
    CHECK(value==0x35353535,"the retained live view still reads its original pixel");
}
int main(void) { @autoreleasepool {
    setenv("DM_PSO_MANIFEST","off",1);mtl_init();
    enum { N=32 };__weak id<MTLTexture> retired[N];pool_t pool={0},other={0};
    tex_t live={.magic=MAGIC('T','E','X',0),.serial=750000,.pool=&other};live.d=(nvn_texdesc){.target=NVN_TEXTURE_TARGET_2D_ARRAY,.format=NVN_FORMAT_R32F,.width=512,.height=512,.depth=1,.levels=1,.samples=1};
    id<MTLTexture> survivor=texture();mtl_tex_init(&live);serial_put(live.serial,survivor);mtl_reg_tex(1,&live,NULL);
    id<MTLTexture> sb=tex_by_id(1);uint64_t srid=0;id<MTLTexture> sv=tex_fit(1,sb,MTLTextureType2D,&srid);CHECK(sv!=nil,"live pool builds its compatible view");pixel(sv);
    uint64_t initial=g_dev.currentAllocatedSize;
    for(int i=0;i<N;i++) { @autoreleasepool {
        tex_t t=live;t.serial=751000+i;t.pool=&pool;int tid=20+i;
        id<MTLTexture> base=texture();mtl_tex_init(&t);serial_put(t.serial,base);mtl_reg_tex(tid,&t,NULL);
        id<MTLTexture> b=tex_by_id(tid);uint64_t rid=0;
        id<MTLTexture> v=tex_fit(tid,b,MTLTextureType2D,&rid);retired[i]=v;CHECK(v!=nil && v.textureType==MTLTextureType2D,"type-compatible view is populated through the production path");pixel(v);
        id<MTLTexture> im=img_fit(tid,b,NVN_DPF_UINT,&rid);CHECK(im!=nil && im.pixelFormat==MTLPixelFormatR32Uint,"integer image view is populated through the production path");
        mtl_sub_begin();id<MTLBuffer> output=[g_dev newBufferWithLength:512*512*4 options:MTLResourceStorageModeShared];res_add(output);
        enc_b_copy_texture_buffer(blit(),base,0,0,MTLOriginMake(0,0,0),MTLSizeMake(512,512,1),output,0,512*4,512*512*4);
        if(i&1){defer_obj_unref((__bridge id)g_treg[tid].view);CFRelease(g_treg[tid].view);g_treg[tid].view=NULL;}
        mtl_tex_release(&t);mtl_alias_drop_pool(&pool);
        CHECK(!g_treg[tid].view && !g_treg[tid].alt && !g_treg[tid].im,"pool finalization clears primary, compatible and image views, even without a primary cache entry");
        CHECK(g_treg[1].view && g_treg[1].alt,"unrelated live pool retains both cached views");pixel(sv);
        finish_retirement(1);
        int valid=!mtl_last_commit_error();uint32_t *out=output.contents;for(size_t j=0;j<512*512;j++)valid &= out[j]==0x35353535;
        CHECK(valid,"every recorded GPU pixel survives descriptor retirement until its submission completes");res_remove(output);
    }}
    @autoreleasepool { finish_retirement(0); }
    int alive=0;for(int i=0;i<N;i++)alive+=retired[i]!=nil;
    CHECK(alive==0,"all 32 retired compatible views are reclaimed after their GPU fence");
    printf("{\"retired_views\":%d,\"still_alive\":%d,\"initial_gpu_bytes\":%llu,\"settled_gpu_bytes\":%llu}\n",N,alive,(unsigned long long)initial,(unsigned long long)g_dev.currentAllocatedSize);
    mtl_tex_release(&live);mtl_alias_drop_pool(&other);finish_retirement(0);
    printf("t_pool_views: %d checks, %d failed\n",checks,failures);return failures!=0;
} }
