// Deterministic visibility policies. Hiding artwork never changes input ownership.
#pragma once
#include <math.h>
#include <stdint.h>
enum { DM_UI_TOUCH=1,DM_UI_MODE=2,DM_UI_NATIVE=4 };
// Side frames reserve the controls independently of the companion's content.
// Page changes, item operations and native menus must not revoke that input.
static inline int dm_companion_control_hidden(int presented,int physical,int mode) {
    return !presented || physical || mode==2;
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
// A finger owned by the actual game view suppresses virtual input as well as
// artwork. Keep controls out of repeated taps and pen strokes until a short idle.
typedef struct { int active;double resume_at; } dm_game_touch_controls;
static inline int dm_game_touch_activity(dm_game_touch_controls *s,int active,double now) {
    if(s->active==active)return 0;
    s->active=active;if(!active)s->resume_at=now+1.1;
    return 1;
}
static inline int dm_game_touch_hidden(const dm_game_touch_controls *s,int mode,double now) {
    return mode==2 || s->active || now<s->resume_at;
}
