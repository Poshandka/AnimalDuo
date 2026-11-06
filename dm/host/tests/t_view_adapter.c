// Closed-form projection/scissor expectations and cache/ABI checks of the
// actual owned ARM64 adapter, independent of any game binary or screenshot.
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdalign.h>
#include <stdlib.h>
struct view_state { char signature[8];float target;uint32_t capable;uint32_t layout;float reference;uint64_t clock,keyboard,board,design,dialog; };
alignas(16) struct view_state dm_view_state={.signature="DMVIEW01"};
extern char test_view_vtable[];
extern float *test_ui_override(void *);
void dm_code_037e5968(void) {}
extern void test_view_matrix(void *,float *);
extern uint32_t test_view_cache(void *,uint64_t *);
extern void test_view_scissor(void *,float *,float,float,float,float);
extern void test_view_capture(void *,float *,float,float,float,float);
extern uint32_t test_view_units(uint32_t *);
extern uint32_t test_view_layout(void *);
extern void dm_view_panel_projection(float *);
extern void dm_view_backdrop(void *,void *,void *);
extern void dm_view_keyboard_frame(void);
extern void dm_view_touch_page(void *);
extern char dm_code_049adc80[],dm_code_049f2b70[];
extern char dm_code_0474de58[];
extern void dm_view_keyboard_window(void *),test_keyboard_window_abi(void *,uint64_t *);
extern int test_footer_match(void *),test_footer_recalc(void *,int);
extern float test_footer_y(void *,float);
static unsigned checks,failures;
#define CHECK(c) do{checks++;if(!(c)){failures++;fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c);}}while(0)
static int closef(float a,float b) { return fabsf(a-b)<=fmaxf(1,fabsf(b))*0.00001f; }
static void putf(void *p,unsigned off,float value) { memcpy((char *)p+off,&value,4); }
static void ptr(void *p,unsigned off,const void *v) { memcpy((char *)p+off,&v,8); }
static void keyboard_dialogs(void) {
    alignas(16) unsigned char panes[6][256],before[sizeof panes];
    const char *names[]={"W_BaseL_01","N_Scale_01","N_Valid_01","L_Btn_00","N_Loop_00","N_Root"};
    const float widths[]={420,30,30,440,30,10},heights[]={120,40,40,224,30,108};
    uint64_t frame=170,registers[28];
    // Single-button validation and both children of the confirmation loop.
    for(int pose=0;pose<3;pose++)for(int bad=-1;bad<31;bad++)for(int capable=0;capable<2;capable++){
        memset(panes,0,sizeof panes);
        for(int i=0;i<6;i++){
            strcpy((char *)panes[i]+0xb0,names[i]);putf(panes[i],0x50,widths[i]);putf(panes[i],0x54,heights[i]);
            ptr(panes[i],0x18,i<5?panes[i+1]:NULL);
        }
        if(!pose)ptr(panes[3],0x18,panes[5]);
        if(pose==2)strcpy((char *)panes[3]+0xb0,"L_Btn_01");
        ptr(panes[0],0,dm_code_0474de58);
        if(bad==0)ptr(panes[0],0,dm_code_049adc80);
        int roles[]={0,1,2,3,5};
        if(bad>=1&&bad<=5)panes[roles[bad-1]][0xb0]='X';
        if(bad>=6&&bad<=10){int i=roles[bad-6];panes[i][0xb0+strlen(names[i])]='X';}
        if(bad>=11&&bad<=14)ptr(panes[bad-11],0x18,NULL);
        if(bad>=15&&bad<=18){int i=(bad-15)/2;putf(panes[i],0x50+4*((bad-15)%2),1);}
        if(bad==19)putf(panes[2],0x50,31);if(bad==20)putf(panes[2],0x54,41);
        if(bad==21)putf(panes[5],0x50,11);if(bad==22)putf(panes[5],0x54,109);
        if(bad==24)panes[4][0xb0]='X';if(bad==25)panes[4][0xb9]='X';
        if(bad==26)putf(panes[4],0x50,31);if(bad==27)putf(panes[4],0x54,31);
        if(bad==28)ptr(panes[4],0x18,NULL);
        if(bad==29)panes[3][0xb7]='2';
        if(bad==30){panes[3][0xb7]='1';ptr(panes[3],0x18,panes[5]);}
        dm_view_state.clock=bad==23?0:(uintptr_t)&frame;
        dm_view_state.capable=capable;dm_view_state.target=capable?21.0f/9:0;
        dm_view_state.keyboard=73;dm_view_state.board=74;dm_view_state.design=75;dm_view_state.dialog=0;
        memcpy(before,panes,sizeof panes);memset(registers,0,sizeof registers);
        test_keyboard_window_abi(panes[0],registers);
        int match=bad==-1 || (!pose&&bad>=24&&bad<=28);
        CHECK(dm_view_state.dialog==(match?171:0));
        CHECK(dm_view_state.keyboard==73&&dm_view_state.board==74&&dm_view_state.design==75);
        CHECK(!memcmp(before,panes,sizeof panes));
        CHECK(registers[0]==(uintptr_t)panes[0]);
        for(unsigned i=1;i<18;i++)CHECK(registers[i]==i*0x101);
        CHECK(registers[18]==0x60000000);
        for(unsigned i=20;i<28;i++)CHECK(registers[i]==0x1212121212121212);
    }
    void *page=dm_code_049adc80;dm_view_state.clock=(uintptr_t)&frame;dm_view_state.dialog=0;dm_view_state.board=0;
    dm_view_touch_page(&page);CHECK(dm_view_state.board==171&&dm_view_state.dialog==0);
    dm_view_state.clock=0;dm_view_state.dialog=0;
    dm_view_state.keyboard=dm_view_state.board=dm_view_state.design=0;
}
extern void dm_view_transition(void *,void *,void *,int);
extern void test_transition_fast(void *,void *,void *);
static void transition_fixture(unsigned char *pane,unsigned char *draw,unsigned char *layout,unsigned char *u,
        const char *layout_name,const char *pane_name,float target,int fast,float sx,float sy,
        float left,float right,float bottom,float top,int width_sign,int height_sign) {
    memset(pane,0,256);memset(draw,0,0x1a0);memset(layout,0,64);memset(u,0x5a,0x230);
    strcpy((char *)pane+0xb0,pane_name);ptr(draw,0xc0,layout);ptr(layout,0x30,layout_name);
    putf(layout,0x28,1920);putf(layout,0x2c,1080);
    const float base=16.0f/9,z=1483.6378173828125f;
    float actual=target>0?target:base,hx=960*fmaxf(1,actual/base),hy=540*fmaxf(1,base/actual);
    float projection[16]={z/hx,0,0,0,0,z/hy,0,0,0,0,-1.000200033f,-2.000200033f,0,0,-1,0};
    float model[12]={sx,0,0,(left+right)/2,0,sy,0,(bottom+top)/2,0,0,1,-z};
    memcpy(draw+0x10,projection,sizeof projection);memcpy(u,projection,sizeof projection);
    memcpy(draw+0x80,model,sizeof model);memcpy(u+0x40,model,sizeof model);
    float width=(right-left)/fabsf(sx)*width_sign,height=(top-bottom)/fabsf(sy)*height_sign;
    putf(pane,0x50,width);putf(pane,0x54,height);
    putf(u,0x210,width*(fast?.5f:1));putf(u,0x214,height*(fast?.5f:1));
    putf(u,0x218,fast?0:-width/2);putf(u,0x21c,fast?0:height/2);
    dm_view_state.capable=1;dm_view_state.target=target;
}
static void transition_bounds(const unsigned char *p,const unsigned char *u,int fast,float *b) {
    float w=*(const float *)(u+0x210),h=*(const float *)(u+0x214);
    float l=*(const float *)(u+0x218),t=*(const float *)(u+0x21c);
    if(fast){w*=2;h*=2;unsigned x=p[0x5b]&3,y=(p[0x5b]>>2)&3;l=x==0?-w/2:x==2?-w:0;t=y==0?h/2:y==2?h:0;}
    float sx=*(const float *)(u+0x40),sy=*(const float *)(u+0x54),tx=*(const float *)(u+0x4c),ty=*(const float *)(u+0x5c);
    float xa=sx*l+tx,xb=sx*(l+w)+tx,ya=sy*t+ty,yb=sy*(t-h)+ty;
    b[0]=fminf(xa,xb);b[1]=fmaxf(xa,xb);b[2]=fminf(ya,yb);b[3]=fmaxf(ya,yb);
}
static void transition_coverage(void) {
    alignas(16) unsigned char pane[256],draw[0x1a0],layout[64],u[0x230],before[0x230];
    const char *layouts[]={"Fade","VideogameFade","WipeCircle","WipePrologue","WipeInterior","WipeInteriorStudio","WipeInteriorCloudIsland","WipeInteriorHotelRoom","WipeInteriorWherearenIslands","WipeHotel","WipeHeart","WipeDream","CloudIslandWipeDream","WipeFes","WipeFesFadeOut","WipeFesCameraSwitching","WipeDemoCameraSwitching","WipeCast","WipeDevice","WipeDeviceLoad","WipeMyDesignExch","WipeOrderWherearenIslands","WipeRemakeAlp","WipeStudy","WipeTidyingMol","WipeVisitorDemo","LWipeTimeEdit"};
    const char *roles[]={"P_Fade_00","P_WipeBG_00","P_WipeFadeOut_00","P_Back_00","P_Base_03","P_L_00","P_RNormal_00","P_Up_00","P_Down_00","P_OutBGS_00","P_PatternL_00"};
    const float boxes[][4]={{-960,960,-540,540},{-988,988,-557,557},{-1012,1024,-594,588},{-1100,-400,-540,540},{400,1100,-540,540},{-960,960,300,750},{-960,960,-750,-300},{-960,-700,-650,650},{-700,-400,-650,650}};
    const float targets[]={0,4.0f/3,669.0f/475.5f,16.0f/9,874.0f/402,3.5f};
    const float colors[][4]={{0,0,0,1},{1,1,1,1},{.25f,.5f,1,.125f},{1,.2f,.4f,.5f}};
    const float base=16.0f/9;
    for(unsigned i=0;i<sizeof layouts/sizeof *layouts;i++)for(unsigned box=0;box<9;box++)for(unsigned target=0;target<6;target++)for(int fast=0;fast<2;fast++)for(int sign=0;sign<4;sign++){
        const float *b=boxes[box];float ratio=targets[target]>0?targets[target]:base;
        transition_fixture(pane,draw,layout,u,layouts[i],roles[(i+box)%11],targets[target],fast,sign&1?-1:1,sign&2?-2:2,b[0],b[1],b[2],b[3],sign&2?-1:1,sign&1?-1:1);
        const float *color=colors[(i+box+target+sign)%4];
        for(int v=0;v<4;v++)memcpy(u+0x1d0+v*16,color,16);
        memcpy(before,u,sizeof u);
        if(fast)test_transition_fast(pane,draw,u);else dm_view_backdrop(pane,draw,u);
        float actual[4];transition_bounds(pane,u,fast,actual);
        float dx=960*fmaxf(0,ratio/base-1),dy=540*fmaxf(0,base/ratio-1);
        float expected[]={b[0]-(b[0]<=-960?dx:0),b[1]+(b[1]>=960?dx:0),b[2]-(b[2]<=-540?dy:0),b[3]+(b[3]>=540?dy:0)};
        for(int edge=0;edge<4;edge++)CHECK(closef(actual[edge],expected[edge]));
        for(unsigned at=0;at<sizeof u;at+=4){
            int changed=fast?(at==0x40||at==0x4c||at==0x54||at==0x5c):(at>=0x210&&at<0x220);
            if(!changed)CHECK(!memcmp(before+at,u+at,4));
        }
        unsigned char once[sizeof u];memcpy(once,u,sizeof u);
        if(fast)test_transition_fast(pane,draw,u);else dm_view_backdrop(pane,draw,u);
        CHECK(!memcmp(once,u,sizeof u));
    }
    // All nine authored origins and zero-area initial curtains use the same
    // world-space outer boundary, including the optimized colour path.
    for(int fast=0;fast<2;fast++)for(int originY=0;originY<3;originY++)for(int originX=0;originX<3;originX++)for(int zero=0;zero<3;zero++){
        float l=zero==1?-1105:-960,r=zero==1?-1105:960,b=zero==2?1105:-540,t=zero==2?1105:540;
        float target=zero==1?874.0f/402:4.0f/3;
        transition_fixture(pane,draw,layout,u,"WipeCircle",zero==2?"P_T_00":"P_L_00",target,fast,1,1,l,r,b,t,1,1);
        pane[0x5b]=originX+4*originY;
        float width=*(float *)(pane+0x50),height=*(float *)(pane+0x54);
        float localLeft=originX==0?-width/2:originX==2?-width:0,localTop=originY==0?height/2:originY==2?height:0;
        float tx=(l+r)/2-(localLeft+width/2),ty=(b+t)/2-(localTop-height/2);
        putf(draw,0x8c,tx);putf(draw,0x9c,ty);putf(u,0x4c,tx);putf(u,0x5c,ty);
        if(!fast){putf(u,0x218,localLeft);putf(u,0x21c,localTop);}
        if(fast)test_transition_fast(pane,draw,u);else dm_view_backdrop(pane,draw,u);
        float actual[4];transition_bounds(pane,u,fast,actual);
        float dx=960*fmaxf(0,target/base-1),dy=540*fmaxf(0,base/target-1);
        const float expected[]={l-(l<=-960?dx:0),r+(r>=960?dx:0),b-(b<=-540?dy:0),t+(t>=540?dy:0)};
        for(int edge=0;edge<4;edge++)CHECK(closef(actual[edge],expected[edge]));
        memcpy(before,u,sizeof u);if(fast)test_transition_fast(pane,draw,u);else dm_view_backdrop(pane,draw,u);CHECK(!memcmp(before,u,sizeof u));
    }
    // Apertures, logos and icons keep their original shape and animation.
    const char *unchanged[]={"P_Circle_00","P_Heart_00","P_SirclePattern_00","P_Mist_00","P_Icon_00","P_Logo_00"};
    for(unsigned i=0;i<sizeof unchanged/sizeof *unchanged;i++)for(int fast=0;fast<2;fast++){
        transition_fixture(pane,draw,layout,u,"WipeHeart",unchanged[i],4.0f/3,fast,1,1,-1400,1400,-1400,1400,1,1);
        memcpy(before,u,sizeof u);if(fast)test_transition_fast(pane,draw,u);else dm_view_backdrop(pane,draw,u);CHECK(!memcmp(before,u,sizeof u));
    }
    // Local, malformed and already stale matrices cannot be promoted to screen coverage.
    for(int bad=0;bad<14;bad++)for(int fast=0;fast<2;fast++){
        transition_fixture(pane,draw,layout,u,"Fade","P_Fade_00",4.0f/3,fast,1,1,-960,960,-540,540,1,1);
        if(bad==0)putf(layout,0x28,1080);if(bad==1)dm_view_state.capable=0;if(bad==2)dm_view_state.target=0;
        if(bad==3)putf(draw,0x24,*(float *)(draw+0x10)*base);
        if(bad==4)putf(draw,0x4c,1);if(bad==5)putf(u,0x4c,1);
        if(bad==6){putf(u,0x44,.1f);putf(draw,0x84,.1f);}
        if(bad==7){putf(u,0x6c,1);putf(draw,0xac,1);}
        if(bad==8){putf(u,0x40,0);putf(draw,0x80,0);}
        if(bad==9){putf(u,0x6c,NAN);putf(draw,0xac,NAN);}
        if(bad==10)putf(u,0x210,32);if(bad==11)putf(u,0x10,1);
        if(bad==12){putf(u,0x40,INFINITY);putf(draw,0x80,INFINITY);}
        if(bad==13){putf(u,0x54,NAN);putf(draw,0x94,NAN);}
        memcpy(before,u,sizeof u);dm_view_transition(pane,draw,u,fast);CHECK(!memcmp(before,u,sizeof u));
    }
    dm_view_state.capable=1;
}

static void screen_backgrounds(void) {
    alignas(16) unsigned char pane[256],draw[0x1a0],layout[64],quad[0x230],expected[sizeof quad];
    const float base=16.0f/9,targets[]={0,4.0f/3,base,874.0f/402,21.0f/9,3.5f};
    const char *names[]={"P_BG_00","P_Tex_00","P_Base_00","P_Dot_00","P_Fade_00"};
    for(unsigned name=0;name<sizeof names/sizeof *names;name++)for(unsigned t=0;t<6;t++)for(unsigned origin=0;origin<=8;origin+=4){
        memset(pane,0,sizeof pane);memset(draw,0,sizeof draw);memset(layout,0,sizeof layout);
        strcpy((char *)pane+0xb0,names[name]);pane[0x5b]=origin;pane[0xf1]=name==4?0:2;
        putf(pane,0x50,1920);putf(pane,0x54,1080);ptr(draw,0xc0,layout);
        putf(layout,0x28,1920);putf(layout,0x2c,1080);float target=targets[t]>0?targets[t]:base;
        putf(draw,0x10,1);putf(draw,0x24,target);draw[0x188]=0;draw[0x189]=255;draw[0x18a]=1;
        memset(quad,0x5a,sizeof quad);putf(quad,0x210,1920);putf(quad,0x214,1080);putf(quad,0x218,-960);putf(quad,0x21c,540);
        for(int slot=0;slot<3;slot++)for(int vertex=0;vertex<4;vertex++){
            putf(quad,0xe0+slot*64+vertex*16,vertex%2?.875f:.125f);
            putf(quad,0xe4+slot*64+vertex*16,vertex/2?.75f:.25f);
        }
        memcpy(expected,quad,sizeof quad);
        float sx=fmaxf(1,target/base),sy=fmaxf(1,base/target);
        putf(expected,0x210,1920*sx);putf(expected,0x214,1080*sy);putf(expected,0x218,-960*sx);putf(expected,0x21c,540*sy);
        for(int slot=0;name!=4&&slot<3;slot+=2)for(int vertex=0;vertex<4;vertex++){
            putf(expected,0xe0+slot*64+vertex*16,.5f+(vertex%2?.375f:-.375f)*sx);
            putf(expected,0xe4+slot*64+vertex*16,.5f+(vertex/2?.25f:-.25f)*sy);
        }
        dm_view_state.capable=1;dm_view_state.target=targets[t];dm_view_backdrop(pane,draw,quad);
        for(unsigned at=0;at<sizeof quad;at+=4){
            if(at>=0x210&&at<0x220)CHECK(closef(*(float *)(quad+at),*(float *)(expected+at)));
            else if((at>=0xe0&&at<0x120)||(at>=0x160&&at<0x1a0))CHECK(closef(*(float *)(quad+at),*(float *)(expected+at)));
            else CHECK(!memcmp(quad+at,expected+at,4));
        }
    }
    // Exact full-screen names and fresh dimensions cannot admit neighbouring
    // widgets, local captures or an already expanded uniform buffer.
    const char *guarded[]={"P_Tex_00","P_Fade_00"};
    for(unsigned name=0;name<sizeof guarded/sizeof *guarded;name++)for(int bad=0;bad<12;bad++){
        strcpy((char *)pane+0xb0,guarded[name]);pane[0x5b]=0;putf(pane,0x50,1920);putf(pane,0x54,1080);
        putf(layout,0x28,1920);putf(layout,0x2c,1080);putf(draw,0x10,1);putf(draw,0x24,21.0f/9);putf(draw,0x4c,0);
        putf(quad,0x210,1920);putf(quad,0x214,1080);dm_view_state.capable=1;dm_view_state.target=21.0f/9;
        if(bad==0)pane[0xb7]='1';if(bad==1)pane[0xb8]='x';if(bad==2)pane[0x5b]=1;if(bad==3)pane[0x5b]=12;
        if(bad==4)putf(pane,0x50,1000);if(bad==5)putf(quad,0x210,2200);if(bad==6)putf(draw,0x4c,1);
        if(bad==7)putf(draw,0x24,base);if(bad==8)putf(draw,0x10,0);if(bad==9)dm_view_state.capable=0;
        if(bad==10)dm_view_state.target=0;if(bad==11){putf(layout,0x28,1080);putf(pane,0x50,1080);putf(quad,0x210,1080);putf(draw,0x24,1);}
        memcpy(expected,quad,sizeof quad);dm_view_backdrop(pane,draw,quad);CHECK(!memcmp(expected,quad,sizeof quad));
    }
}
static void wipe_curtains(void) {
    alignas(16) unsigned char root[256]={0},inout[256]={0},circle[256]={0},side[256]={0},draw[0x1a0]={0},layout[64]={0},quad[0x230],expected[sizeof quad];
    strcpy((char *)root+0xb0,"RootPane");putf(root,0x50,1920);putf(root,0x54,1080);
    putf(inout,0x50,30);putf(inout,0x54,30);ptr(inout,0x18,root);ptr(circle,0x18,inout);ptr(side,0x18,circle);
    putf(side,0x54,1080);ptr(draw,0xc0,layout);putf(layout,0x28,1920);putf(layout,0x2c,1080);
    const float base=16.0f/9,targets[]={0,678.0f/466,669.0f/475.5f,4.0f/3,base,21.0f/9};
    // The original iris animates curtain width and translation independently.
    // Extend outer coverage without moving either edge next to the aperture.
    for(int index=0;index<2;index++)for(int right=0;right<2;right++)for(int phase=0;phase<=4;phase++)for(unsigned i=0;i<sizeof targets/sizeof *targets;i++){
        sprintf((char *)inout+0xb0,"N_InOut_0%d",index);sprintf((char *)circle+0xb0,"P_Circle_0%d",index);sprintf((char *)side+0xb0,"P_%c_0%d",right?'R':'L',index);
        float width=1098.0f*phase/4,target=targets[i],height=1080*(target>0&&target<base?base/target:1);
        putf(side,0x50,width);putf(circle,0x50,2210-width*2);putf(circle,0x54,2210-width*2);side[0x5b]=right?0x21:0x12;
        memset(quad,0x5a,sizeof quad);putf(quad,0x210,width);putf(quad,0x214,1080);putf(quad,0x218,right?0:-width);putf(quad,0x21c,540);
        float extra=target>base?1920*(target/base-1)/2:0;
        memcpy(expected,quad,sizeof quad);putf(expected,0x214,height);putf(expected,0x21c,height/2);
        putf(expected,0x210,width+extra);putf(expected,0x218,right?0:-width-extra);
        putf(draw,0x10,1);putf(draw,0x24,target>0?target:base);dm_view_state.capable=1;dm_view_state.target=target;
        dm_view_backdrop(side,draw,quad);
        CHECK(closef(*(float *)(quad+0x214),height));CHECK(closef(*(float *)(quad+0x21c),height/2));
        if(target>base){
            float left=*(float *)(quad+0x218),actualWidth=*(float *)(quad+0x210);
            CHECK(closef(right?left:left+actualWidth,0));
            CHECK(closef(right?left+actualWidth:left,right?width+extra:-width-extra));
            unsigned char once[sizeof quad];memcpy(once,quad,sizeof quad);
            dm_view_backdrop(side,draw,quad);CHECK(!memcmp(once,quad,sizeof quad));
        }
        memcpy(expected+0x214,quad+0x214,4);memcpy(expected+0x21c,quad+0x21c,4);CHECK(!memcmp(expected,quad,sizeof quad));
    }
    dm_view_state.target=4.0f/3;putf(draw,0x24,4.0f/3);
    for(int bad=0;bad<10;bad++){
        strcpy((char *)side+0xb0,"P_L_00");strcpy((char *)circle+0xb0,"P_Circle_00");strcpy((char *)inout+0xb0,"N_InOut_00");
        putf(root,0x50,1920);putf(side,0x54,1080);putf(inout,0x54,30);putf(draw,0x4c,0);ptr(side,0x18,circle);ptr(draw,0xc0,layout);dm_view_state.capable=1;
        if(bad==0)side[0xb5]='2';if(bad==1)circle[0xba]='1';if(bad==2)inout[0xb9]='1';if(bad==3)circle[0xbb]='x';
        if(bad==4)putf(root,0x50,1280);if(bad==5)putf(side,0x54,600);if(bad==6)putf(inout,0x54,31);
        if(bad==7)putf(draw,0x4c,1);if(bad==8)ptr(side,0x18,NULL);if(bad==9)dm_view_state.capable=0;
        memset(quad,0x5a,sizeof quad);putf(quad,0x214,1080);putf(quad,0x21c,540);memcpy(expected,quad,sizeof quad);
        dm_view_backdrop(side,draw,quad);CHECK(!memcmp(expected,quad,sizeof quad));
    }
    dm_view_state.capable=1;
}
int main(int argc,char **argv) {
    transition_coverage();
    keyboard_dialogs();
    screen_backgrounds();
    wipe_curtains();
    const float base=16.0f/9;alignas(16) unsigned char projection[192]={0},draw[0x1a0]={0},layout[64]={0};float out[2];uint64_t flags=0;
    putf(projection,0xac,.5f);putf(projection,0xb0,base);putf(projection,0xa0,2*atanf(.5f));
    const float targets[]={0,678.0f/466,669.0f/475.5f,4.0f/3,16.0f/9,21.0f/9};
    for(unsigned i=0;i<sizeof targets/sizeof *targets;i++){
        float target=targets[i];dm_view_state.target=target;
        test_view_matrix(projection,out);
        float expected=target>0?target:base,vertical=target>0?fmaxf(1,base/target):1;
        CHECK(closef(out[0],.5f*vertical));CHECK(closef(out[1],expected));
        // World X stays identical while extending Y on a narrower target.
        if(target>0 && target<base)CHECK(closef(out[0]*out[1],.5f*base));
    }
    putf(projection,0xb0,1);dm_view_state.target=4.0f/3;test_view_matrix(projection,out);
    CHECK(out[0]==.5f && out[1]==1);putf(projection,0xb0,base);
    ptr(projection,0,test_view_vtable);putf(projection,0xc,1);putf(projection,0x20,base);
    dm_view_state.capable=0;CHECK(test_view_cache(projection,&flags)==0);
    dm_view_state.capable=1;CHECK(test_view_cache(projection,&flags)==1);
    putf(projection,0x20,dm_view_state.target);CHECK(test_view_cache(projection,&flags)==0);
    dm_view_state.target=0;CHECK(test_view_cache(projection,&flags)==1);
    putf(projection,0x20,base);CHECK(test_view_cache(projection,&flags)==0);
    projection[8]=1;CHECK(test_view_cache(projection,&flags)==1);projection[8]=0;
    ptr(projection,0,NULL);CHECK(test_view_cache(projection,&flags)==0);
    ptr(projection,0,test_view_vtable);putf(projection,0xb0,base+.000001f);dm_view_state.target=4.0f/3;CHECK(test_view_cache(projection,&flags)==0);
    // UI jobs retain a raw override matrix across target changes. Derivation
    // must follow every change without accumulating scale or accepting local captures.
    alignas(16) unsigned char ui[80]={0};float *ui_matrix=(float *)(ui+8);const float ui_x=1.5454561710357666f;
    ui_matrix[0]=ui_x;ui_matrix[5]=ui_x*base;ui_matrix[10]=-1.0002000331878662f;ui_matrix[11]=-2.000200033187866f;ui_matrix[14]=-1;
    dm_view_state.capable=0;dm_view_state.target=4.0f/3;CHECK(test_ui_override(ui)==ui_matrix && ui_matrix[5]==ui_x*base);
    dm_view_state.capable=1;
    for(unsigned round=0;round<3;round++)for(unsigned i=0;i<sizeof targets/sizeof *targets;i++){
        dm_view_state.target=targets[i];test_ui_override(ui);float target=targets[i]>0?targets[i]:base;
        CHECK(closef(ui_matrix[0],ui_x*fminf(1,base/target)));CHECK(closef(ui_matrix[5]/ui_matrix[0],target));
    }
    ui_matrix[0]=ui_x*base/(21.0f/9);ui_matrix[5]=ui_x*base;dm_view_state.target=4.0f/3;test_ui_override(ui);CHECK(closef(ui_matrix[0],ui_x));CHECK(closef(ui_matrix[5]/ui_matrix[0],4.0f/3));
    ui_matrix[0]=ui_matrix[5]=1;test_ui_override(ui);CHECK(ui_matrix[0]==1 && ui_matrix[5]==1);
    ui_matrix[0]=ui_x;ui_matrix[5]=ui_x*base;ui_matrix[15]=1;test_ui_override(ui);CHECK(ui_matrix[5]==ui_x*base);
    ui_matrix[15]=0;ui_matrix[2]=.25f;test_ui_override(ui);CHECK(ui_matrix[5]==ui_x*base);
    ui_matrix[2]=0;ui_matrix[10]=-1;test_ui_override(ui);CHECK(ui_matrix[5]==ui_x*base);
    // A real original-frame counter drives page freshness. Ordinary views have
    // no page stamp, and a stale/future stamp cannot dock a subsequent screen.
    uint64_t frame=100;ptr(&dm_view_state,24,&frame);
    dm_view_keyboard_frame();uint64_t stamp;memcpy(&stamp,(char *)&dm_view_state+32,8);CHECK(stamp==101);
    float matrix[16]={0};matrix[0]=ui_x;matrix[5]=ui_x*base;matrix[10]=-1.0002000331878662f;matrix[11]=-2.000200033187866f;matrix[14]=-1;
    dm_view_state.capable=1;dm_view_state.target=4.0f/3;dm_view_panel_projection(matrix);
    CHECK(closef(matrix[5]/matrix[0],4.0f/3));CHECK(closef(matrix[6],.25f));
    frame=103;matrix[6]=0;dm_view_panel_projection(matrix);CHECK(matrix[6]==0);
    alignas(16) unsigned char page[16]={0};ptr(page,0,dm_code_049adc80);dm_view_touch_page(page);
    memcpy(&stamp,(char *)&dm_view_state+40,8);CHECK(stamp==104);
    matrix[6]=0;dm_view_panel_projection(matrix);CHECK(matrix[6]==0);
    ptr(page,0,dm_code_049f2b70);dm_view_touch_page(page);
    memcpy(&stamp,(char *)&dm_view_state+48,8);CHECK(stamp==0);
    matrix[6]=0;dm_view_state.target=0;dm_view_panel_projection(matrix);CHECK(closef(matrix[5]/matrix[0],base)&&matrix[6]==0);
    // Drawing stays centred; only an actual keyboard docks all screen UI.
    frame=100;dm_view_state.keyboard=0;dm_view_state.board=101;
    matrix[6]=0;dm_view_state.target=4.0f/3;dm_view_panel_projection(matrix);CHECK(matrix[6]==0);
    alignas(16) unsigned char root[256]={0},footer[256]={0},align[256]={0};
    putf(root,0x50,1920);putf(root,0x54,1080);ptr(footer,0x18,root);ptr(footer,0x28,align+8);
    putf(footer,0x50,30);putf(footer,0x54,30);memcpy(footer+0xb0,"N_InOut_00",11);
    putf(align,0x50,1810);putf(align,0x54,100);memcpy(align+0xb0,"N_Align_00",11);
    CHECK(test_footer_match(footer));CHECK(test_footer_recalc(footer,0)==1);
    dm_view_state.capable=0;CHECK(test_footer_recalc(footer,0)==0);CHECK(test_footer_y(footer,-540)==-540);dm_view_state.capable=1;
    CHECK(closef(test_footer_y(footer,-540),-720));CHECK(closef(test_footer_y(footer,-560),-740));
    dm_view_state.target=0;CHECK(test_footer_y(footer,-540)==-540);
    dm_view_state.target=4.0f/3;dm_view_state.keyboard=101;CHECK(test_footer_y(footer,-540)==-540);
    dm_view_state.keyboard=0;putf(align,0x54,99);CHECK(!test_footer_match(footer));CHECK(test_footer_y(footer,-540)==-540);
    putf(align,0x54,100);putf(root,0x50,1280);CHECK(!test_footer_match(footer));
    putf(root,0x50,1920);footer[0xba]='x';CHECK(!test_footer_match(footer));
    footer[0xba]=0;ptr(footer,0x28,footer+0x20);CHECK(!test_footer_match(footer));
    // Independent full-screen quad expectations: 1080 at a 3/4 ratio becomes
    // 1440, with top 900 and bottom -540 for a bottom-docked screen projection.
    alignas(16) unsigned char bg[256]={0},constants[0x230]={0};
    putf(bg,0x50,1920);putf(bg,0x54,1080);bg[0xf1]=3;draw[0x188]=0;draw[0x189]=1;draw[0x18a]=2;memcpy(bg+0xb0,"P_Stripe_00",12);
    ptr(draw,0xc0,layout);putf(layout,0x28,1920);putf(layout,0x2c,1080);putf(draw,0x10,ui_x);putf(draw,0x24,ui_x*(4.0f/3));putf(draw,0x28,.25f);
    putf(constants,0x210,1920);putf(constants,0x214,1080);putf(constants,0x218,-960);putf(constants,0x21c,540);
    for(int set=0;set<3;set++){putf(constants,0xe4+set*64,0);putf(constants,0xf4+set*64,0);putf(constants,0x104+set*64,1);putf(constants,0x114+set*64,1);}
    dm_view_state.target=4.0f/3;dm_view_backdrop(bg,draw,constants);
    float *values=(float *)constants;CHECK(closef(values[0x214/4],1440));CHECK(closef(values[0x21c/4],900));CHECK(closef(values[0xe4/4],-1.0f/6));CHECK(closef(values[0x104/4],7.0f/6));
    // Unpopulated UV slots must retain their sentinel values.
    bg[0xf1]=1;draw[0x188]=0;draw[0x189]=255;draw[0x18a]=2;
    for(int i=0;i<3;i++){putf(constants,0x214,1080);putf(constants,0x21c,540);putf(constants,0xe4+i*64,0);putf(constants,0x104+i*64,1);}
    dm_view_backdrop(bg,draw,constants);CHECK(closef(values[0xe4/4],-1.0f/6));CHECK(values[0x124/4]==0&&values[0x144/4]==1);CHECK(values[0x164/4]==0&&values[0x184/4]==1);
    const char *backgrounds[]={"P_BG_00","P_Bg_00","P_Dot_00","P_ColorBg_00","P_AllBg_00"};
    for(unsigned i=0;i<sizeof backgrounds/sizeof *backgrounds;i++){
        memset(bg+0xb0,0,32);strcpy((char *)bg+0xb0,backgrounds[i]);putf(constants,0x214,1080);putf(constants,0x21c,540);dm_view_backdrop(bg,draw,constants);CHECK(closef(values[0x214/4],1440));
    }
    putf(bg,0x54,600);putf(constants,0x214,600);dm_view_backdrop(bg,draw,constants);CHECK(values[0x214/4]==600);
    ptr(draw,0xc0,layout);putf(layout,0x28,1920);putf(layout,0x2c,1080);
    putf(draw,0x10,1);putf(draw,0x24,base);dm_view_state.target=4.0f/3;
    test_view_scissor(draw,out,1280,720,1920,1080);CHECK(closef(out[0],2.0f/3));CHECK(closef(out[1],2.0f/3));
    putf(draw,0x24,dm_view_state.target);
    test_view_scissor(draw,out,1280,720,1920,1080);CHECK(closef(out[0],2.0f/3));CHECK(closef(out[1],.5f));
    test_view_capture(draw,out,1280,720,1920,1080);CHECK(closef(out[0],2.0f/3));CHECK(closef(out[1],.5f));
    // A square reference/capture is unchanged even with a different global target.
    putf(layout,0x28,1000);putf(layout,0x2c,1000);putf(draw,0x24,1);
    test_view_scissor(draw,out,600,600,1000,1000);CHECK(closef(out[0],.6f));CHECK(closef(out[1],.6f));
    test_view_capture(draw,out,600,600,1000,1000);CHECK(closef(out[0],.6f));CHECK(closef(out[1],.6f));
    // The local orthographic capture must bypass the correction entirely.
    putf(draw,0x4c,1);putf(draw,0x24,.2f);
    test_view_scissor(draw,out,600,600,1000,1000);CHECK(closef(out[0],.6f));CHECK(closef(out[1],.6f));
    test_view_capture(draw,out,600,600,1000,1000);CHECK(closef(out[0],.6f));CHECK(closef(out[1],.6f));
    uint32_t units=2000;dm_view_state.capable=0;CHECK(test_view_units(&units)==2000);
    dm_view_state.capable=1;CHECK(test_view_units(&units)==4000);
    // A matching length and name are insufficient: the whole resource must match.
    unsigned char *resource=calloc(14012,1);memcpy(resource,"FLYT",4);
    uint16_t header=20;memcpy(resource+6,&header,2);uint32_t size=14012,flag=1;memcpy(resource+12,&size,4);memcpy(resource+2908,&flag,4);
    CHECK(test_view_layout(resource)==header);memcpy(&flag,resource+2908,4);CHECK(flag==1);free(resource);
    for(int i=1;i<argc;i++){
        FILE *file=fopen(argv[i],"rb");if(!file)return 2;fseek(file,0,SEEK_END);long length=ftell(file);rewind(file);resource=malloc(length);CHECK(fread(resource,1,length,file)==(size_t)length);fclose(file);
        unsigned offset=length==14012?2908:3292;memcpy(&flag,resource+offset,4);CHECK(flag==1);
        dm_view_state.capable=0;test_view_layout(resource);memcpy(&flag,resource+offset,4);CHECK(flag==1);
        dm_view_state.capable=1;test_view_layout(resource);memcpy(&flag,resource+offset,4);CHECK(flag==0);
        test_view_layout(resource);memcpy(&flag,resource+offset,4);CHECK(flag==0);uint32_t accepted;memcpy(&accepted,&dm_view_state.layout,4);CHECK(accepted==1);free(resource);
    }
    printf("view adapter: %u checks, %u failed\n",checks,failures);return failures?1:0;
}
