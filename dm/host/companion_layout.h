// The full-size companion owns the lower screen; controls float above its content.
#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
typedef struct { CGFloat left,right,bottom; } dm_companion_dock_insets;
typedef struct { CGRect game,controls,panel,left,right; dm_companion_dock_insets dock; } dm_companion_layout;
// Compact controls retain their own minimum column rather than borrowing space
// from an independently fitted companion card.
static inline CGFloat dm_companion_compact_fraction(CGFloat width) {
    return isfinite(width) && width>0 ? fmin(1,fmax(0,(600-width)/160)):0;
}
static inline CGFloat dm_companion_rail_width(CGFloat width) {
    if(!isfinite(width)||width<=0)return 0;
    return fmin(width/3,fmin(128,fmax(68,width*.16)));
}
static inline CGFloat dm_companion_footer_gap(CGSize size) {
    return fmin(12,size.height*.028);
}
// Rendering and controller placement share these physical columns. The body
// keeps the manifest's aspect inside the centre; its background still bleeds to
// the panel edges and the footer remains full width.
typedef struct {
    CGRect body,footer,nav_art,nav_controls,content,left,right;
    CGFloat body_scale,nav_scale;
    CGPoint body_offset,nav_offset;
} dm_companion_surface_layout;
static inline dm_companion_surface_layout dm_companion_surface_make_safe(CGSize size,int controls,dm_companion_dock_insets dock) {
    dm_companion_surface_layout p={0};
    if(!isfinite(size.width)||!isfinite(size.height)||size.width<=0||size.height<=0)return p;
    CGFloat gap=dm_companion_footer_gap(size),bottom=fmin(size.height,fmax(0,dock.bottom));
    CGFloat inset=fmax(fmin(16,size.width*.026),fmin(22,bottom*.60));
    CGFloat left=fmin(size.width,fmax(inset,dock.left));
    CGFloat right=fmin(size.width-left,fmax(inset,dock.right));
    CGFloat nav_width=size.width-left-right;
    // The authored icons, labels and selection art occupy y=975..1073.
    // Centre that strip in a compact plate and reserve only its bottom edge
    // for gestures, with side clearance for the window's curved corners.
    CGFloat art_height=98,padding=fmin(11,fmax(4,bottom*.31));
    CGFloat gesture_edge=fmin(bottom,padding),target_scale=fmin(.62,nav_width/1240);
    CGFloat h=fmin(size.height-gap,fmax(44+gesture_edge,art_height*target_scale+2*padding));
    CGFloat rail=controls?dm_companion_rail_width(size.width):0;
    CGFloat footer_y=size.height-h;
    p.body=CGRectMake(0,0,size.width,fmax(0,footer_y-gap));
    p.footer=CGRectMake(0,footer_y,size.width,h);
    p.nav_scale=fmax(.001,fmin(target_scale,(h-2*padding)/art_height));
    CGFloat nav_w=fmin(nav_width,1240*p.nav_scale),nav_h=fmin(h,art_height*p.nav_scale);
    CGFloat nav_x=left+(nav_width-nav_w)/2;
    p.nav_art=CGRectMake(nav_x,footer_y+(h-nav_h)/2,nav_w,nav_h);
    p.nav_controls=CGRectMake(nav_x,footer_y,nav_w,fmax(0,h-gesture_edge));
    p.nav_offset=CGPointMake(nav_x,CGRectGetMidY(p.nav_art)-1024*p.nav_scale);
    p.content=CGRectMake(rail,0,fmax(1,size.width-2*rail),p.body.size.height);
    CGFloat edge=fmin(10,rail*.15);
    p.left=CGRectMake(edge,0,fmax(0,rail-edge),p.body.size.height);p.right=CGRectMake(size.width-rail,0,fmax(0,rail-edge),p.body.size.height);
    p.body_scale=fmax(.001,fmin(p.content.size.width/1240,p.content.size.height/968));
    p.body_offset=CGPointMake(CGRectGetMidX(p.content)-620*p.body_scale,CGRectGetMidY(p.content)-484*p.body_scale);
    return p;
}
static inline dm_companion_surface_layout dm_companion_surface_make(CGSize size,int controls) {
    return dm_companion_surface_make_safe(size,controls,(dm_companion_dock_insets){0});
}
static inline void dm_companion_place_controls(dm_companion_layout *layout,CGRect safe,int touch) {
    CGRect panel=layout->panel;
    layout->dock=(dm_companion_dock_insets){
        fmax(0,CGRectGetMinX(safe)-CGRectGetMinX(panel)),
        fmax(0,CGRectGetMaxX(panel)-CGRectGetMaxX(safe)),
        fmax(0,CGRectGetMaxY(panel)-CGRectGetMaxY(safe))
    };
    if(!touch)return;
    dm_companion_surface_layout surface=dm_companion_surface_make_safe(panel.size,1,layout->dock);
    CGRect body=CGRectOffset(surface.body,panel.origin.x,panel.origin.y);
    CGRect lower=CGRectIntersection(body,safe);
    if(CGRectIsNull(lower)||CGRectIsEmpty(lower))return;
    layout->controls=lower;
    CGFloat rail=dm_companion_rail_width(lower.size.width);
    layout->left=CGRectMake(lower.origin.x,lower.origin.y,rail,lower.size.height);
    layout->right=CGRectMake(CGRectGetMaxX(lower)-rail,lower.origin.y,rail,lower.size.height);
}
static inline dm_companion_layout dm_companion_screen_layout(CGRect bounds, CGRect safe, int portrait, int touch) {
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
    r.panel=CGRectMake(bounds.origin.x,CGRectGetMaxY(r.game),bounds.size.width,CGRectGetMaxY(bounds)-CGRectGetMaxY(r.game));
    dm_companion_place_controls(&r,safe,touch);
    return r;
}
// Tablets and expanded folding-phone windows split the canvas equally. Foreground
// controls stay inside each asymmetric safe edge; backgrounds reach the edge.
static inline dm_companion_layout dm_companion_fold_layout(CGRect bounds,CGRect safe,int split,int touch) {
    dm_companion_layout r={0};r.game=bounds;
    if(!split)return r;
    r.game.size.height=bounds.size.height/2;
    r.panel=CGRectMake(bounds.origin.x,CGRectGetMaxY(r.game),bounds.size.width,bounds.size.height-r.game.size.height);
    dm_companion_place_controls(&r,safe,touch);
    return r;
}
// UIKit drawing, input hit testing and geometry validation consume the same positions.
enum { DM_COMPANION_DPAD_RADIUS=43, DM_COMPANION_DPAD_ARM_WIDTH=17 };
typedef struct {
    CGRect left,right;
    CGPoint stick,dpad,face,right_stick,shoulder[4],click[2],menu[2],swap;
    CGFloat unit,face_gap,face_x_scale,face_y_scale,face_r,stick_r,dpad_r,right_r,shoulder_r,click_r,swap_r,knob_r;
    CGFloat stick_hit_r,right_hit_r;
    CGFloat face_hit_r,dpad_hit_r,shoulder_hit_r,click_hit_r;
    CGSize menu_size,menu_hit_size;
} dm_companion_pad_layout;
static inline CGRect dm_companion_pad_disc(CGPoint p,CGFloat radius) {
    return CGRectMake(p.x-radius,p.y-radius,2*radius,2*radius);
}
static inline CGFloat dm_companion_pad_stick_extent(dm_companion_pad_layout p,int right) {
    return right?p.right_hit_r:p.stick_hit_r;
}
static inline CGFloat dm_companion_pad_shoulder_extent(dm_companion_pad_layout p) {
    return p.shoulder_hit_r*(1.45/1.35);
}
static inline CGRect dm_companion_pad_face_box(dm_companion_pad_layout p) {
    CGFloat extent=p.face_gap+p.face_hit_r,x=extent*p.face_x_scale,y=extent*p.face_y_scale;
    return CGRectMake(p.face.x-x,p.face.y-y,2*x,2*y);
}
static inline CGRect dm_companion_pad_region(dm_companion_pad_layout p,int right) {
    CGRect rail=right?p.right:p.left;
    CGFloat margin=8-6*dm_companion_compact_fraction(CGRectGetMaxX(p.right));
    CGFloat vertical=fmax(0,fmin(4,(rail.size.height*.09-22+7.2*p.unit)/2));
    return CGRectInset(rail,fmin(margin,rail.size.width*.08),vertical);
}
static inline CGRect dm_companion_pad_face_region(dm_companion_pad_layout p) {
    CGRect region=dm_companion_pad_region(p,1);
    CGFloat inset=CGRectGetMinX(region)-CGRectGetMinX(p.right);
    // The diamond can use part of the rail padding while retaining a clear edge.
    return CGRectInset(region,-fmax(0,inset-fmax(1.5,inset*.45)),0);
}
static inline CGRect dm_companion_pad_menu_hit(dm_companion_pad_layout p,int right) {
    CGFloat w=p.menu_hit_size.width,h=p.menu_hit_size.height;
    return CGRectMake(p.menu[right].x-w/2,p.menu[right].y-h/2,w,h);
}
static inline CGRect dm_companion_pad_group(dm_companion_pad_layout p,int right) {
    CGRect box=right?dm_companion_pad_face_box(p):dm_companion_pad_disc(p.stick,dm_companion_pad_stick_extent(p,0));
    box=CGRectUnion(box,dm_companion_pad_disc(right?p.right_stick:p.dpad,right?dm_companion_pad_stick_extent(p,1):p.dpad_hit_r));
    for(int i=right?2:0;i<(right?4:2);i++)box=CGRectUnion(box,dm_companion_pad_disc(p.shoulder[i],dm_companion_pad_shoulder_extent(p)));
    box=CGRectUnion(box,dm_companion_pad_disc(p.click[right],p.click_hit_r));
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
static inline CGFloat dm_companion_pad_art_size(CGFloat requested,CGFloat fitted,CGFloat limit,CGFloat growth) {
    return fmin(requested,fitted+(limit-fitted)*growth);
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
    CGFloat pitch=h*.17;
    // The +/- row sits between the upper and lower control groups. Protect
    // its full 44-point minimum target from both groups on short surfaces.
    CGFloat face_extent=42+1.25*(24+2*compact),menu_half=18+6*compact+8;
    fit=fmin(fit,(pitch-28)/face_extent);
    fit=fmin(fit,(pitch-6)/(face_extent+menu_half));
    // The lower stick and its click key use the same row pitch as the
    // upper stick, menu and D-pad. Leave room for both full touch targets.
    fit=fmin(fit,(pitch-6)/(46*1.4+1.35*(17+5*compact)));
    CGFloat nominal=fmin(1.08,fmin(rail/(175.0-31*compact),h/550.0));
    p.unit=fmax(0,fmin(fit,scale*nominal));
    // Keep the rail reservations fitted. Each control uses the available
    // space around its artwork progressively across the full slider range.
    CGFloat art_unit=fmax(0,fmin(fit,nominal))*scale;
    CGFloat growth=fmax(0,(scale-1)/.35);
    p.stick_hit_r=50*p.unit*1.4;p.right_hit_r=46*p.unit*1.4;
    p.left=left;p.right=right;
    p.stick=CGPointMake(CGRectGetMidX(left),left.origin.y+2*pitch);p.face=CGPointMake(CGRectGetMidX(right),right.origin.y+2*pitch);
    p.dpad=CGPointMake(CGRectGetMidX(left),left.origin.y+4*pitch);p.right_stick=CGPointMake(CGRectGetMidX(right),right.origin.y+4*pitch);
    p.shoulder[0]=CGPointMake(left.origin.x+left.size.width*(.29-.03*compact),left.origin.y+42*p.unit);p.shoulder[1]=CGPointMake(left.origin.x+left.size.width*(.71+.03*compact),left.origin.y+42*p.unit);
    p.shoulder[2]=CGPointMake(CGRectGetMaxX(right)-right.size.width*(.29-.03*compact),right.origin.y+42*p.unit);p.shoulder[3]=CGPointMake(CGRectGetMaxX(right)-right.size.width*(.71+.03*compact),right.origin.y+42*p.unit);
    p.click[0]=CGPointMake(CGRectGetMidX(left),left.origin.y+5*pitch);p.click[1]=CGPointMake(CGRectGetMidX(right),right.origin.y+5*pitch);
    p.swap=CGPointMake(CGRectGetMidX(left),left.origin.y+h*.18);
    // Open the diamond slightly where needed to keep adjacent outlines apart.
    // Its outer hit extent stays the same as the fitted diamond.
    CGFloat face_radius=24+2*compact,fitted_face=face_radius*p.unit,face_gap=42*p.unit;
    CGFloat face_box=face_gap+1.25*fitted_face,clearance=fmin(1.5,6*p.unit);
    CGFloat face_padding=.5*clearance+2*p.unit; // retain a small overlap for diagonal presses
    CGFloat face_limit=(face_box-M_SQRT1_2*clearance-face_padding)/(1+M_SQRT2);
    p.face_gap=face_gap+growth*(face_box-face_limit-face_padding-face_gap);
    p.face_r=dm_companion_pad_art_size(face_radius*art_unit,fitted_face,face_limit,growth);
    p.face_hit_r=face_box-p.face_gap;
    CGFloat face_half_width=CGRectGetWidth(dm_companion_pad_face_region(p))/2;
    p.face_x_scale=face_box>0 ? fmax(1,fmin(1.12,face_half_width/face_box)) : 1;
    p.stick_r=50*art_unit;p.right_r=46*art_unit;p.knob_r=30*art_unit;
    CGFloat dpad_radius=DM_COMPANION_DPAD_RADIUS;
    p.dpad_hit_r=dpad_radius*1.3*p.unit;
    // Include the diagonal distance to the end of a D-pad arm.
    p.dpad_r=dm_companion_pad_art_size(dpad_radius*art_unit,dpad_radius*p.unit,
                                      p.dpad_hit_r/hypot(1,DM_COMPANION_DPAD_ARM_WIDTH/dpad_radius),growth);
    // The diagonally angled teardrop tip stays inside the old shoulder box.
    p.shoulder_hit_r=24*p.unit*1.35;p.shoulder_r=24*art_unit;
    CGFloat click_radius=17+5*compact;
    p.click_hit_r=click_radius*p.unit*1.35;p.click_r=click_radius*art_unit;
    p.swap_r=(15+5*compact)*p.unit;
    CGFloat menu_w=50+14*compact,menu_h=36+12*compact;
    p.menu_hit_size=CGSizeMake(fmax(44,(menu_w+16)*p.unit),fmax(44,(menu_h+16)*p.unit));
    CGFloat menu_limit=fmin(p.menu_hit_size.width/menu_w,p.menu_hit_size.height/menu_h);
    CGFloat menu_unit=dm_companion_pad_art_size(art_unit,p.unit,menu_limit,growth);
    p.menu_size=CGSizeMake(menu_w*menu_unit,menu_h*menu_unit);
    p.menu[0]=CGPointMake(CGRectGetMidX(left),left.origin.y+3*pitch);p.menu[1]=CGPointMake(CGRectGetMidX(right),right.origin.y+3*pitch);
    // Stretch the diamond vertically into the free space between the shoulders
    // and +, independently of the horizontal clearance inside the right rail.
    CGFloat face_top=p.shoulder[2].y+dm_companion_pad_shoulder_extent(p)+6;
    CGFloat face_bottom=CGRectGetMinY(dm_companion_pad_menu_hit(p,1))-6;
    p.face_y_scale=1;
    if(face_box>0 && face_bottom-face_top>2*face_box){
        p.face_y_scale=fmin(1.35,(face_bottom-face_top)/(2*face_box));
        CGFloat extent=face_box*p.face_y_scale;
        p.face.y=fmin(face_bottom-extent,fmax(face_top+extent,p.face.y));
    }
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
