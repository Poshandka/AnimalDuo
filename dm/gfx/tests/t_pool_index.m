// Exercise public address lookups through pool insertion, overlap and dense-table
// removal, plus a gated lookup while an unrelated pool's writer holds the lock.
#ifndef POOL_TEST_SOURCE
#define POOL_TEST_SOURCE "../nvn/nvn_mtl.m"
#endif
#include POOL_TEST_SOURCE
uint64_t g_t0_ns;
int dm_guest_as_contains(uintptr_t address) { (void)address; return 0; }
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, fails;
#define CHECK(c, msg) do { checks++; if (!(c)) { fails++; fprintf(stderr, "FAIL: %s\n", msg); } } while (0)
enum { N = 64, TOTAL = 72 };
static struct { uint8_t *p; size_t n; int live; } ranges[TOTAL];
static void add_range(int i, uint8_t *p, size_t n) { ranges[i].p=p; ranges[i].n=n; ranges[i].live=1; mtl_pool_add(p,n); }
static void remove_range(int i) { mtl_pool_del(ranges[i].p); ranges[i].live=0; }
static int expected(uintptr_t a,size_t n) {
    for(int i=0;i<TOTAL;i++)if(ranges[i].live && a>=(uintptr_t)ranges[i].p && a+n<=(uintptr_t)ranges[i].p+ranges[i].n)return 1;
    return 0;
}
static void query(uintptr_t a,size_t n) {
    void *buffer=NULL;uint64_t off=0,gpu=0;int want=expected(a,n);
    int found=mtl_addr(a,n,&buffer,&off);CHECK(found==want,"whole-range lookup agrees with live registration oracle");
    if(found)CHECK((uintptr_t)[(__bridge id<MTLBuffer>)buffer contents]+off==a,"CPU buffer and offset identify the requested bytes");
    found=mtl_gpu_addr(a,n,&buffer,&off,&gpu);CHECK(found==want,"GPU lookup agrees with live registration oracle");
    if(found){id<MTLBuffer>b=(__bridge id<MTLBuffer>)buffer;CHECK((uintptr_t)b.contents+off==a && gpu==b.gpuAddress+off,"GPU address uses the returned live buffer and correct offset");}
}
static void cached_reader(uint8_t *extra,size_t page) {
    dispatch_semaphore_t warm=dispatch_semaphore_create(0),held=dispatch_semaphore_create(0),held_main=dispatch_semaphore_create(0);
    dispatch_semaphore_t release=dispatch_semaphore_create(0),read_done=dispatch_semaphore_create(0),write_done=dispatch_semaphore_create(0);
    __block int good=0;uint64_t address=(uintptr_t)ranges[10].p+32;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        void *b=NULL;uint64_t off=0;int first=mtl_addr(address,4,&b,&off);
        dispatch_semaphore_signal(warm);dispatch_semaphore_wait(held,DISPATCH_TIME_FOREVER);
        void *next=NULL;uint64_t noff=0;good=first && mtl_addr(address,4,&next,&noff) && b==next && off==noff;
        dispatch_semaphore_signal(read_done);
    });
    CHECK(!dispatch_semaphore_wait(warm,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)),"reader populates its address cache");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        mtl_pool_add(extra,page);pthread_mutex_lock(&g_mu);dispatch_semaphore_signal(held);dispatch_semaphore_signal(held_main);
        dispatch_semaphore_wait(release,DISPATCH_TIME_FOREVER);pthread_mutex_unlock(&g_mu);dispatch_semaphore_signal(write_done);
    });
    CHECK(!dispatch_semaphore_wait(held_main,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)),"unrelated pool writer reaches the gate");
    long waited=dispatch_semaphore_wait(read_done,dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC));
    dispatch_semaphore_signal(release);
    CHECK(!waited,"adding a disjoint pool does not make a cached reader wait for its writer");
    if(waited)CHECK(!dispatch_semaphore_wait(read_done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)),"baseline reader resumes after the gate opens");
    CHECK(!dispatch_semaphore_wait(write_done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)),"writer releases the gate");CHECK(good,"cached reader retains the same live mapping");
    mtl_pool_del(extra);
}
int main(void) { @autoreleasepool {
    setenv("DM_PSO_MANIFEST","off",1);mtl_init();size_t page=getpagesize(),bytes=(TOTAL+4)*page;
    uint8_t *memory=mmap(NULL,bytes,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);if(memory==MAP_FAILED)return 2;
    for(size_t i=0;i<bytes;i++)memory[i]=(uint8_t)(i/page+1);
    query((uintptr_t)memory,1); // the first lookup is deliberately before any registration
    for(int i=0;i<N;i++){int k=i*37%N;add_range(k,memory+k*page+17,page-34);query((uintptr_t)ranges[k].p+9,32);}
    cached_reader(memory+(N+6)*page,page);
    add_range(N,memory+3,5*page-6);add_range(N+1,memory+12*page+3,2*page-6);
    add_range(N+3,memory+3,5*page-6);add_range(N+4,memory+3,5*page-6);
    remove_range(N+4); // remove one of several equal-start registrations
    query((uintptr_t)memory+page-64,128);query((uintptr_t)memory+20*page-64,128);
    // Hold an old resource while its range is removed and registered again.
    uint8_t *isolated=memory+(N+5)*page;add_range(N+2,isolated,page);void *b=NULL;uint64_t off=0;
    CHECK(mtl_addr((uintptr_t)isolated,4,&b,&off),"isolated range resolves");id<MTLBuffer>old=(__bridge id<MTLBuffer>)b;
    remove_range(N+2);query((uintptr_t)isolated,4);add_range(N+2,isolated,page);
    CHECK(mtl_addr((uintptr_t)isolated,4,&b,&off) && b!=(__bridge void*)old,"address reuse resolves the new registration, not the retired resource");
    uint32_t rng=0x9374ac21;
    for(int step=0;step<512;step++){
        rng=rng*1664525u+1013904223u;int k=(rng>>16)%N;
        if(ranges[k].live)remove_range(k);else add_range(k,memory+k*page+17,page-34);
        for(int j=0;j<24;j++){rng=rng*1664525u+1013904223u;size_t offset=(rng>>4)%(bytes-2*page);rng=rng*1664525u+1013904223u;query((uintptr_t)memory+offset,1+(rng%(2*page)));}
    }
    for(int i=0;i<TOTAL;i++)if(ranges[i].live)remove_range(i);
    query((uintptr_t)memory+page,16);
    mtl_sub_begin();uint64_t fence=mtl_sub_commit();CHECK(mtl_wait(fence,5000000000ull),"empty submission publishes deferred retirement fence");defer_drain();res_commit();
    // The held buffer remains valid until this autorelease scope finishes; its
    // no-copy storage is unmapped only when this test process exits.
    (void)old;
    printf("t_pool_index: %d checks, %d failed\n",checks,fails);return fails!=0;
} }
