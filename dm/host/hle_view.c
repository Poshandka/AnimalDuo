// Optional guest camera state shared by a registered build and the front end.
#include "dm.h"
#include "front.h"
#include <math.h>
#include <stdatomic.h>

// The profile's view stubs read a single aligned float at +8; zero is the
// original projection. Installation and UI updates are serialized so an early
// geometry request cannot be lost while background module loading completes.
static pthread_mutex_t g_view_mu=PTHREAD_MUTEX_INITIALIZER;
static _Atomic uintptr_t g_view_state;
static _Atomic uint32_t g_view_requested;
static uint32_t g_view_capable;
int dm_view_available(void) { return atomic_load_explicit(&g_view_state,memory_order_acquire)!=0; }
double dm_view_aspect(void) {
    uint32_t bits=atomic_load(&g_view_requested);float f;memcpy(&f,&bits,4);return f;
}
unsigned dm_view_touch_context(void) {
    uintptr_t at=atomic_load_explicit(&g_view_state,memory_order_acquire);
    if(!at)return 0;
    uintptr_t clock=atomic_load((_Atomic uintptr_t *)(at+24));
    if(!clock)return 0;
    uint64_t frame=atomic_load((const _Atomic uint64_t *)clock)+1;
    unsigned result=0;
    for(unsigned i=0;i<3;i++){
        uint64_t seen=atomic_load((_Atomic uint64_t *)(at+32+i*8));
        if(seen && seen<=frame && frame-seen<=2)result|=1u<<i;
    }
    return result;
}
// An opted-in profile keeps native 2D hit rectangles in its original screen
// coordinates. Convert once before both touch and gesture sampling. Extra scene
// coverage outside that rectangle must not become a press on its edge.
int dm_view_touch(float *x,float *y) {
    if(!isfinite(*x)||!isfinite(*y))return 0;
    uintptr_t at=atomic_load_explicit(&g_view_state,memory_order_acquire);
    if(!at || !atomic_load((_Atomic uint32_t *)(at+12)))return 1;
    float reference;memcpy(&reference,(void *)(at+20),4);
    uint32_t bits=atomic_load((_Atomic uint32_t *)(at+8));float target;memcpy(&target,&bits,4);
    if(!isfinite(reference) || !isfinite(target) || reference<=0 || target<=0)return 1;
    // Inline keyboards are docked to the lower edge of the expanded screen.
    // Other 2D interfaces keep their centred canonical rectangle.
    float anchor=target<reference && (dm_view_touch_context()&1)?1:.5f;
    float mapped=anchor+(*y-anchor)*reference/target;
    if(*x<0 || *x>=1 || mapped<0 || mapped>=1)return 0;
    *y=mapped;return 1;
}
static void publish_view_locked(void) {
    uintptr_t at=atomic_load_explicit(&g_view_state,memory_order_acquire);
    if(at){atomic_store((_Atomic uint32_t *)(at+8),atomic_load(&g_view_requested));atomic_store((_Atomic uint32_t *)(at+12),g_view_capable);}
}
void dm_view_target(double aspect) {
    float value=isfinite(aspect)&&aspect>=0.75&&aspect<=3.5?(float)aspect:0;uint32_t bits;memcpy(&bits,&value,4);
    pthread_mutex_lock(&g_view_mu);atomic_store(&g_view_requested,bits);publish_view_locked();pthread_mutex_unlock(&g_view_mu);
}
void dm_view_device(int capable) {
    pthread_mutex_lock(&g_view_mu);g_view_capable=capable!=0;publish_view_locked();pthread_mutex_unlock(&g_view_mu);
}
void dm_view_install(module_t *m) {
    uint64_t off=m->view_state_off;
    if(off%16 || off<m->ro_off || off>m->data_off || m->data_off-off<64 || off>m->size || m->size-off<64 || memcmp(m->base+off,"DMVIEW01",8))die("%s: invalid view-adapter state",m->name);
    pthread_mutex_lock(&g_view_mu);
    if(atomic_load(&g_view_state))die("multiple view-adapter state blocks");
    atomic_store((_Atomic uintptr_t *)(m->base+off+24),(uintptr_t)dm_guest_frame_counter());
    atomic_store_explicit(&g_view_state,(uintptr_t)(m->base+off),memory_order_release);publish_view_locked();pthread_mutex_unlock(&g_view_mu);
    LOG("%s: adaptive-view adapter registered (build %s)",m->name,m->build_id);
}
void dm_view_state_apply(void) {
    const char *text=getenv("DM_VIEW_ASPECT");
    if(text){char *end;double aspect=strtod(text,&end);if(end==text || *end || !isfinite(aspect) || aspect<0.75 || aspect>3.5){LOG("[RED] DM_VIEW_ASPECT must be a ratio between 0.75 and 3.5");aspect=0;}dm_view_device(aspect>0);dm_view_target(aspect);}
    if(dm_view_aspect()>0)LOG("adaptive view: requested aspect %.6f, adapter %s",dm_view_aspect(),dm_view_available()?"available":"unavailable; original projection retained");
}
