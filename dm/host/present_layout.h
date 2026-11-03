// Shared display framing and its inverse for native touchscreen coordinates.
#pragma once
#include <math.h>
enum { DM_PRESENT_FIT=0, DM_PRESENT_FILL=1, DM_PRESENT_STRETCH=2, DM_PRESENT_EXPAND=3 };
typedef struct { double x,y,w,h; unsigned cx,cy,cw,ch; } dm_present_layout;
static inline dm_present_layout dm_present_layout_make(unsigned cw,unsigned ch,double dw,double dh,int mode) {
    dm_present_layout r={0};
    if(!cw||!ch||!isfinite(dw)||!isfinite(dh)||dw<=0||dh<=0)return r;
    r.cw=cw;r.ch=ch;
    if(mode==DM_PRESENT_FILL){
        if(dw/dh<(double)cw/ch){r.cw=(unsigned)fmax(1,fmin(cw,floor(ch*dw/dh)));r.cx=(cw-r.cw)/2;}
        else {r.ch=(unsigned)fmax(1,fmin(ch,floor(cw*dh/dw)));r.cy=(ch-r.ch)/2;}
    }
    if(mode==DM_PRESENT_FILL||mode==DM_PRESENT_STRETCH||mode==DM_PRESENT_EXPAND){r.w=dw;r.h=dh;return r;}
    double s=fmin(dw/cw,dh/ch);r.w=round(cw*s);r.h=round(ch*s);r.x=floor((dw-r.w)/2);r.y=floor((dh-r.h)/2);
    if(fabs((dw/dh)/((double)cw/ch)-1)<0.01){r.x=r.y=0;r.w=dw;r.h=dh;}
    return r;
}
static inline int dm_present_touch(dm_present_layout r,unsigned sw,unsigned sh,double x,double y,double *u,double *v) {
    if(r.w<=0||r.h<=0||!sw||!sh)return 0;
    *u=(r.cx+fmin(1,fmax(0,(x-r.x)/r.w))*r.cw)/sw;
    *v=(r.cy+fmin(1,fmax(0,(y-r.y)/r.h))*r.ch)/sh;
    return x>=r.x&&y>=r.y&&x<r.x+r.w&&y<r.y+r.h;
}
