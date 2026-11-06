// The frontend may publish geometry before or during background module load.
#include "../hle_view.c"
#include <assert.h>
#include <stdalign.h>
#include "../control_presentation.h"
static _Atomic uint64_t original_frame;
const void *dm_guest_frame_counter(void){return &original_frame;}
static void *writer(void *arg) {
    uintptr_t value=(uintptr_t)arg;const double ratios[]={0,678.0/466,669.0/475.5,2};
    for(int i=0;i<12000;i++)dm_view_target(ratios[(i+value)%4]);return NULL;
}
static void *render_context(void *arg) {
    _Atomic uint64_t *stamp=arg;
    for(uint64_t frame=1;frame<=24000;frame++){
        atomic_store(&original_frame,frame);
        atomic_store(stamp,frame+1);
    }
    return NULL;
}
int main(void) {
    dm_keyboard_controls controls={0};
    assert(dm_keyboard_controls_context(&controls,1));
    assert(!dm_keyboard_controls_context(&controls,9));
    for(int i=0;i<40;i++)assert(!dm_keyboard_controls_context(&controls,1));
    dm_keyboard_controls_touch(&controls,1,0);assert(!dm_keyboard_controls_context(&controls,1));
    dm_keyboard_controls_touch(&controls,9,1);assert(!dm_keyboard_controls_context(&controls,9));
    dm_keyboard_controls_touch(&controls,1,1);assert(dm_keyboard_controls_context(&controls,1));
    assert(!dm_keyboard_controls_context(&controls,9));
    assert(!dm_keyboard_controls_context(&controls,0));
    assert(dm_keyboard_controls_context(&controls,1));
    assert(!dm_keyboard_controls_context(&controls,8));
    alignas(16) uint8_t memory[128]={0};memcpy(memory+32,"DMVIEW01",8);
    float reference=16.0f/9;memcpy(memory+52,&reference,4);
    module_t module={.base=memory,.size=sizeof memory,.ro_off=16,.data_off=96,.view_state_off=32};
    strcpy(module.name,"fixture");strcpy(module.build_id,"00000000000000000000000000000000");
    assert(!dm_view_available());dm_view_device(1);dm_view_target(678.0/466);dm_view_install(&module);
    assert(dm_view_available());float actual;uint32_t bits=atomic_load((_Atomic uint32_t *)(memory+40));memcpy(&actual,&bits,4);
    assert(actual==(float)(678.0/466));assert(atomic_load((_Atomic uint32_t *)(memory+44))==1);
    assert(atomic_load((_Atomic uintptr_t *)(memory+56))==(uintptr_t)&original_frame);
    pthread_t a,b,render;assert(!pthread_create(&render,NULL,render_context,memory+64));
    assert(!pthread_create(&a,NULL,writer,(void *)0));assert(!pthread_create(&b,NULL,writer,(void *)1));
    for(int i=0;i<24000;i++){
        bits=atomic_load((_Atomic uint32_t *)(memory+40));memcpy(&actual,&bits,4);
        assert(actual==0 || actual==(float)(678.0/466) || actual==(float)(669.0/475.5) || actual==2);
        assert((dm_view_touch_context()&~15u)==0);
        float x=.25f,y=.75f;assert(dm_view_touch(&x,&y));
        if(x==.25f){
            int coherent=y==.75f;
            const float narrow[]={(float)(678.0/466),(float)(669.0/475.5)};
            for(unsigned n=0;n<2;n++)for(unsigned bottom=0;bottom<2;bottom++){
                float anchor=bottom?1:.5f;
                coherent|=fabsf(y-(anchor+(.75f-anchor)*reference/narrow[n]))<.00001f;
            }
            assert(coherent);
        }else assert(fabsf(x-(.5f-.25f*2/reference))<.00001f && y==.75f);
    }
    pthread_join(a,NULL);pthread_join(b,NULL);pthread_join(render,NULL);dm_view_target(669.0/475.5);
    bits=atomic_load((_Atomic uint32_t *)(memory+40));memcpy(&actual,&bits,4);assert(actual==(float)(669.0/475.5));
    atomic_store(&original_frame,100);
    atomic_store((_Atomic uint64_t *)(memory+64),101);
    atomic_store((_Atomic uint64_t *)(memory+72),0);
    atomic_store((_Atomic uint64_t *)(memory+80),0);
    atomic_store((_Atomic uint64_t *)(memory+88),101);
    assert(dm_view_touch_context()==9);
    atomic_store((_Atomic uint64_t *)(memory+88),98);assert(dm_view_touch_context()==1);
    atomic_store((_Atomic uint64_t *)(memory+88),102);assert(dm_view_touch_context()==1);
    atomic_store((_Atomic uint64_t *)(memory+64),0);atomic_store((_Atomic uint64_t *)(memory+88),101);
    assert(dm_view_touch_context()==0);
    atomic_store((_Atomic uint64_t *)(memory+64),101);assert(dm_view_touch_context()==9);
    dm_view_target(NAN);assert(dm_view_aspect()==0);dm_view_target(INFINITY);assert(dm_view_aspect()==0);
    dm_view_target(.1);assert(dm_view_aspect()==0);dm_view_target(0);assert(dm_view_aspect()==0);
    dm_view_device(0);assert(atomic_load((_Atomic uint32_t *)(memory+44))==0);
    puts("view state: early publication, concurrent geometry/context updates, invalid geometry and capability reset passed");return 0;
}
