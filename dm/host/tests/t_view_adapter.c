// Closed-form projection/scissor expectations and cache/ABI checks of the
// actual owned ARM64 adapter, independent of any game binary or screenshot.
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdalign.h>
#include <stdlib.h>
struct view_state { char signature[8];float target;uint32_t capable;uint32_t layout;float reference;uint64_t clock,keyboard,board,design,reserved; };
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
extern int test_footer_match(void *),test_footer_recalc(void *,int);
extern float test_footer_y(void *,float);
static unsigned checks,failures;
#define CHECK(c) do{checks++;if(!(c)){failures++;fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c);}}while(0)
static int closef(float a,float b) { return fabsf(a-b)<=fmaxf(1,fabsf(b))*0.00001f; }
static void putf(void *p,unsigned off,float value) { memcpy((char *)p+off,&value,4); }
static void ptr(void *p,unsigned off,const void *v) { memcpy((char *)p+off,&v,8); }
static void wipe_curtains(void) {
    alignas(16) unsigned char root[256]={0},inout[256]={0},circle[256]={0},side[256]={0},draw[0x1a0]={0},layout[64]={0},quad[0x230],expected[sizeof quad];
    strcpy((char *)root+0xb0,"RootPane");putf(root,0x50,1920);putf(root,0x54,1080);
    putf(inout,0x50,30);putf(inout,0x54,30);ptr(inout,0x18,root);ptr(circle,0x18,inout);ptr(side,0x18,circle);
    putf(side,0x54,1080);ptr(draw,0xc0,layout);putf(layout,0x28,1920);putf(layout,0x2c,1080);
    const float base=16.0f/9,targets[]={0,678.0f/466,669.0f/475.5f,4.0f/3,base,21.0f/9};
    // The original iris animates curtain width and translation independently.
    // Only full-height side coverage grows; the circular boundary and UVs do not.
    for(int index=0;index<2;index++)for(int right=0;right<2;right++)for(int phase=0;phase<=4;phase++)for(unsigned i=0;i<sizeof targets/sizeof *targets;i++){
        sprintf((char *)inout+0xb0,"N_InOut_0%d",index);sprintf((char *)circle+0xb0,"P_Circle_0%d",index);sprintf((char *)side+0xb0,"P_%c_0%d",right?'R':'L',index);
        float width=1098.0f*phase/4,target=targets[i],height=1080*(target>0&&target<base?base/target:1);
        putf(side,0x50,width);putf(circle,0x50,2210-width*2);putf(circle,0x54,2210-width*2);side[0x5b]=right?0x21:0x12;
        memset(quad,0x5a,sizeof quad);putf(quad,0x210,width);putf(quad,0x214,1080);putf(quad,0x218,right?0:-width);putf(quad,0x21c,540);
        memcpy(expected,quad,sizeof quad);putf(expected,0x214,height);putf(expected,0x21c,height/2);
        putf(draw,0x10,1);putf(draw,0x24,target>0?target:base);dm_view_state.capable=1;dm_view_state.target=target;
        dm_view_backdrop(side,draw,quad);
        CHECK(closef(*(float *)(quad+0x214),height));CHECK(closef(*(float *)(quad+0x21c),height/2));
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
        CHECK(ui_matrix[0]==ui_x);CHECK(closef(ui_matrix[5]/ui_matrix[0],target));
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
