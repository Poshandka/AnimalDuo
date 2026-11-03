// The full-size companion owns the lower screen; controls float above its content.
#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
typedef struct { CGRect game,controls,panel,left,right; } dm_companion_layout;
// Compact controls retain their own minimum column rather than borrowing space
// from an independently fitted companion card.
static inline CGFloat dm_companion_compact_fraction(CGFloat width) {
    return isfinite(width) && width>0 ? fmin(1,fmax(0,(600-width)/160)):0;
}
static inline CGFloat dm_companion_rail_width(CGFloat width) {
    if(!isfinite(width)||width<=0)return 0;
    return fmin(width/3,fmin(128,fmax(68,width*.16)));
}
static inline CGFloat dm_companion_footer_height(CGSize size) {
    if(!isfinite(size.width)||!isfinite(size.height)||size.width<=0||size.height<=0)return 0;
    return fmin(size.height*0.2,fmax(56,fmin(88,size.width*0.09)));
}
// Rendering and controller placement share these physical columns. The body
// keeps the manifest's aspect inside the centre; its background still bleeds to
// the panel edges and the footer remains full width.
typedef struct {
    CGRect body,footer,content,left,right;
    CGFloat body_scale,nav_scale;
    CGPoint body_offset,nav_offset;
} dm_companion_surface_layout;
static inline dm_companion_surface_layout dm_companion_surface_make(CGSize size,int controls) {
    dm_companion_surface_layout p={0};
    if(!isfinite(size.width)||!isfinite(size.height)||size.width<=0||size.height<=0)return p;
    CGFloat h=dm_companion_footer_height(size),rail=controls?dm_companion_rail_width(size.width):0;
    p.body=CGRectMake(0,0,size.width,fmax(1,size.height-h));
    p.footer=CGRectMake(0,CGRectGetMaxY(p.body),size.width,h);
    p.content=CGRectMake(rail,0,fmax(1,size.width-2*rail),p.body.size.height);
    CGFloat edge=fmin(10,rail*.15);
    p.left=CGRectMake(edge,0,fmax(0,rail-edge),p.body.size.height);p.right=CGRectMake(size.width-rail,0,fmax(0,rail-edge),p.body.size.height);
    p.body_scale=fmax(.001,fmin(p.content.size.width/1240,p.content.size.height/968));
    p.body_offset=CGPointMake(CGRectGetMidX(p.content)-620*p.body_scale,CGRectGetMidY(p.content)-484*p.body_scale);
    p.nav_scale=fmax(.001,fmin(size.width/1240,h/112));
    p.nav_offset=CGPointMake((size.width-1240*p.nav_scale)/2,CGRectGetMinY(p.footer)+(h-112*p.nav_scale)/2-968*p.nav_scale);
    return p;
}
static inline dm_companion_layout dm_companion_screen_layout(CGRect safe, int portrait, int touch) {
    dm_companion_layout r={0};
    if(!isfinite(safe.size.width) || !isfinite(safe.size.height) || safe.size.width<=0 || safe.size.height<=0)return r;
    CGFloat w=safe.size.width,h=safe.size.height;
    if(!portrait){
        w=fmin(w,h*16.0/9.0);h=w*9.0/16.0;
        r.game=CGRectMake(safe.origin.x+(safe.size.width-w)/2,safe.origin.y+(safe.size.height-h)/2,w,h);
        return r;
    }
    h=fmin(safe.size.height*0.48,w*9.0/16.0);w=h*16.0/9.0;
    r.game=CGRectMake(safe.origin.x+(safe.size.width-w)/2,safe.origin.y,w,h);
    CGRect lower=CGRectMake(safe.origin.x,CGRectGetMaxY(r.game),safe.size.width,safe.size.height-h);
    r.panel=lower;
    if(touch){
        r.controls=lower;r.controls.size.height-=dm_companion_footer_height(lower.size);
        CGFloat rail=dm_companion_rail_width(lower.size.width);
        r.left=CGRectMake(lower.origin.x,lower.origin.y,rail,r.controls.size.height);
        r.right=CGRectMake(CGRectGetMaxX(lower)-rail,lower.origin.y,rail,r.controls.size.height);
    }
    return r;
}
// Expanded folding-phone windows split the entire canvas equally. Foreground
// controls stay inside each asymmetric safe edge; backgrounds reach the edge.
static inline dm_companion_layout dm_companion_fold_layout(CGRect bounds,CGRect safe,int split,int touch) {
    dm_companion_layout r={0};r.game=bounds;
    if(!split)return r;
    r.game.size.height=bounds.size.height/2;
    r.panel=CGRectMake(bounds.origin.x,CGRectGetMaxY(r.game),bounds.size.width,bounds.size.height-r.game.size.height);
    if(touch){
        dm_companion_surface_layout surface=dm_companion_surface_make(r.panel.size,1);
        // The footer already protects the home-indicator inset. Intersect its
        // body with the safe area once, rather than removing both independently.
        CGRect lower=CGRectIntersection(CGRectOffset(surface.body,r.panel.origin.x,r.panel.origin.y),safe);
        if(!CGRectIsNull(lower)&&lower.size.width>0&&lower.size.height>0){
            r.controls=lower;
            CGFloat rail=dm_companion_rail_width(lower.size.width);
            r.left=CGRectMake(lower.origin.x,lower.origin.y,rail,r.controls.size.height);
            r.right=CGRectMake(CGRectGetMaxX(lower)-rail,lower.origin.y,rail,r.controls.size.height);
        }
    }
    return r;
}
// UIKit drawing, input hit testing and geometry validation consume the same positions.
typedef struct {
    CGRect left,right;
    CGPoint stick,dpad,face,right_stick,shoulder[4],click[2],menu[2],swap;
    CGFloat unit,face_gap,face_r,stick_r,dpad_r,right_r,shoulder_r,click_r,swap_r,knob_r;
    CGSize menu_size;
} dm_companion_pad_layout;
static inline CGRect dm_companion_pad_disc(CGPoint p,CGFloat radius) {
    return CGRectMake(p.x-radius,p.y-radius,2*radius,2*radius);
}
static inline CGFloat dm_companion_pad_stick_extent(dm_companion_pad_layout p,int right) {
    CGFloat r=right?p.right_r:p.stick_r;
    return r*1.4;
}
static inline CGRect dm_companion_pad_region(dm_companion_pad_layout p,int right) {
    CGRect rail=right?p.right:p.left;
    CGFloat margin=8-6*dm_companion_compact_fraction(CGRectGetMaxX(p.right));
    CGFloat vertical=fmax(0,fmin(4,(rail.size.height*.09-22+7.2*p.unit)/2));
    return CGRectInset(rail,fmin(margin,rail.size.width*.08),vertical);
}
static inline CGRect dm_companion_pad_menu_hit(dm_companion_pad_layout p,int right) {
    CGFloat w=fmax(44,p.menu_size.width+16*p.unit),h=fmax(44,p.menu_size.height+16*p.unit);
    return CGRectMake(p.menu[right].x-w/2,p.menu[right].y-h/2,w,h);
}
static inline CGRect dm_companion_pad_group(dm_companion_pad_layout p,int right) {
    CGRect box=dm_companion_pad_disc(right?p.face:p.stick,right?p.face_gap+p.face_r*1.25:dm_companion_pad_stick_extent(p,0));
    box=CGRectUnion(box,dm_companion_pad_disc(right?p.right_stick:p.dpad,right?dm_companion_pad_stick_extent(p,1):p.dpad_r*1.3));
    for(int i=right?2:0;i<(right?4:2);i++)box=CGRectUnion(box,dm_companion_pad_disc(p.shoulder[i],p.shoulder_r*1.45));
    box=CGRectUnion(box,dm_companion_pad_disc(p.click[right],p.click_r*1.35));
    box=CGRectUnion(box,dm_companion_pad_menu_hit(p,right));
    if(!right)box=CGRectUnion(box,dm_companion_pad_disc(p.swap,fmax(22,p.swap_r*1.6)));
    return box;
}
static inline void dm_companion_pad_center(dm_companion_pad_layout *p) {
    for(int right=0;right<2;right++){
        CGRect box=dm_companion_pad_group(*p,right),rail=right?p->right:p->left;
        CGFloat dx=CGRectGetMidX(rail)-CGRectGetMidX(box),dy=CGRectGetMidY(rail)-CGRectGetMidY(box);
        CGPoint *points[]={right?&p->face:&p->stick,right?&p->right_stick:&p->dpad,&p->shoulder[right*2],&p->shoulder[right*2+1],&p->click[right],&p->menu[right],&p->swap};
        for(int i=0;i<(right?6:7);i++){points[i]->x+=dx;points[i]->y+=dy;}
    }
}
static inline dm_companion_pad_layout dm_companion_pad_geometry_regions(CGSize size,CGFloat scale,CGRect left,CGRect right) {
    dm_companion_pad_layout p={0};
    CGFloat w=size.width,h=size.height;
    if(!isfinite(w)||!isfinite(h)||w<=0||h<=0)return p;
    if(CGRectIsEmpty(left)||CGRectIsEmpty(right))return p;
    CGFloat compact=dm_companion_compact_fraction(w),rail=fmin(left.size.width,right.size.width);
    h=fmin(left.size.height,right.size.height);
    if(!isfinite(scale))scale=1;
    scale=fmin(1.35,fmax(.65,scale));
    CGFloat margin=fmin(8-6*compact,rail*.08),vertical=fmin(4,h*.02);
    // Reserve the moving knob, generous hit regions and shoulder pair before
    // centring. A requested scale cannot consume the companion's middle column.
    CGFloat width=fmax(140,2*(42+1.25*(24+2*compact)));
    CGFloat fit=fmin((rail-2*margin)/width,((.58-.06*compact)*rail-2*margin)/(2*24*1.45));
    fit=fmin(fit,(h*.09-2*vertical)/(18.8+6*compact));
    // The +/- row sits between the upper and lower control groups. Protect
    // its full 44-point minimum target from both groups on short surfaces.
    CGFloat face_extent=42+1.25*(24+2*compact),menu_half=18+6*compact+8;
    fit=fmin(fit,(h*.18-28)/face_extent);
    fit=fmin(fit,(h*.18-6)/(face_extent+menu_half));
    p.unit=fmax(0,fmin(fit,scale*fmin(1.08,fmin(rail/(175.0-31*compact),h/550.0))));
    p.left=left;p.right=right;
    p.stick=CGPointMake(CGRectGetMidX(left),left.origin.y+h*.36);p.face=CGPointMake(CGRectGetMidX(right),right.origin.y+h*.36);
    p.dpad=CGPointMake(CGRectGetMidX(left),left.origin.y+h*.72);p.right_stick=CGPointMake(CGRectGetMidX(right),right.origin.y+h*.72);
    p.shoulder[0]=CGPointMake(left.origin.x+left.size.width*(.29-.03*compact),left.origin.y+42*p.unit);p.shoulder[1]=CGPointMake(left.origin.x+left.size.width*(.71+.03*compact),left.origin.y+42*p.unit);
    p.shoulder[2]=CGPointMake(CGRectGetMaxX(right)-right.size.width*(.29-.03*compact),right.origin.y+42*p.unit);p.shoulder[3]=CGPointMake(CGRectGetMaxX(right)-right.size.width*(.71+.03*compact),right.origin.y+42*p.unit);
    p.click[0]=CGPointMake(CGRectGetMidX(left),left.origin.y+h*.91);p.click[1]=CGPointMake(CGRectGetMidX(right),right.origin.y+h*.91);
    p.swap=CGPointMake(CGRectGetMidX(left),left.origin.y+h*.18);
    p.face_gap=42*p.unit;p.face_r=(24+2*compact)*p.unit;p.stick_r=50*p.unit;p.right_r=46*p.unit;p.dpad_r=43*p.unit;
    p.shoulder_r=24*p.unit;p.click_r=(17+5*compact)*p.unit;p.swap_r=(15+5*compact)*p.unit;p.knob_r=30*p.unit;
    p.menu_size=CGSizeMake((50+14*compact)*p.unit,(36+12*compact)*p.unit);
    p.menu[0]=CGPointMake(CGRectGetMidX(left),left.origin.y+h*.54);p.menu[1]=CGPointMake(CGRectGetMidX(right),right.origin.y+h*.54);
    dm_companion_pad_center(&p);return p;
}
static inline dm_companion_pad_layout dm_companion_pad_geometry_scaled(CGSize size,CGFloat scale) {
    CGFloat rail=dm_companion_rail_width(size.width),edge=fmin(10,rail*.15);
    return dm_companion_pad_geometry_regions(size,scale,CGRectMake(edge,0,rail-edge,size.height),CGRectMake(size.width-rail,0,rail-edge,size.height));
}
static inline dm_companion_pad_layout dm_companion_pad_geometry(CGSize size) {
    return dm_companion_pad_geometry_scaled(size,1);
}

static inline int dm_companion_pad_contains(CGSize size,CGPoint point) {
    dm_companion_pad_layout p=dm_companion_pad_geometry(size);
    return CGRectContainsPoint(p.left,point) || CGRectContainsPoint(p.right,point);
}
