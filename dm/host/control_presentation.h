// Deterministic visibility policies. Hiding artwork never changes input ownership.
#pragma once
#include <math.h>
#include <stdint.h>
enum { DM_UI_TOUCH=1,DM_UI_MODE=2,DM_UI_NATIVE=4 };
typedef struct { unsigned busy;double show_at; } dm_companion_control_state;
static inline int dm_companion_control_activity(dm_companion_control_state *s,unsigned source,int busy,double now) {
    if(source!=DM_UI_TOUCH && source!=DM_UI_MODE && source!=DM_UI_NATIVE)return 0;
    unsigned next=busy ? s->busy|source : s->busy&~source;
    if(next==s->busy)return 0;
    s->busy=next;
    if(!busy)s->show_at=fmax(s->show_at,now+1.1);
    return 1;
}
static inline int dm_companion_control_hidden(const dm_companion_control_state *s,int presented,int physical,double now) {
    if(!presented || physical)return 1;
    return s->busy!=0 || now<s->show_at;
}
typedef struct { double began,last;int session,active,mode; } dm_control_fade;
static inline void dm_control_fade_event(dm_control_fade *s,int active,double now) {
    if(!s->session || (!s->active && now-s->last>=1.5)){s->session=1;s->began=now;}
    s->active=active;s->last=now;
}
static inline int dm_control_fade_hidden(dm_control_fade *s,double now) {
    if(s->mode==1)return 0;
    if(s->mode==2)return 1;
    if(!s->active && now-s->last>=1.5){s->session=0;return 0;}
    return s->session && now-s->began>=8;
}
