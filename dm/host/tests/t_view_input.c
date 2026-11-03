// The real camera state and HID sampler agree with displayed 2D touch targets.
#include "../hle_view.c"
#include <assert.h>
#include <stdalign.h>
int touch_fill(void *,uint64_t);
int gesture_fill(void *,int,uint64_t);
static int32_t read32(const void *b,int offset){int32_t v;memcpy(&v,(const char *)b+offset,4);return v;}
static _Atomic uint64_t original_frame;
const void *dm_guest_frame_counter(void){return &original_frame;}
int main(void){
    alignas(16) uint8_t state[64]={0};memcpy(state,"DMVIEW01",8);float reference=16.0f/9;memcpy(state+20,&reference,4);
    module_t m={.base=state,.size=64,.ro_off=0,.data_off=64,.view_state_off=0};strcpy(m.name,"fixture");dm_view_install(&m);dm_view_device(1);dm_view_target(4.0/3);
    dm_touch point={2,.25f,.78125f};uint8_t sample[0x290],gesture[0x60];
    dm_touch_set(&point,1);assert(touch_fill(sample,1000000000)==1);assert(read32(sample,0x20)==320 && read32(sample,0x24)==630);assert(point.y==.78125f);
    assert(gesture_fill(gesture,1,1000000000)==1);assert(read32(gesture,0x18)==320 && read32(gesture,0x1c)==630);
    dm_touch_set(NULL,0);assert(touch_fill(sample,1020000000)==1 && read32(sample,0x18)==2);assert(touch_fill(sample,1040000000)==0);
    point.y=0;dm_touch_set(&point,1);assert(touch_fill(sample,1060000000)==0);
    dm_view_target(0);dm_touch_set(&point,1);assert(touch_fill(sample,1080000000)==1 && read32(sample,0x24)==0);dm_touch_set(NULL,0);touch_fill(sample,1100000000);
    dm_view_target(4.0/3);dm_view_device(0);point.y=.78125f;dm_touch_set(&point,1);assert(touch_fill(sample,1120000000)==1 && read32(sample,0x24)==562);
    assert(dm_view_touch_context()==0);
    dm_view_device(1);atomic_store(&original_frame,50);atomic_store((_Atomic uint64_t *)(state+32),51);
    assert(dm_view_touch_context()==1);
    // A canonical key at y=.875 is shown at .90625 by bottom docking.
    dm_touch_set(NULL,0);touch_fill(sample,1140000000);touch_fill(sample,1160000000);
    point.y=.90625f;dm_touch_set(&point,1);assert(touch_fill(sample,1180000000)==1 && read32(sample,0x24)==630);
    assert(gesture_fill(gesture,1,1180000000)==1 && read32(gesture,0x1c)==630);
    atomic_store(&original_frame,52);assert(dm_view_touch_context()==1);
    atomic_store(&original_frame,53);assert(dm_view_touch_context()==0);
    atomic_store((_Atomic uint64_t *)(state+40),54);assert(dm_view_touch_context()==2);
    atomic_store((_Atomic uint64_t *)(state+32),55);assert(dm_view_touch_context()==2); // future stamps are not accepted
    point.y=.78125f;float x=point.x,y=point.y;assert(dm_view_touch(&x,&y)&&fabsf(y-.875f)<.00001f);
    atomic_store((_Atomic uint64_t *)(state+48),54);assert(dm_view_touch_context()==6);
    x=point.x;y=point.y;assert(dm_view_touch(&x,&y)&&fabsf(y-.875f)<.00001f);
    puts("view input: canonical keyboard coordinates, coherent gestures, edge rejection and disabled passthrough passed");return 0;
}
