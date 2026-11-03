// Independent viewport expectations and native touch round trips.
#include "../present_layout.h"
#include <assert.h>
#include <stdio.h>
static int near(double a,double b){return fabs(a-b)<.00001;}
int main(void){
    dm_present_layout r=dm_present_layout_make(1920,1080,678,466,DM_PRESENT_EXPAND);double u,v;
    assert(r.x==0&&r.y==0&&r.w==678&&r.h==466&&r.cx==0&&r.cy==0&&r.cw==1920&&r.ch==1080);
    for(int i=0;i<10;i++)for(int j=0;j<10;j++){assert(dm_present_touch(r,1920,1080,678*i/10.0,466*j/10.0,&u,&v));assert(near(u,i/10.0)&&near(v,j/10.0));}
    r=dm_present_layout_make(1920,1080,669,475.5,DM_PRESENT_EXPAND);assert(r.w==669&&r.h==475.5&&r.cw==1920&&r.ch==1080);
    r=dm_present_layout_make(1920,1080,678,466,DM_PRESENT_FIT);assert(r.x==0&&r.y==42&&r.w==678&&r.h==381);
    assert(!dm_present_touch(r,1920,1080,339,1,&u,&v));assert(dm_present_touch(r,1920,1080,339,232.5,&u,&v)&&near(u,.5)&&near(v,.5));
    assert(!dm_present_touch(r,1920,1080,-1,232,&u,&v)&&u==0);assert(!dm_present_touch(r,1920,1080,339,466,&u,&v)&&v==1);
    assert(dm_present_layout_make(0,1080,678,466,DM_PRESENT_EXPAND).w==0);assert(dm_present_layout_make(1920,1080,NAN,466,DM_PRESENT_EXPAND).w==0);
    puts("present layout: expanded full coverage, fitted bars and inverse native touch passed");return 0;
}
