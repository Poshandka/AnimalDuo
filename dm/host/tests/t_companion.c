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
    const CGRect safe[]={CGRectMake(0,24,1024,1322),CGRectMake(0,24,834,1150),CGRectMake(8,30,728,1080),CGRectMake(0,0,500,700),
        CGRectMake(0,59,393,759),CGRectMake(0,62,402,778),CGRectMake(0,59,430,839),CGRectMake(0,20,375,647)};
    for(unsigned i=0;i<sizeof safe/sizeof *safe;i++){
        dm_companion_layout l=dm_companion_screen_layout(safe[i],safe[i],1,1);
        assert(CGRectContainsRect(safe[i],l.game) && CGRectContainsRect(safe[i],l.panel));
        assert(CGRectGetMaxY(l.game)<=CGRectGetMinY(l.panel));
        assert(fabs(l.game.size.width/l.game.size.height-16.0/9.0)<1e-9);
        assert(CGRectContainsRect(l.panel,l.controls));
        dm_companion_surface_layout surface=dm_companion_surface_make(l.panel.size,1);
        assert(fabs(CGRectGetMaxY(l.panel)-CGRectGetMaxY(l.controls)-
                    surface.footer.size.height-dm_companion_footer_gap(l.panel.size))<1e-9);
        assert(CGRectGetMinY(l.panel)==CGRectGetMinY(l.controls));
        assert(CGRectGetMinX(l.panel)==CGRectGetMinX(safe[i]) && l.panel.size.width==safe[i].size.width);
        assert(CGRectContainsRect(l.controls,l.left) && CGRectContainsRect(l.controls,l.right));
        assert(CGRectContainsRect(l.panel,l.left) && CGRectContainsRect(l.panel,l.right));
        dm_companion_pad_layout p=dm_companion_pad_geometry(l.controls.size);
        for(int right=0;right<2;right++){
            CGRect group=dm_companion_pad_group(p,right),rail=right?p.right:p.left;
            assert(fabs(CGRectGetMidX(group)-CGRectGetMidX(rail))<1e-9);
            assert(fabs(CGRectGetMidY(group)-CGRectGetMidY(rail))<1e-9);
            assert(CGRectContainsRect(rail,group));
        }
        const CGPoint left[]={p.stick,p.dpad,p.shoulder[0],p.shoulder[1],p.click[0],p.menu[0],p.swap};
        const CGPoint right[]={p.face,p.right_stick,p.shoulder[2],p.shoulder[3],p.click[1],p.menu[1]};
        for(unsigned k=0;k<sizeof left/sizeof *left;k++)assert(CGRectContainsPoint(p.left,left[k]));
        for(unsigned k=0;k<sizeof right/sizeof *right;k++)assert(CGRectContainsPoint(p.right,right[k]));
        assert(!dm_companion_pad_contains(l.controls.size,CGPointMake(l.controls.size.width/2,l.controls.size.height/2)));
        assert(dm_companion_pad_contains(l.controls.size,p.stick) && dm_companion_pad_contains(l.controls.size,p.face));
        assert(p.face.x-p.face_gap*p.face_x_scale-p.face_r>=p.right.origin.x);
        assert(p.face.x+p.face_gap*p.face_x_scale+p.face_r<=CGRectGetMaxX(p.right));
        assert(p.stick.x-p.stick_r>=CGRectGetMinX(p.left) && p.stick.x+p.stick_r<=CGRectGetMaxX(p.left));
        assert(CGRectGetMaxY(l.controls)<CGRectGetMaxY(safe[i]));
        assert(p.menu[0].y+p.menu_size.height/2<l.controls.size.height);
        assert(p.dpad.y+p.dpad_r<l.controls.size.height && p.right_stick.y+p.right_r<l.controls.size.height);
        if(safe[i].size.width>=375 && safe[i].size.width<=440){
            assert(p.face_r>0 && p.stick_r>0 && p.click_r>0);
            // Compact artwork fits its reserved column; the menu keeps its
            // separate minimum target without borrowing from the content.
            assert(dm_companion_pad_menu_hit(p,0).size.height>=44);
            assert(p.shoulder[1].x-p.shoulder[0].x>p.shoulder_r*2*1.35);
        }
        assert(!CGRectIntersectsRect(l.game,l.controls));
        dm_companion_layout pad=dm_companion_screen_layout(safe[i],safe[i],1,0);
        assert(CGRectIsEmpty(pad.controls) && CGRectEqualToRect(pad.panel,l.panel) && CGRectEqualToRect(pad.game,l.game));
        dm_companion_layout wide=dm_companion_screen_layout(safe[i],safe[i],0,1);
        assert(CGRectIsEmpty(wide.panel) && CGRectIsEmpty(wide.controls));
        assert(CGRectContainsRect(safe[i],wide.game));
        assert(fabs(wide.game.size.width/wide.game.size.height-16.0/9.0)<1e-9);
    }
    CGRect full=CGRectMake(0,0,669,951),inset=CGRectMake(22,44,630,873);
    dm_companion_layout modes[]={dm_companion_fold_layout(full,inset,1,1),
                                dm_companion_screen_layout(full,inset,1,1)};
    for(unsigned i=0;i<sizeof modes/sizeof *modes;i++){
        dm_companion_layout l=modes[i];
        assert(CGRectGetMaxY(l.panel)==CGRectGetMaxY(full) && l.panel.size.width==full.size.width);
        assert(l.dock.left==22 && l.dock.right==17 && l.dock.bottom==34);
        dm_companion_surface_layout s=dm_companion_surface_make_safe(l.panel.size,1,l.dock);
        assert(CGRectGetMaxY(s.footer)==l.panel.size.height);
        CGFloat gesture_edge=l.panel.size.height-CGRectGetMaxY(s.nav_controls);
        assert(gesture_edge>=8 && gesture_edge<=11);
        assert(fabs(CGRectGetMidY(s.nav_art)-CGRectGetMidY(s.footer))<1e-7);
        assert(CGRectContainsRect(CGRectInset(s.nav_controls,-1e-7,-1e-7),s.nav_art));
        assert(CGRectGetMinX(s.nav_controls)>=22 && CGRectGetMaxX(s.nav_controls)<=652+1e-7);
        assert(s.nav_controls.size.height>=44);
        assert(CGRectGetMaxY(l.controls)==l.panel.origin.y+CGRectGetMaxY(s.body));
        assert(!CGRectIntersectsRect(s.body,s.nav_controls));
    }
    const CGSize panels[]={{375,538},{402,552},{469,334.5},{669,475.5},{834,690},{1024,750}};
    for(unsigned i=0;i<sizeof panels/sizeof *panels;i++){
        dm_companion_surface_layout s=dm_companion_surface_make(panels[i],1);
        assert(s.footer.size.width==panels[i].width && CGRectGetMaxY(s.footer)==panels[i].height);
        CGFloat gap=dm_companion_footer_gap(panels[i]);
        assert(gap>0 && fabs(CGRectGetMinY(s.footer)-CGRectGetMaxY(s.body)-gap)<1e-9);
        assert(CGRectGetMaxY(s.left)==CGRectGetMaxY(s.body) && CGRectGetMaxY(s.right)==CGRectGetMaxY(s.body));
        assert(!CGRectIntersectsRect(s.left,s.content) && !CGRectIntersectsRect(s.right,s.content));
        CGRect authored=CGRectMake(s.body_offset.x,s.body_offset.y,1240*s.body_scale,968*s.body_scale);
        assert(CGRectContainsRect(CGRectInset(s.content,-1e-7,-1e-7),authored));
        assert(fabs(CGRectGetMidY(authored)-CGRectGetMidY(s.content))<1e-7);
        assert(fabs(CGRectGetMidY(s.nav_art)-CGRectGetMidY(s.footer))<1e-7);
        dm_companion_pad_layout p=dm_companion_pad_geometry_regions(s.body.size,1,s.left,s.right);
        for(int side=0;side<2;side++){
            CGRect box=dm_companion_pad_group(p,side),frame=side?s.right:s.left;
            assert(CGRectContainsRect(CGRectInset(frame,-1e-7,-1e-7),box));
            assert(!CGRectIntersectsRect(box,s.content));
            assert(fabs(CGRectGetMidX(box)-CGRectGetMidX(frame))<1e-7 && fabs(CGRectGetMidY(box)-CGRectGetMidY(frame))<1e-7);
        }
        dm_companion_surface_layout unreserved=dm_companion_surface_make(panels[i],0);
        assert(CGRectEqualToRect(unreserved.body,unreserved.content));
        assert(CGRectEqualToRect(unreserved.body,s.body) && CGRectEqualToRect(unreserved.footer,s.footer));
        assert(fabs(unreserved.body_scale-fmin(panels[i].width/1240,unreserved.body.size.height/968))<1e-9);
    }
    const CGFloat widths[]={375,393,402,430,469,500,669,768,834,1024},heights[]={250,280,300,414,600,900};
    const CGFloat scales[]={.65,.8,1,1.1,1.2,1.3,1.35};
    for(unsigned i=0;i<sizeof widths/sizeof *widths;i++)for(unsigned j=0;j<sizeof heights/sizeof *heights;j++)for(unsigned k=0;k<sizeof scales/sizeof *scales;k++){
        CGSize size=CGSizeMake(widths[i],heights[j]);
        dm_companion_pad_layout p=dm_companion_pad_geometry_scaled(size,scales[k]);
        dm_companion_pad_layout standard=dm_companion_pad_geometry(size);
        assert(fabs(p.stick_r-standard.stick_r*scales[k])<1e-7);
        assert(fabs(p.right_r-standard.right_r*scales[k])<1e-7);
        assert(fabs(p.knob_r-standard.knob_r*scales[k])<1e-7);
        assert(p.stick_r<=dm_companion_pad_stick_extent(p,0));
        assert(p.right_r<=dm_companion_pad_stick_extent(p,1));
        assert(fabs((p.menu[0].y-p.stick.y)-(p.dpad.y-p.menu[0].y))<1e-7);
        assert(fabs((p.dpad.y-p.menu[0].y)-(p.click[0].y-p.dpad.y))<1e-7);
        assert(fabs((p.right_stick.y-p.menu[1].y)-(p.click[1].y-p.right_stick.y))<1e-7);
        if(k){
            dm_companion_pad_layout previous=dm_companion_pad_geometry_scaled(size,scales[k-1]);
            assert(p.face_r>previous.face_r && p.dpad_r>previous.dpad_r);
            assert(p.shoulder_r>previous.shoulder_r && p.click_r>previous.click_r);
            assert(p.menu_size.width>previous.menu_size.width && p.menu_size.height>previous.menu_size.height);
        }
        assert(p.face_x_scale>1.01 && p.face_x_scale<=1.12);
        assert(p.face_y_scale>=1.30 && p.face_y_scale<=1.35);
        assert(p.face_gap*hypot(p.face_x_scale,p.face_y_scale)-2*p.face_r>2.5);
        assert(p.face_hit_r>M_SQRT1_2*p.face_gap); // Adjacent targets still meet at their midpoint.
        CGRect face_box=dm_companion_pad_face_box(p);
        assert(CGRectContainsRect(CGRectInset(dm_companion_pad_face_region(p),-1e-7,-1e-7),face_box));
        assert(CGRectGetMinX(face_box)-CGRectGetMinX(p.right)>=1.49);
        assert(CGRectGetMinY(face_box)>=p.shoulder[2].y+dm_companion_pad_shoulder_extent(p)+5.99);
        assert(p.face_r<=p.face_hit_r && p.click_r<=p.click_hit_r+1e-7);
        assert(p.dpad_r*hypot(1,(double)DM_COMPANION_DPAD_ARM_WIDTH/DM_COMPANION_DPAD_RADIUS)<=p.dpad_hit_r+1e-7);
        assert(1.45*M_SQRT1_2*p.shoulder_r<=dm_companion_pad_shoulder_extent(p));
        assert(p.menu_size.width<=p.menu_hit_size.width && p.menu_size.height<=p.menu_hit_size.height);
        for(int side=0;side<2;side++){
            CGRect box=dm_companion_pad_group(p,side),region=side?dm_companion_pad_face_region(p):dm_companion_pad_region(p,0);
            CGRect rail=side?p.right:p.left;
            if(!CGRectContainsRect(CGRectInset(region,-1e-7,-1e-7),box))fprintf(stderr,"rail fit %.0fx%.0f scale %.2f side %d: unit %g box %g %g %g %g region %g %g %g %g\n",widths[i],heights[j],scales[k],side,p.unit,box.origin.x,box.origin.y,box.size.width,box.size.height,region.origin.x,region.origin.y,region.size.width,region.size.height);
            assert(CGRectContainsRect(CGRectInset(region,-1e-7,-1e-7),box));
            assert(fabs(CGRectGetMidX(box)-CGRectGetMidX(rail))<1e-7 && fabs(CGRectGetMidY(box)-CGRectGetMidY(rail))<1e-7);
            assert(dm_companion_pad_menu_hit(p,side).size.height>=44);
            CGPoint lower=side?p.right_stick:p.dpad;
            CGFloat extent=side?dm_companion_pad_stick_extent(p,1):p.dpad_hit_r;
            CGPoint upper=side?p.face:p.stick;
            CGFloat upper_extent=side?(p.face_gap+p.face_hit_r)*p.face_y_scale:dm_companion_pad_stick_extent(p,0);
            assert(CGRectGetMinY(dm_companion_pad_menu_hit(p,side))>=upper.y+upper_extent+5.99);
            assert(CGRectGetMaxY(dm_companion_pad_menu_hit(p,side))<=lower.y-extent-5.99);
            CGFloat click_top=p.click[side].y-p.click_hit_r;
            CGFloat click_bottom=p.click[side].y+p.click_hit_r;
            assert(click_top>=lower.y+extent+5.99);
            assert(CGRectGetMaxY(rail)-click_bottom>=fmin(24,rail.size.height*.06)-1e-7);
        }
    }
    assert(CGRectIsEmpty(dm_companion_screen_layout(full,CGRectMake(0,0,0,800),1,1).panel));
    assert(CGRectIsEmpty(dm_companion_screen_layout(full,CGRectMake(0,0,NAN,800),1,1).panel));
    // Reserved portrait rails stay available; only presentation and explicit
    // controller/direct-touch choices can hide them.
    for(int mode=0;mode<3;mode++){
        assert(dm_companion_control_hidden(1,0,mode)==(mode==2));
        assert(dm_companion_control_hidden(0,0,mode));
        assert(dm_companion_control_hidden(1,1,mode));
    }
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
    dm_game_touch_controls screen={0};
    assert(!dm_game_touch_hidden(&screen,0,1));
    assert(dm_game_touch_hidden(&screen,2,1)); // Manual direct touch has no hidden hit regions.
    assert(dm_game_touch_activity(&screen,1,2));
    assert(dm_game_touch_hidden(&screen,0,100) && dm_game_touch_hidden(&screen,1,100));
    assert(!dm_game_touch_activity(&screen,1,100)); // Motion does not restart visibility timers.
    assert(dm_game_touch_activity(&screen,0,101));
    assert(dm_game_touch_hidden(&screen,0,102.09));
    assert(!dm_game_touch_hidden(&screen,0,102.11));
    assert(dm_game_touch_activity(&screen,1,103));
    assert(dm_game_touch_activity(&screen,0,103.2));
    assert(dm_game_touch_activity(&screen,1,104)); // The old release must not reveal controls mid-stroke.
    assert(dm_game_touch_hidden(&screen,0,104.4));
    puts("companion: guest bounds, full portrait geometry, overlay lifecycle and timed artwork passed");return 0;
}
