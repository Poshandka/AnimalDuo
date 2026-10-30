// The bridge reads only published guest ranges and tolerates concurrent unmapping.
#include "../hle_companion.c"
#include "../companion_layout.h"
#include "../control_presentation.h"
#include <sys/mman.h>
#include <assert.h>
module_t g_mod[MAX_MOD];
int g_nmod;
int dm_guest_transaction(int (*body)(void *),void *context) { return body(context); }
static uint64_t heap_begin, heap_end;
void dm_guest_heap_bounds(uint64_t *begin,uint64_t *end) { *begin=heap_begin;*end=heap_end; }
int main(void) {
    dm_companion_guest g;
    assert(!dm_companion_guest_info(&g));
    size_t size=(size_t)getpagesize();
    void *p=mmap(NULL,size,PROT_READ|PROT_WRITE,MAP_ANON|MAP_PRIVATE,-1,0);assert(p!=MAP_FAILED);
    strcpy(g_mod[0].name,"main");strcpy(g_mod[0].build_id,"ff1d1c05670db6021c85b624a710b963");
    g_mod[0].base=p;g_mod[0].size=size;g_nmod=1;
    heap_begin=(uintptr_t)p;heap_end=heap_begin+size;
    assert(!dm_companion_guest_read((uintptr_t)p,&g,1));
    dm_companion_host_ready();assert(dm_companion_guest_info(&g));
    assert(g.title_id==DM_GAME_PROGRAM_ID && !strcmp(g.build_id,g_mod[0].build_id));
    assert(g.main_base==(uintptr_t)p && g.main_size==size);
    memcpy(p,"guest data",11);char buf[11]={0};
    assert(dm_companion_guest_read((uintptr_t)p,buf,sizeof buf) && !strcmp(buf,"guest data"));
    assert(!dm_companion_guest_mapped(UINT64_MAX-1,8));
    assert(!dm_companion_guest_mapped((uintptr_t)p+size,1));
    assert(!dm_companion_guest_mapped((uintptr_t)p+size-1,2));
    assert(!dm_companion_guest_mapped(0,1));assert(!dm_companion_guest_mapped((uintptr_t)p,0));
    assert(!dm_companion_guest_read((uintptr_t)p,NULL,1));
    const char expected[]="guest", replacement[]="Guest";
    dm_companion_write_op ops[2]={{(uintptr_t)p,5,expected,replacement},{(uintptr_t)p+6,4,"data","save"}};
    assert(dm_companion_guest_write_batch(ops,2));assert(!memcmp(p,"Guest save",10));
    assert(!dm_companion_guest_write_batch(ops,2));assert(!memcmp(p,"Guest save",10));
    ops[0]=(dm_companion_write_op){(uintptr_t)p,5,replacement,expected};ops[1].expect="bad!";
    assert(!dm_companion_guest_write_batch(ops,2));assert(!memcmp(p,"Guest save",10));
    assert(!dm_companion_guest_write_batch(ops,33));
    ops[1]=ops[0];assert(!dm_companion_guest_write_batch(ops,2));
    assert(!mprotect(p,size,PROT_READ));assert(!dm_companion_guest_write_batch(ops,1));
    assert(!munmap(p,size));
    assert(!dm_companion_guest_read((uintptr_t)p,buf,1)); // Range metadata can race a guest decommit.
    const CGRect safe[]={CGRectMake(0,24,1024,1322),CGRectMake(0,24,834,1150),CGRectMake(8,30,728,1080),CGRectMake(0,0,500,700)};
    for(unsigned i=0;i<sizeof safe/sizeof *safe;i++){
        dm_companion_layout l=dm_companion_screen_layout(safe[i],1,1);
        assert(CGRectContainsRect(safe[i],l.game) && CGRectContainsRect(safe[i],l.panel));
        assert(CGRectGetMaxY(l.game)<=CGRectGetMinY(l.panel));
        assert(fabs(l.game.size.width/l.game.size.height-16.0/9.0)<1e-9);
        assert(CGRectContainsRect(l.panel,l.controls));
        assert(fabs(CGRectGetMaxY(l.panel)-CGRectGetMaxY(l.controls)-dm_companion_footer_height(l.panel.size))<1e-9);
        assert(CGRectGetMinY(l.panel)==CGRectGetMinY(l.controls));
        assert(CGRectGetMinX(l.panel)==CGRectGetMinX(safe[i]) && l.panel.size.width==safe[i].size.width);
        assert(CGRectContainsRect(l.controls,l.left) && CGRectContainsRect(l.controls,l.right));
        assert(CGRectContainsRect(l.panel,l.left) && CGRectContainsRect(l.panel,l.right));
        dm_companion_pad_layout p=dm_companion_pad_geometry(l.controls.size);
        const CGPoint left[]={p.stick,p.dpad,p.shoulder[0],p.shoulder[1],p.click[0],p.menu[0],p.swap};
        const CGPoint right[]={p.face,p.right_stick,p.shoulder[2],p.shoulder[3],p.click[1],p.menu[1]};
        for(unsigned k=0;k<sizeof left/sizeof *left;k++)assert(CGRectContainsPoint(p.left,left[k]));
        for(unsigned k=0;k<sizeof right/sizeof *right;k++)assert(CGRectContainsPoint(p.right,right[k]));
        assert(!dm_companion_pad_contains(l.controls.size,CGPointMake(l.controls.size.width/2,l.controls.size.height/2)));
        assert(dm_companion_pad_contains(l.controls.size,p.stick) && dm_companion_pad_contains(l.controls.size,p.face));
        assert(p.face.x-p.face_gap-p.face_r>=p.right.origin.x);
        assert(p.face.x+p.face_gap+p.face_r<=CGRectGetMaxX(p.right));
        assert(p.stick.x-p.stick_r>=0 && p.stick.x+p.stick_r<=p.left.size.width);
        assert(CGRectGetMaxY(l.controls)<CGRectGetMaxY(safe[i]));
        assert(p.menu[0].y+p.menu_size.height/2<l.controls.size.height);
        assert(p.dpad.y+p.dpad_r<l.controls.size.height && p.right_stick.y+p.right_r<l.controls.size.height);
        assert(!CGRectIntersectsRect(l.game,l.controls));
        dm_companion_layout pad=dm_companion_screen_layout(safe[i],1,0);
        assert(CGRectIsEmpty(pad.controls) && CGRectEqualToRect(pad.panel,l.panel) && CGRectEqualToRect(pad.game,l.game));
        dm_companion_layout wide=dm_companion_screen_layout(safe[i],0,1);
        assert(CGRectIsEmpty(wide.panel) && CGRectIsEmpty(wide.controls));
        assert(CGRectContainsRect(safe[i],wide.game));
        assert(fabs(wide.game.size.width/wide.game.size.height-16.0/9.0)<1e-9);
    }
    assert(CGRectIsEmpty(dm_companion_screen_layout(CGRectMake(0,0,0,800),1,1).panel));
    assert(CGRectIsEmpty(dm_companion_screen_layout(CGRectMake(0,0,NAN,800),1,1).panel));
    // Overlapping operations must keep controls away until every operation completes.
    dm_companion_control_state c={0};
    assert(!dm_companion_control_hidden(&c,1,0,0));
    assert(dm_companion_control_activity(&c,DM_UI_TOUCH,1,1));
    assert(dm_companion_control_hidden(&c,1,0,1));
    assert(!dm_companion_control_activity(&c,DM_UI_TOUCH,1,1.2));
    assert(dm_companion_control_activity(&c,DM_UI_MODE,1,1.3));
    assert(dm_companion_control_activity(&c,DM_UI_TOUCH,0,2));
    assert(dm_companion_control_hidden(&c,1,0,10));
    assert(dm_companion_control_activity(&c,DM_UI_NATIVE,1,10));
    assert(dm_companion_control_activity(&c,DM_UI_MODE,0,11));
    assert(dm_companion_control_hidden(&c,1,0,20));
    assert(dm_companion_control_activity(&c,DM_UI_NATIVE,0,20));
    assert(dm_companion_control_hidden(&c,1,0,21.09));
    assert(!dm_companion_control_hidden(&c,1,0,21.11));
    assert(!dm_companion_control_activity(&c,8,1,22));
    assert(dm_companion_control_hidden(&c,0,0,100) && dm_companion_control_hidden(&c,1,1,100));
    // Auto fade changes only presentation; a held virtual input remains owned by UIKit.
    dm_control_fade f={0};dm_control_fade_event(&f,1,1);
    assert(!dm_control_fade_hidden(&f,8.99));assert(dm_control_fade_hidden(&f,9));assert(f.active);
    dm_control_fade_event(&f,0,10);assert(dm_control_fade_hidden(&f,11.49));
    assert(!dm_control_fade_hidden(&f,11.5) && !f.session);
    dm_control_fade_event(&f,1,12);dm_control_fade_event(&f,0,12.1);
    dm_control_fade_event(&f,1,13);assert(!dm_control_fade_hidden(&f,19.99));
    assert(dm_control_fade_hidden(&f,20));
    f.mode=1;assert(!dm_control_fade_hidden(&f,30));
    f.mode=2;assert(dm_control_fade_hidden(&f,30));
    puts("companion: guest bounds, full portrait geometry, overlay lifecycle and timed artwork passed");return 0;
}
