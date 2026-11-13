// Portrait companions use shared side geometry: the centre passes touches to the
// auxiliary view, and both sticks are visible. The standard overlay remains edge-based.
// Virtual gamepad (Nintendo button positions) + physical controllers (GameController). Both are merged and handed to the host through dm_input_set (hle_hid.c, bit layout in dm_input.h).
//   The screen-controls menu selects 2D / 3D (and Tap in handheld mode), keeping the existing per-game NSUserDefaults choice and profile default (DM_GAME_PAD_LAYOUT).
//   Tap (touch): no control but the layout button, every other touch goes to the game's touch screen; offered only while the game is in handheld mode, the only one in which it reads the touch screen (Balatro, played by touch).
//   2D (simple): top corners ZL above L (one column), ZR above R likewise, teardrops with the tip toward the screen corner; − and + side by side at the top centre; the left stick in the bottom-left corner (fixed ring, tilt measured from the ring centre, small dead zone);
//     the A (right) B (bottom) X (top) Y (left) diamond in the bottom-right corner, sliding a finger between keys switches keys. Each bottom corner holds a single control, so it sits close in (reaching halfway into the side safe-area inset).
//   3D (full, Pro Controller style): everything in 2D (left stick and diamond keep their place and size), plus a D-pad (inward of and below the left stick, 8-way), a right stick that is not drawn
//     (a touch landing in the right third of the screen on no control holds it: centred where it lands, the centre dragged along once the finger passes the stick radius) and L3 / R3 (small round keys in the top row, inward of ZL / ZR).
//     Breath of the Wild crouches with L3 and uses the scope with R3; 3D World and Breath of the Wild turn the camera with the right stick.
//   Touch-down ownership: locked keys first (shoulders, − / +, the layout button, L3 / R3), then whichever of the diamond, the D-pad and the left stick has the smallest distance / grab radius (the left stick's grab circle borders the D-pad),
//     then in 3D the right stick for a touch in the right third.
//   Everything hugs the edges and corners to leave the picture room; controls sit over the picture, one CAShapeLayer each: a press only swaps the fill, a stick only moves its knob, nothing redraws the whole screen.
//   Touches no control takes (in 3D, those outside the right third) go to the game's touch screen (pushGame; Super Mario Galaxy's pointer in handheld mode).
//   The virtual gamepad (layout button included) hides while a physical controller is connected and comes back when it is removed; meanwhile every touch goes to the game. Physical controllers keep every button (D-pad and right stick included) and map by position: bottom = B, right = A, left = Y, top = X (same positions as on a Switch controller).
//   Shaking the phone shakes the controller (DM_BTN_SHAKE: its six-axis sensor, hle_hid.c), whichever controls are in use; see "Shaking the phone" below.
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <CoreMotion/CoreMotion.h>
#import <CoreText/CoreText.h>
#include <pthread.h>
#include "dm.h"
#include "dm_input.h"
#include "front.h"
#include "companion_layout.h"
#include "control_presentation.h"
#include "game_profile.h"
#include "haptics_apple.h"
int front_native_keyboard_controls_hidden(unsigned context);

enum { B_A = 0, B_B, B_X, B_Y, B_LS, B_RS, B_L, B_R, B_ZL, B_ZR, B_PLUS, B_MINUS, B_LEFT, B_UP, B_RIGHT, B_DOWN, B_N };
enum { C_NONE = 0, C_STICK, C_DPAD, C_FACE, C_BTN, C_SWAP, C_GAME };   // which control a touch holds; C_GAME: none, the touch goes to the game's touch screen (finger slot << 8)

static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static uint64_t g_touch_btn, g_pad_btn, g_shake_btn;
static int32_t g_touch_lx, g_touch_ly, g_touch_rx, g_touch_ry, g_pad_lx, g_pad_ly, g_pad_rx, g_pad_ry;
static int tilted(int32_t x, int32_t y) { return (int64_t)x * x + (int64_t)y * y > (int64_t)4000 * 4000; }
static void publish(void) {
    pthread_mutex_lock(&g_mu);
    int32_t lx = g_touch_lx, ly = g_touch_ly, rx = g_touch_rx, ry = g_touch_ry;
    if (tilted(g_pad_lx, g_pad_ly)) { lx = g_pad_lx; ly = g_pad_ly; }   // a tilted physical stick wins
    if (tilted(g_pad_rx, g_pad_ry)) { rx = g_pad_rx; ry = g_pad_ry; }
    dm_input_set(g_touch_btn | g_pad_btn | g_shake_btn, lx, ly, rx, ry);
    pthread_mutex_unlock(&g_mu);
}

// ---- Shaking the phone ----
// The accelerometer at 60 Hz (no gyroscope, no permission prompt): gravity is followed by a slow low-pass (about 0.8 s), and a sample whose acceleration beyond it exceeds DM_SHAKE_G
// (1.5 G by default; Documents/env.txt overrides) is a hit. The controller is shaken until 120 ms after the last hit: a flick is one shake (the host finishes it as a whole cycle)
// and shaking on keeps it going. Holding the phone and pressing the screen stays far below the threshold. Each detected shake is logged with its peak
static CMMotionManager *g_motion;
static void motion_start(void) {
    if (g_motion) return;
    g_motion = [CMMotionManager new];
    if (!g_motion.accelerometerAvailable) { LOG("front end: no accelerometer, shaking the phone does nothing"); return; }
    const char *e = getenv("DM_SHAKE_G"); double thr = e && atof(e) > 0 ? atof(e) : 1.5;
    LOG("front end: shaking the phone shakes the controller (threshold %.2f G)", thr);
    g_motion.accelerometerUpdateInterval = 1.0 / 60;
    NSOperationQueue *q = [NSOperationQueue new]; q.maxConcurrentOperationCount = 1;
    __block double gx = 0, gy = 0, gz = 0, last = -1, peak = 0; __block BOOL init = NO;
    [g_motion startAccelerometerUpdatesToQueue:q withHandler:^(CMAccelerometerData *d, NSError *err) {
        (void)err; if (!d) return;
        CMAcceleration a = d.acceleration;
        if (!init) { gx = a.x; gy = a.y; gz = a.z; init = YES; }
        double dx = a.x - gx, dy = a.y - gy, dz = a.z - gz, g = sqrt(dx * dx + dy * dy + dz * dz);
        gx += (a.x - gx) * 0.02; gy += (a.y - gy) * 0.02; gz += (a.z - gz) * 0.02;
        if (g > thr) { if (last < 0) peak = 0; last = d.timestamp; peak = fmax(peak, g); }
        BOOL on = last >= 0 && d.timestamp - last < 0.12;
        if (!on && last >= 0) { LOG("front end: phone shaken (peak %.1f G)", peak); last = -1; }
        uint64_t want = on ? DM_BTN_SHAKE : 0;
        pthread_mutex_lock(&g_mu); BOOL changed = g_shake_btn != want; g_shake_btn = want; pthread_mutex_unlock(&g_mu);
        if (changed) publish();
    }];
}

// ---- Layout constants (in u; x measured from the outer edge, the right half mirrors) ----
static const CGFloat
    K_ZL_X = 44, K_ZL_Y = 40, K_ZL_R = 26,          // ZL / ZR: centre from the outer edge and the top, radius
    K_L_X = 44, K_L_Y = 108, K_L_R = 24,            // L / R: same column as ZL / ZR
    K_DROP_TIP = 1.45,                              // teardrop tip distance from the centre (times the radius)
    K_CORNER_IN = 0.5,                              // how far the bottom-corner controls reach into the side safe-area inset (in landscape there is only the rounded screen corner there; the Dynamic Island is mid-edge)
    K_FACE_X = 81, K_PAD_Y = 82,                    // diamond centre from the outer edge; diamond and stick centre from the bottom (B's lower edge about 5 above it)
    K_FACE_GAP = 50, K_FACE_R = 27,                 // diamond: key distance from the centre, key radius
    K_PILL_DX = 52, K_PILL_Y = 22, K_PILL_W = 50, K_PILL_H = 28,   // − / +: centre from the screen's midline (the middle goes to the layout button) and from the top, size
    K_SWAP_R = 15,                                  // layout button: top centre, level with − / +
    K_STICK_X = 81, K_STICK_R = 77, K_KNOB_R = 30,  // left stick: mirrors the diamond, the ring as large as the whole diamond (key distance + key radius), the knob a little larger than a diamond key
    K_STICK_GRAB = 1.4,                             // how near the ring centre a touch-down grabs a stick (times the ring radius)
    K_FULL = 0.8,                                   // full tilt at this fraction of the ring radius (the knob still travels to the ring edge)
    K_DEAD = 0.1,                                   // stick dead zone (times the ring radius)
    K_WALK_TILT = 0.35,                             // analog tilt at the outer edge of the left stick's slow-walk zone
    // controls only the 3D layout has
    K_LOW_X = 231, K_LOW_Y = 64,                    // D-pad centre from the outer edge and the bottom (inward of and below the left stick, as on a Pro Controller)
    K_DPAD_R = 48, K_ARM_W = DM_COMPANION_DPAD_ARM_WIDTH, K_ARM_IN = 11, // D-pad: arm outer edge from the centre, half-width, tip from the centre
    K_DPAD_GRAB = 1.3,                              // D-pad grab radius (times the outer edge)
    K_RSTICK_R = 60,                                // right stick (not drawn): radius around its centre, the touch-down point
    K_RSWIPE = 1.0 / 3,                             // right stick area: this fraction of the screen width from the right edge (not in u)
    K_CLICK_X = 102, K_CLICK_R = 17;                // L3 / R3: centre from the outer edge (level with ZL / ZR), radius
static const int k_btns[] = {B_ZL, B_L, B_ZR, B_R, B_MINUS, B_PLUS, B_LS, B_RS};   // keys locked at touch-down (L3 / R3 only in the 3D layout)
static NSString *const k_layout_key = @"DmPadLayout";   // NSUserDefaults: 0 = 2D, 1 = 3D, 2 = Tap (DM_GAME_PAD_LAYOUT's numbers)
static void migrate_full_layout_defaults(NSUserDefaults *defaults) {
    if(DM_GAME_PAD_LAYOUT!=1 || [defaults boolForKey:@"DmPadFullDefaultV1"])return;
    NSNumber *saved=[defaults objectForKey:k_layout_key];
    if(!saved || saved.integerValue==0)[defaults setInteger:1 forKey:k_layout_key];
    [defaults setBool:YES forKey:@"DmPadFullDefaultV1"];
}
int dm_opmode(void);   // hle_oe.c: 0 = handheld

@interface DmGamepad : UIView
- (instancetype)initWithFrame:(CGRect)frame preview:(BOOL)preview;
- (void)configureProfile:(NSDictionary *)profile portrait:(BOOL)portrait;
- (NSArray *)editingHandles;
- (void)presentationCompanion:(BOOL)dock suppressed:(BOOL)suppressed;
- (void)nativeSurface:(BOOL)enabled;
- (void)artworkMode:(int)mode;
- (void)companionCanvas:(CGRect)frame;
@end
static __weak DmGamepad *g_view;
void front_native_ui_context(unsigned context);
int front_controls_full_canvas(void);
int front_controls_outer_display(void);

double dm_touch_default_slow_walk_radius(double deadZone) {
    return deadZone + (K_FULL - deadZone) * K_WALK_TILT;
}

@implementation DmGamepad {
    NSMapTable<UITouch *, NSNumber *> *_owner;     // touch → control (with the key for C_BTN or the stick for C_STICK, << 8)
    UITouch *_stick[2]; CGPoint _stickNow[2];      // the touch holding each stick and where it is now (0 left, 1 right)
    CGPoint _rCentre;                              // the right stick's centre: where its touch landed, dragged along past K_RSTICK_R
    uint64_t _faceBits, _dpadBits, _btnBits;
    NSMapTable<UITouch *, NSNumber *> *_faceOf;    // which keys each touch on the diamond currently holds
    CAShapeLayer *_key[B_N]; CATextLayer *_label[B_N];   // one layer per key
    CAShapeLayer *_rightRing, *_rightKnob; CATextLayer *_rightLabel;
    CAShapeLayer *_ring, *_knob;                   // left stick; the companion also draws the right stick
    CAShapeLayer *_swap; CATextLayer *_swapLabel; BOOL _swapHeld;
    UIImpactFeedbackGenerator *_touchFeedback;       // one short feedback per touch-control press edge
    unsigned _hapticSticks;
    BOOL _stickShown;                              // a visible stick was held at the last refresh
    BOOL _full, _tap;                              // the 3D layout / the Tap layout is current
    CALayer *_controls;                            // holds every control layer: hidden while a physical controller is connected (the view itself stays, for game touches)
    BOOL _sideControls, _suppressed, _nativeSurface;
    CGRect _companionCanvas;
    dm_control_fade _fade;NSTimer *_artTimer;
    BOOL _padOff;                                  // a physical controller is connected: every touch goes to the game
    BOOL _previewMode;
    NSDictionary *_custom;
    UITouch *_game[16];                            // touches on the game's touch screen by finger slot
}

static UIColor *k_idle, *k_on, *k_line, *k_ringFill, *k_text, *k_textOn;
static CAShapeLayer *shape(CALayer *parent) {
    CAShapeLayer *l = [CAShapeLayer layer];
    l.fillColor = k_idle.CGColor; l.strokeColor = k_line.CGColor; l.lineWidth = 1.5;
    l.shadowColor = UIColor.blackColor.CGColor; l.shadowOpacity = 0.2; l.shadowRadius = 3; l.shadowOffset = CGSizeMake(0, 1);
    [parent addSublayer:l]; return l;
}
static CATextLayer *label(CALayer *parent, NSString *s) {
    CATextLayer *t = [CATextLayer layer];
    t.string = s; t.alignmentMode = kCAAlignmentCenter; t.foregroundColor = k_text.CGColor; t.contentsScale = UIScreen.mainScreen.scale;
    [parent addSublayer:t]; return t;
}
static CGFloat dist(CGPoint a,CGPoint b);
static CGPoint side(CGRect s,int right,CGFloat dx,CGFloat y);
static BOOL fullOnly(int b) { return b == B_LS || b == B_RS || b >= B_LEFT; }   // keys shown only in the 3D layout
#include "TouchControlsConfiguration.inc"

- (instancetype)initWithFrame:(CGRect)f {
    return [self initWithFrame:f preview:NO];
}
- (instancetype)initWithFrame:(CGRect)f preview:(BOOL)preview {
    if ((self = [super initWithFrame:f])) {
        _previewMode=preview;
        self.multipleTouchEnabled = YES; self.opaque = NO; self.backgroundColor = UIColor.clearColor;
        const char *feedback = getenv("DM_TOUCH_HAPTICS");
        if (!preview && (!feedback || atoi(feedback))) {
            _touchFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [_touchFeedback prepare];
        }
        _owner = [NSMapTable strongToStrongObjectsMapTable]; _faceOf = [NSMapTable strongToStrongObjectsMapTable];
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            // each colour carries its own low opacity instead of lowering the whole view's alpha (that would add an off-screen pass for the full-screen layer)
            k_idle = [UIColor colorWithWhite:1 alpha:0.14]; k_on = [UIColor colorWithWhite:1 alpha:0.45]; k_line = [UIColor colorWithWhite:1 alpha:0.38];
            k_ringFill = [UIColor colorWithWhite:1 alpha:0.06]; k_text = [UIColor colorWithWhite:1 alpha:0.6]; k_textOn = [UIColor colorWithWhite:0 alpha:0.7];
        });
        _controls = [CALayer layer]; [self.layer addSublayer:_controls];
        _ring = shape(_controls); _ring.fillColor = k_ringFill.CGColor;
        _knob = shape(_controls);
        _rightRing=shape(_controls);_rightKnob=shape(_controls);_rightLabel=label(_rightKnob,@"R");
        CAShapeLayer *in = [CAShapeLayer layer]; in.fillColor = nil; in.strokeColor = k_line.CGColor; in.lineWidth = 1.5;   // inner ring of the knob
        [_knob addSublayer:in];
        static NSString *const names[B_N] = {@"A", @"B", @"X", @"Y", @"L3", @"R3", @"L", @"R", @"ZL", @"ZR", @"+", @"−"};
        for (int b = 0; b < B_N; b++) {
            _key[b] = shape(_controls);
            if (names[b]) _label[b] = label(_key[b], names[b]);   // the D-pad arms carry no label
        }
        _swap = shape(_controls); _swapLabel = label(_swap, @"");
        if(!preview)migrate_full_layout_defaults(NSUserDefaults.standardUserDefaults);
        NSNumber *saved = [NSUserDefaults.standardUserDefaults objectForKey:k_layout_key];
        int l = saved ? (int)saved.integerValue : DM_GAME_PAD_LAYOUT;
        if (l == 2 && dm_opmode() != 0) l = 0;   // Tap only in handheld mode (env.txt's DM_OPMODE may have changed it)
        _full = l == 1; _tap = l == 2;
        [self reloadProfile:nil];
        [self applyLayout];
        if(preview){_full=YES;_tap=NO;_nativeSurface=YES;[self applyLayout];return self;}
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserver:self selector:@selector(reloadProfile:) name:@"DmTouchProfileChanged" object:nil];
        [nc addObserver:self selector:@selector(padsChanged) name:GCControllerDidConnectNotification object:nil];
        [nc addObserver:self selector:@selector(padsChanged) name:GCControllerDidDisconnectNotification object:nil];
        [self padsChanged];
        __weak DmGamepad *weak=self;
        _artTimer=[NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer*t){[weak updateArtwork];}];
        [NSRunLoop.mainRunLoop addTimer:_artTimer forMode:NSRunLoopCommonModes];
        [self artworkMode:(int)[NSUserDefaults.standardUserDefaults integerForKey:@"DmPadVisibility"]];
        motion_start();
    }
    return self;
}
- (void)applyLayout {   // show / hide the controls for the current layout
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (int b = 0; b < B_N; b++) _key[b].hidden = _tap || (fullOnly(b) && !_full);
    _ring.hidden = _knob.hidden = _tap;
    _rightRing.hidden=_rightKnob.hidden=![self fixedRight] || !_full || _tap;
    _swap.hidden=!_previewMode;
    _swapLabel.string = @"⋯";
    [CATransaction commit];
}
- (int)selectedLayout { return _tap ? 2 : _full ? 1 : 0; }
- (void)selectLayout:(int)layout {
    if(layout<0 || layout>2 || (layout==2 && dm_opmode()!=0))return;
    [self reset];_full=layout==1;_tap=layout==2;
    [NSUserDefaults.standardUserDefaults setInteger:layout forKey:k_layout_key];
    [self applyLayout];[self setNeedsLayout];
}
- (void)nextLayout {
    [self selectLayout:_tap ? 0 : _full ? (dm_opmode()==0 ? 2 : 0) : 1];
}
- (CGRect)settingsRect {
    CGRect safe=self.safe;CGFloat d=MIN([self pillRect:B_MINUS].size.height,MIN(safe.size.width,safe.size.height));
    if(d<=0)return CGRectNull;
    CGPoint p=self.swapCenter;
    p.x=MIN(CGRectGetMaxX(safe)-d/2,MAX(CGRectGetMinX(safe)+d/2,p.x));
    p.y=MIN(CGRectGetMaxY(safe)-d/2,MAX(CGRectGetMinY(safe)+d/2,p.y));
    return CGRectMake(p.x-d/2,p.y-d/2,d,d);
}
- (CGFloat)settingsIconSize { return 18*self.u; }

// ---- Layout (points; computed inside the safe area) ----
- (dm_companion_pad_layout)sideGeometry {
    if(!CGRectIsEmpty(_companionCanvas)){
        dm_companion_surface_layout s=dm_companion_surface_make(_companionCanvas.size,1);
        CGRect left=CGRectIntersection(self.bounds,CGRectOffset(s.left,_companionCanvas.origin.x,_companionCanvas.origin.y));
        CGRect right=CGRectIntersection(self.bounds,CGRectOffset(s.right,_companionCanvas.origin.x,_companionCanvas.origin.y));
        return dm_companion_pad_geometry_regions(self.bounds.size,self.controlScale,left,right);
    }
    return dm_companion_pad_geometry_scaled(self.bounds.size,self.controlScale);
}
- (void)companionCanvas:(CGRect)frame {
    if(CGRectEqualToRect(frame,_companionCanvas))return;
    [self reset];_companionCanvas=frame;[self setNeedsLayout];
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if(_suppressed || _padOff || !CGRectContainsPoint(self.bounds,point))return NO;
    if(_sideControls){dm_companion_pad_layout p=self.sideGeometry;if(!CGRectContainsPoint(p.left,point)&&!CGRectContainsPoint(p.right,point))return NO;}
    // Active keyboard editing owns the game canvas. Drawing only owns it while the
    // pad is suppressed; restored artwork must also restore its hit regions.
    if(!_previewMode && _nativeSurface && !_sideControls && front_native_keyboard_controls_hidden(dm_view_touch_context()))return NO;
    if(!_nativeSurface && !_sideControls)return [super pointInside:point withEvent:event];
    if(_fade.mode==2)return NO;
    if([self inSwap:point])return YES;
    if(_tap)return NO;
    if([self btnAt:point]>=0)return YES;
    if([self faceGrabFraction:point]<=1)return YES;
    if(dist(point,self.stickHome)<=[self stickGrabRadius:0])return YES;
    return _full && (dist(point,self.dpadCenter)<=self.dpadGrabRadius || [self inRightArea:point]);
}
- (CGPoint)rightHome {
    CGRect s=self.corner;CGPoint p=_sideControls ? self.sideGeometry.right_stick : side(s,1,K_LOW_X*self.u,CGRectGetMaxY(s)-K_LOW_Y*self.u);
    return [self moved:p group:@"rightStick" radius:[self stickR:1]];
}

- (UIEdgeInsets)controlInsets {
    UIEdgeInsets i=self.safeAreaInsets;
    // Outer-display controls use the full width, including the camera side.
    // Keep the home-indicator inset; portrait companion geometry is separate.
    if(front_controls_full_canvas())i.left=i.right=0;
    return i;
}
- (CGRect)safe { return _sideControls ? self.bounds : UIEdgeInsetsInsetRect(self.bounds, self.controlInsets); }
- (CGRect)corner { if(_sideControls)return self.bounds; UIEdgeInsets i = self.controlInsets; i.left *= K_CORNER_IN; i.right *= K_CORNER_IN; return UIEdgeInsetsInsetRect(self.bounds, i); }   // the rectangle the bottom-corner controls use
- (CGFloat)u { return _sideControls ? self.sideGeometry.unit : MIN(self.bounds.size.height / 430.0, 1.3)*self.controlScale; }   // 1 = 430 points tall (iPhone Pro Max landscape)
static CGPoint side(CGRect s, int right, CGFloat dx, CGFloat y) { return CGPointMake(right ? CGRectGetMaxX(s) - dx : CGRectGetMinX(s) + dx, y); }
- (CGPoint)faceCenter {CGRect s=self.corner;CGFloat u=self.u;CGPoint p=_sideControls ? self.sideGeometry.face : side(s,1,K_FACE_X*u,CGRectGetMaxY(s)-K_PAD_Y*u);return [self moved:p group:@"face" radius:self.faceGap+self.faceR];}
- (CGFloat)faceGap { return _sideControls ? self.sideGeometry.face_gap : K_FACE_GAP*self.u; }
- (CGFloat)faceR { return _sideControls ? self.sideGeometry.face_r : K_FACE_R*self.u; }
static CGFloat faceDistance(CGPoint p,CGPoint center,CGFloat xScale,CGFloat yScale) {
    return hypot((p.x-center.x)/xScale,(p.y-center.y)/yScale);
}
- (CGFloat)faceGrabFraction:(CGPoint)p {
    if(!_sideControls)return dist(p,self.faceCenter)/(self.faceGap+self.faceR*1.6);
    dm_companion_pad_layout g=self.sideGeometry;
    CGFloat extent=g.face_gap+g.face_hit_r;
    return extent>0 ? faceDistance(p,self.faceCenter,g.face_x_scale,g.face_y_scale)/extent : INFINITY;
}
- (CGPoint)facePos:(int)b { CGPoint c = self.faceCenter; CGFloat x = self.faceGap;
    CGFloat y=x;
    if(_sideControls){dm_companion_pad_layout g=self.sideGeometry;x*=g.face_x_scale;y*=g.face_y_scale;}
    switch (b) { case B_A: return CGPointMake(c.x+x,c.y); case B_B: return CGPointMake(c.x,c.y+y); case B_X: return CGPointMake(c.x,c.y-y); default: return CGPointMake(c.x-x,c.y); } }
- (CGPoint)outerLeftStick {
    CGFloat u=self.u;CGRect s=self.corner;
    CGFloat x=CGRectGetMinX(self.safe)+K_ZL_X*u+MAX(K_ZL_R,K_L_R)*u*1.35+[self stickR:0]*K_STICK_GRAB+8*u;
    return CGPointMake(MIN(CGRectGetMidX(s)-[self stickR:0],x),CGRectGetMaxY(s)-K_PAD_Y*u);
}
- (CGPoint)stickHome {CGRect s=self.corner;CGPoint p=_sideControls ? self.sideGeometry.stick : front_controls_full_canvas()?self.outerLeftStick:side(s,0,K_STICK_X*self.u,CGRectGetMaxY(s)-K_PAD_Y*self.u);return [self moved:p group:@"leftStick" radius:[self stickR:0]];}   // the left stick's ring centre
- (CGPoint)stickCentre:(int)i { return i ? ([self fixedRight] ? self.rightHome : _rCentre) : self.stickHome; }
- (CGFloat)stickR:(int)i { return _sideControls ? (i ? self.sideGeometry.right_r : self.sideGeometry.stick_r) : (i ? K_RSTICK_R : K_STICK_R)*self.u; }
- (CGFloat)stickGrabRadius:(int)i {
    return _sideControls ? dm_companion_pad_stick_extent(self.sideGeometry,i) : [self stickR:i]*K_STICK_GRAB;
}
- (CGFloat)stickKnobRadius { return _sideControls ? self.sideGeometry.knob_r : K_KNOB_R*self.u; }
- (BOOL)inRightArea:(CGPoint)p { if([self fixedRight]){return dist(p,self.rightHome)<=[self stickGrabRadius:1];} CGRect b = self.bounds; return p.x >= CGRectGetMaxX(b) - b.size.width * K_RSWIPE; }
- (CGPoint)dpadCenter {CGRect s=self.corner;CGFloat u=self.u;CGPoint p=_sideControls ? self.sideGeometry.dpad : side(s,0,K_LOW_X*u,CGRectGetMaxY(s)-K_LOW_Y*u);
    if(!_sideControls && front_controls_full_canvas()){p=self.outerLeftStick;p.y-=[self stickR:0]*K_STICK_GRAB+self.dpadR*K_DPAD_GRAB+8*u;}
    return [self moved:p group:@"dpad" radius:self.dpadR];}
- (CGFloat)dpadR { return _sideControls ? self.sideGeometry.dpad_r : K_DPAD_R*self.u; }
- (CGFloat)dpadGrabRadius { return _sideControls ? self.sideGeometry.dpad_hit_r : self.dpadR*K_DPAD_GRAB; }
static BOOL isDrop(int b) { return b == B_ZL || b == B_L || b == B_ZR || b == B_R; }
static BOOL isClick(int b) { return b == B_LS || b == B_RS; }
- (CGPoint)dropCenter:(int)b { CGRect s = self.safe; CGFloat u = self.u; BOOL z = b == B_ZL || b == B_ZR;
    CGPoint p=_sideControls ? self.sideGeometry.shoulder[b==B_ZL ? 0 : b==B_L ? 1 : b==B_ZR ? 2 : 3] : side(s,b==B_ZR || b==B_R,(z ? K_ZL_X:K_L_X)*u,CGRectGetMinY(s)+(z ? K_ZL_Y:K_L_Y)*u);
    if(!_sideControls && front_controls_outer_display() && (b==B_ZL || b==B_L)){
        // Compact phone environments, including the Duo cover screen, stack the
        // left shoulders in the lower rail; full-size environments mirror the
        // right column.
        p.y=CGRectGetMaxY(s)-(K_L_R*1.05+8)*u;
        if(z)p.y-=((K_L_R+K_ZL_R)*1.05+12)*u;
    }
    return [self moved:p group:(b==B_ZR || b==B_R) ? @"shoulderR":@"shoulderL" radius:[self dropR:b]*K_DROP_TIP];}
- (CGFloat)dropR:(int)b { return _sideControls ? self.sideGeometry.shoulder_r : (b == B_ZL || b == B_ZR ? K_ZL_R : K_L_R)*self.u; }
- (CGFloat)clickR { return _sideControls ? self.sideGeometry.click_r : K_CLICK_R*self.u; }
- (CGPoint)clickCenter:(int)b {CGRect s=self.safe;CGFloat u=self.u;CGPoint p=_sideControls ? self.sideGeometry.click[b==B_RS ? 1:0] : side(s,b==B_RS,K_CLICK_X*u,CGRectGetMinY(s)+K_ZL_Y*u);return [self moved:p group:b==B_RS ? @"clickR":@"clickL" radius:self.clickR];}
- (CGRect)pillRect:(int)b {
    if(_sideControls){dm_companion_pad_layout g=self.sideGeometry;CGPoint c=[self moved:g.menu[b==B_PLUS ? 1:0] group:b==B_PLUS ? @"plus":@"minus" radius:g.menu_size.width/2];return CGRectMake(c.x-g.menu_size.width/2,c.y-g.menu_size.height/2,g.menu_size.width,g.menu_size.height);}
    CGRect s = self.safe; CGFloat u = self.u, w = K_PILL_W * u, h = (_sideControls ? 36 : K_PILL_H) * u;
    CGPoint c = CGPointMake(CGRectGetMidX(s) + (b == B_PLUS ? K_PILL_DX : -K_PILL_DX) * u, CGRectGetMinY(s) + (_sideControls ? 28 : K_PILL_Y) * u);   // − on the left, + on the right
    c=[self moved:c group:b==B_PLUS ? @"plus":@"minus" radius:w/2];return CGRectMake(c.x-w/2,c.y-h/2,w,h);}
- (CGPoint)swapCenter {CGRect s=self.safe;CGPoint p=_sideControls ? self.sideGeometry.swap : CGPointMake(CGRectGetMidX(s),CGRectGetMinY(s)+K_PILL_Y*self.u);return [self moved:p group:@"layout" radius:self.swapR];}
- (CGFloat)swapR { return _sideControls ? self.sideGeometry.swap_r : K_SWAP_R*self.u; }

static CGFloat dist(CGPoint a, CGPoint b) { return hypot(a.x - b.x, a.y - b.y); }
- (int)btnAt:(CGPoint)p {   // locked keys (tested on touch-down only, then locked)
    dm_companion_pad_layout sideGeometry=_sideControls ? self.sideGeometry : (dm_companion_pad_layout){0};
    for (int i = 0; i < (int)(sizeof k_btns / sizeof *k_btns); i++) { int b = k_btns[i];
        if (fullOnly(b) && !_full) continue;
        BOOL hit;
        if(isDrop(b)){
            CGFloat radius=_sideControls ? sideGeometry.shoulder_hit_r : [self dropR:b]*1.35;
            hit=dist(p,[self dropCenter:b])<=radius;
            // A resized teardrop can extend beyond the circular tap target.
            if(!hit && _sideControls && _key[b].path)hit=CGPathContainsPoint(_key[b].path,NULL,p,false);
        } else if(isClick(b)){
            hit=dist(p,[self clickCenter:b])<=(_sideControls ? sideGeometry.click_hit_r : self.clickR*1.35);
        } else {
            CGRect rect=[self pillRect:b];
            if(_sideControls){
                CGSize target=sideGeometry.menu_hit_size;
                rect=CGRectInset(rect,(rect.size.width-target.width)/2,(rect.size.height-target.height)/2);
            } else rect=CGRectInset(rect,-8*self.u,-8*self.u);
            hit=CGRectContainsPoint(rect,p);
        }
        if (hit) return b; }
    return -1;
}
- (BOOL)inSwap:(CGPoint)p { return _previewMode && dist(p, self.swapCenter) <= self.swapR * 1.6; }
- (uint64_t)faceAt:(CGPoint)p {   // keys under the finger in the diamond (between two keys both count)
    dm_companion_pad_layout g=_sideControls ? self.sideGeometry : (dm_companion_pad_layout){0};
    CGFloat r=_sideControls ? g.face_hit_r : self.faceR*1.25;
    CGFloat xScale=fmax(1,g.face_x_scale),yScale=fmax(1,g.face_y_scale);
    uint64_t m=0;
    for (int b = B_A; b <= B_Y; b++) if (faceDistance(p,[self facePos:b],xScale,yScale)<=r) m|=1ull<<b;
    return m;
}
- (uint64_t)dpadAt:(CGPoint)p {   // 8 directions: 45° each, diagonals press two keys; a small centre circle counts as none
    CGPoint c = self.dpadCenter; CGFloat dx = p.x - c.x, dy = p.y - c.y;
    if (hypot(dx, dy) < self.dpadR * 0.25) return 0;
    double a = atan2(-dy, dx) * 180 / M_PI; uint64_t m = 0;
    if (a > -67.5 && a < 67.5) m |= 1ull << B_RIGHT;
    if (a > 22.5 && a < 157.5) m |= 1ull << B_UP;
    if (a > 112.5 || a < -112.5) m |= 1ull << B_LEFT;
    if (a < -22.5 && a > -157.5) m |= 1ull << B_DOWN;
    return m;
}
- (CGPoint)stickOffset:(int)i {   // complete HID throw, independent of knob artwork
    if (!_stick[i]) return CGPointZero;
    CGPoint h = [self stickCentre:i]; CGFloat dx = _stickNow[i].x - h.x, dy = _stickNow[i].y - h.y, d = hypot(dx, dy), R = [self stickR:i];
    if (d > R) { dx *= R / d; dy *= R / d; }
    return CGPointMake(dx, dy);
}
- (CGPoint)knobOffset:(int)i {
    CGPoint p=[self stickOffset:i];CGFloat r=[self stickR:i];
    // Keep companion artwork inside the ring without shortening the HID throw.
    if(_sideControls && r>0){CGFloat travel=fmax(0,r-self.stickKnobRadius)/r;p.x*=travel;p.y*=travel;}
    return p;
}

// ---- Touch ----
- (void)recompute {
    uint64_t face = 0; for (UITouch *t in _faceOf) face |= [_faceOf objectForKey:t].unsignedLongLongValue;
    uint64_t btn = 0, dpad = 0; BOOL swap = NO;
    for (UITouch *t in _owner) { uint64_t v = [_owner objectForKey:t].unsignedLongLongValue; int c = (int)(v & 0xff);
        if (c == C_BTN) btn |= 1ull << (v >> 8);
        else if (c == C_DPAD) dpad |= [self dpadAt:[t locationInView:self]];
        else if (c == C_SWAP) swap = YES; }
    int32_t ax[4] = {0};
    CGFloat deadZone = [self customNumber:@"deadZone" fallback:K_DEAD low:0 high:.3];
    for (int i = 0; i < 2; i++) {
        CGPoint o = [self stickOffset:i]; CGFloat R = [self stickR:i], d = hypot(o.x, o.y), dz = R * deadZone;
        if (d <= dz) continue;
        CGFloat full = R * K_FULL;
        CGFloat tilt = fmin((d - dz) / (full - dz), 1);
        if (i == 0 && tilt < 1) {
            CGFloat original = dm_touch_default_slow_walk_radius(deadZone);
            CGFloat fraction = [self customNumber:@"slowWalkRadius" fallback:original
                                               low:fmax(.20, deadZone + .05) high:.70];
            if (fraction != original) {
                // Both ramps meet at the slow-walk boundary. Direction and full tilt stay intact.
                CGFloat walk = R * fraction;
                if (d <= walk) tilt = K_WALK_TILT * (d - dz) / (walk - dz);
                else tilt = K_WALK_TILT + (1 - K_WALK_TILT) * (d - walk) / (full - walk);
            }
        }
        CGFloat m = tilt / d;
        ax[i * 2] = (int32_t)lrint(o.x * m * 32767); ax[i * 2 + 1] = (int32_t)lrint(-o.y * m * 32767);   // host: up is positive; rounded so full tilt is exactly 32767
    }
    BOOL changed = face != _faceBits || dpad != _dpadBits || btn != _btnBits || swap != _swapHeld;
    uint64_t pressed = (face | dpad | btn) & ~(_faceBits | _dpadBits | _btnBits);
    unsigned gripping = (_stick[0] ? 1u : 0) | (_stick[1] ? 2u : 0);
    if (pressed || (swap && !_swapHeld) || (gripping & ~_hapticSticks)) {
        [_touchFeedback impactOccurredWithIntensity:0.6]; [_touchFeedback prepare];
    }
    _hapticSticks = gripping;
    _faceBits = face; _dpadBits = dpad; _btnBits = btn; _swapHeld = swap;
    pthread_mutex_lock(&g_mu);
    g_touch_btn = face | dpad | btn; g_touch_lx = ax[0]; g_touch_ly = ax[1]; g_touch_rx = ax[2]; g_touch_ry = ax[3];
    pthread_mutex_unlock(&g_mu);
    publish();
    BOOL stick = _stick[0] != nil || ([self fixedRight] && _stick[1] != nil);   // refresh the visible right stick in companion mode as well
    if (changed || stick || _stickShown) [self refresh];   // also refresh on the stick release so the knob returns to the centre
    _stickShown = stick;
}
// Touches no control takes (all of them while a physical controller is connected) go to the game's touch screen, normalized on the 16:9 picture that front_ios.m
// centres in the screen: Super Mario Galaxy's pointer in handheld mode (profile op_mode). The host reports them only in handheld mode, as on the Switch (hle_hid.c touch_read)
- (void)pushGame {
    if(_nativeSurface)return;
    CGRect b = self.bounds; CGFloat w = b.size.width, h = b.size.height;
    if (w <= 0 || h <= 0) return;
    if (w / h > 16.0 / 9.0) w = h * 16.0 / 9.0; else h = w * 9.0 / 16.0;
    CGFloat x0 = (b.size.width - w) / 2, y0 = (b.size.height - h) / 2;
    dm_touch t[16]; int n = 0;
    for (int i = 0; i < 16; i++) if (_game[i]) {
        CGPoint p = [_game[i] locationInView:self];
        t[n++] = (dm_touch){(uint32_t)i, (float)fmin(fmax((p.x - x0) / w, 0), 0.999), (float)fmin(fmax((p.y - y0) / h, 0), 0.999)};
    }
    dm_touch_set(t, n);
}
- (BOOL)gameBegin:(UITouch *)t {
    if(_sideControls || _suppressed || _nativeSurface)return NO;
    for (int i = 0; i < 16; i++) if (!_game[i]) { _game[i] = t; [_owner setObject:@(C_GAME | (uint64_t)i << 8) forKey:t]; return YES; }
    return NO;
}
- (void)touchesBegan:(NSSet<UITouch *> *)ts withEvent:(UIEvent *)e {
    BOOL game = NO;
    if(_suppressed)return;
    for (UITouch *t in ts) {
        if (_padOff) { game |= [self gameBegin:t]; continue; }
        CGPoint p = [t locationInView:self]; int hit = _tap ? -1 : [self btnAt:p];
        if (hit >= 0) { [_owner setObject:@(C_BTN | (uint64_t)hit << 8) forKey:t]; continue; }
        if ([self inSwap:p]) { [_owner setObject:@(C_SWAP) forKey:t]; continue; }
        if (_tap) { game |= [self gameBegin:t]; continue; }
        // diamond, D-pad, left stick: take the one with the smallest distance / grab radius, if it is <= 1
        CGFloat best = 1; int kind = C_NONE, idx = 0;
        CGFloat f = [self faceGrabFraction:p]; if (f <= best) { best = f; kind = C_FACE; }
        if (_full) { CGFloat d = dist(p, self.dpadCenter) / self.dpadGrabRadius; if (d < best) { best = d; kind = C_DPAD; } }
        if (!_stick[0]) { CGFloat s = dist(p, self.stickHome) / [self stickGrabRadius:0]; if (s < best) { best = s; kind = C_STICK; } }
        if (kind == C_NONE && _full && !_stick[1] && [self inRightArea:p]) { kind = C_STICK; idx = 1; _rCentre = p; }   // the right stick: centred where the touch lands
        if (kind == C_FACE) { [_owner setObject:@(C_FACE) forKey:t]; [_faceOf setObject:@([self faceAt:p]) forKey:t]; }
        else if (kind == C_DPAD) [_owner setObject:@(C_DPAD) forKey:t];
        else if (kind == C_STICK) { [_owner setObject:@(C_STICK | (uint64_t)idx << 8) forKey:t]; _stick[idx] = t; _stickNow[idx] = p; }
        else game |= [self gameBegin:t];
    }
    if (game) [self pushGame];
    [self recompute];[self artworkEvent];
}
- (void)touchesMoved:(NSSet<UITouch *> *)ts withEvent:(UIEvent *)e {
    BOOL game = NO;
    for (UITouch *t in ts) {
        uint64_t v = [_owner objectForKey:t].unsignedLongLongValue; int c = (int)(v & 0xff); CGPoint p = [t locationInView:self];
        if (c == C_FACE) [_faceOf setObject:@([self faceAt:p]) forKey:t];
        else if (c == C_STICK) { _stickNow[v >> 8] = p;
            if ((v >> 8) == 1 && ![self fixedRight]) { CGFloat d = dist(p, _rCentre), R = [self stickR:1];   // the right stick's centre follows a finger past its radius, so turning back responds at once
                if (d > R) _rCentre = CGPointMake(p.x - (p.x - _rCentre.x) * R / d, p.y - (p.y - _rCentre.y) * R / d); } }
        else if (c == C_GAME) game = YES;
    }
    if (game) [self pushGame];
    [self recompute];[self artworkEvent];
}
- (void)endTouches:(NSSet<UITouch *> *)ts tapped:(BOOL)ended {
    BOOL swap = NO, game = NO;
    for (UITouch *t in ts) {
        uint64_t v = [_owner objectForKey:t].unsignedLongLongValue;
        if (ended && (v & 0xff) == C_SWAP && [self inSwap:[t locationInView:self]]) swap = YES;   // layout button: counts only when released on the button
        if ((v & 0xff) == C_GAME && (v >> 8) < 16) { _game[v >> 8] = nil; game = YES; }
        [_owner removeObjectForKey:t]; [_faceOf removeObjectForKey:t]; for (int i = 0; i < 2; i++) if (t == _stick[i]) _stick[i] = nil;
    }
    if (game) [self pushGame];
    [self recompute];
    [self artworkEvent];
    if (swap) [self nextLayout];
}
- (void)touchesEnded:(NSSet<UITouch *> *)ts withEvent:(UIEvent *)e { [self endTouches:ts tapped:YES]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)ts withEvent:(UIEvent *)e { [self endTouches:ts tapped:NO]; }
- (void)reset {if(_previewMode)return;[_owner removeAllObjects]; [_faceOf removeAllObjects]; _stick[0] = _stick[1] = nil; for (int i = 0; i < 16; i++) _game[i] = nil; _fade.active=0;_fade.session=0; [self pushGame]; [self recompute]; }

// ---- Shapes ----
static CGPathRef circlePath(CGPoint c, CGFloat r) { return CGPathCreateWithEllipseInRect(CGRectMake(c.x - r, c.y - r, 2 * r, 2 * r), NULL); }
static CGPathRef dropPath(CGPoint c, CGFloat r, CGFloat tipAngle, CGFloat round) {   // teardrop: circle + two tangents meeting at the tip, tip slightly rounded
    CGFloat d = r * K_DROP_TIP, th = acos(r / d);
    CGPoint tip = CGPointMake(c.x + d * cos(tipAngle), c.y + d * sin(tipAngle));
    CGPoint p1 = CGPointMake(c.x + r * cos(tipAngle + th), c.y + r * sin(tipAngle + th)), p2 = CGPointMake(c.x + r * cos(tipAngle - th), c.y + r * sin(tipAngle - th));
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, p2.x, p2.y);
    CGPathAddArcToPoint(p, NULL, tip.x, tip.y, p1.x, p1.y, round);
    CGPathAddArc(p, NULL, c.x, c.y, r, tipAngle + th, tipAngle - th + 2 * M_PI, false);
    CGPathCloseSubpath(p); return p;
}
static CGPathRef armPath(CGPoint c, CGFloat R, CGFloat w, CGFloat in, CGFloat angle, CGFloat round) {   // one D-pad arm: an upward pentagon (tip toward the centre) rotated by angle around the centre
    CGPoint v[5] = {{-w, -R}, {w, -R}, {w, -(in + w)}, {0, -in}, {-w, -(in + w)}};
    CGFloat cs = cos(angle), sn = sin(angle);
    for (int i = 0; i < 5; i++) v[i] = CGPointMake(c.x + v[i].x * cs - v[i].y * sn, c.y + v[i].x * sn + v[i].y * cs);
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, (v[4].x + v[0].x) / 2, (v[4].y + v[0].y) / 2);
    for (int i = 0; i < 5; i++) CGPathAddArcToPoint(p, NULL, v[i].x, v[i].y, v[(i + 1) % 5].x, v[(i + 1) % 5].y, round);
    CGPathCloseSubpath(p); return p;
}
static void setPath(CAShapeLayer *l, CGPathRef p) { l.path = p; l.shadowPath = p; CGPathRelease(p); }
static void placeLabel(CATextLayer *t, CGPoint c, CGFloat fs) {
    CTFontRef f = CTFontCreateUIFontForLanguage(kCTFontUIFontEmphasizedSystem, fs, NULL);
    t.font = f; t.fontSize = fs;
    CGFloat h = CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f), w = fs * 3;
    t.frame = CGRectMake(c.x - w / 2, c.y - h / 2, w, h);
    CFRelease(f);
}

- (void)nativeSurface:(BOOL)enabled {if(_nativeSurface==enabled)return;[self reset];_nativeSurface=enabled;[self applyLayout];[self setNeedsLayout];}
- (void)artworkMode:(int)mode {_fade.mode=MAX(0,MIN(2,mode));_fade.session=0;if(_fade.mode==2 && !_sideControls)[self reset];[self updateArtwork];}
- (void)artworkEvent {if(_nativeSurface && !_sideControls){dm_control_fade_event(&_fade,_owner.count>0,CACurrentMediaTime());[self updateArtwork];}}
- (void)updateArtwork {
    // Reuse the existing main-thread artwork tick; keyboard lifetime must not
    // depend on finger-up events or add a rendering callback/timer.
    if(!_previewMode && _nativeSurface){
        front_native_ui_context(dm_view_touch_context());
    }
    float opacity=1;
    if(_nativeSurface && !_sideControls)opacity=dm_control_fade_hidden(&_fade,CACurrentMediaTime()) ? 0:0.65;
    if(_previewMode)opacity=1;opacity*=[self customNumber:@"opacity" fallback:1 low:.25 high:1];
    if(fabsf(_controls.opacity-opacity)<0.01)return;
    [CATransaction begin];[CATransaction setAnimationDuration:0.16];_controls.opacity=opacity;[CATransaction commit];
}
- (void)dealloc {[_artTimer invalidate];}
- (void)presentationCompanion:(BOOL)dock suppressed:(BOOL)suppressed {
    if(_sideControls==dock && _suppressed==suppressed)return;
    [self reset];_sideControls=dock;_suppressed=suppressed;
    if(!_previewMode)[self reloadProfile:nil];
    self.backgroundColor=UIColor.clearColor;
    [self applyLayout];[self updateArtwork];[self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // The suppressed companion controls have an empty frame in landscape. Do not build
    // teardrop arcs with radius zero during that transition (acos(0 / 0)).
    if(self.bounds.size.width<=0 || self.bounds.size.height<=0)return;
    CGFloat u = self.u;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _controls.frame = self.layer.bounds;
    for (int b = B_A; b <= B_Y; b++) { CGPoint c = [self facePos:b]; setPath(_key[b], circlePath(c, self.faceR)); placeLabel(_label[b], c, _sideControls?MAX(10,20*u):20*u); }
    for (int i = 0; i < (int)(sizeof k_btns / sizeof *k_btns); i++) { int b = k_btns[i];
        if (isDrop(b)) {
            BOOL right = b == B_ZR || b == B_R; CGPoint c = [self dropCenter:b];
            setPath(_key[b], dropPath(c, [self dropR:b], right ? -M_PI_4 : -3 * M_PI_4, 4 * u)); placeLabel(_label[b], c, _sideControls?MAX(8,16*u):16*u);   // tip toward the near top corner
        } else if (isClick(b)) {
            CGPoint c = [self clickCenter:b]; setPath(_key[b], circlePath(c, self.clickR)); placeLabel(_label[b], c, _sideControls?MAX(8,13*u):13*u);
        } else {
            CGRect rc = [self pillRect:b];
            setPath(_key[b], CGPathCreateWithRoundedRect(rc, rc.size.height / 2, rc.size.height / 2, NULL)); placeLabel(_label[b], CGPointMake(CGRectGetMidX(rc), CGRectGetMidY(rc)), _sideControls?MAX(9,18*u):18*u);
        }
    }
    static const struct { int b; CGFloat angle; } arms[] = {{B_UP, 0}, {B_RIGHT, M_PI_2}, {B_DOWN, M_PI}, {B_LEFT, -M_PI_2}};   // the same arm in 90° steps
    CGFloat dpadR=self.dpadR,armUnit=_sideControls ? dpadR/DM_COMPANION_DPAD_RADIUS : u;
    for (int i = 0; i < 4; i++) setPath(_key[arms[i].b], armPath(self.dpadCenter,dpadR,K_ARM_W*armUnit,K_ARM_IN*armUnit,arms[i].angle,6*armUnit));
    CGRect menu=self.settingsRect;CGPoint sc=CGPointMake(CGRectGetMidX(menu),CGRectGetMidY(menu));setPath(_swap,circlePath(sc,menu.size.height/2));placeLabel(_swapLabel,sc,12*u);
    setPath(_ring, circlePath(self.stickHome, [self stickR:0]));
    CGFloat k = self.stickKnobRadius;
    if([self fixedRight]){
        setPath(_rightRing,circlePath(self.rightHome,[self stickR:1]));
        _rightKnob.bounds=CGRectMake(0,0,2*k,2*k);
        setPath(_rightKnob,circlePath(CGPointMake(k,k),k));placeLabel(_rightLabel,CGPointMake(k,k),_sideControls?MAX(8,13*k/K_KNOB_R):13*u);
    }
    _knob.bounds = CGRectMake(0, 0, 2 * k, 2 * k);
    setPath(_knob, circlePath(CGPointMake(k, k), k));
    CAShapeLayer *in = (CAShapeLayer *)_knob.sublayers.firstObject; CGPathRef ip = circlePath(CGPointMake(k, k), k * 0.62);
    in.frame = _knob.bounds; in.path = ip; CGPathRelease(ip);
    [CATransaction commit];
    UIColor *line=_sideControls ? [UIColor colorWithRed:0.45 green:0.55 blue:0.46 alpha:0.7] : k_line;
    for(int b=0;b<B_N;b++)_key[b].strokeColor=line.CGColor;
    _swap.strokeColor=_ring.strokeColor=_knob.strokeColor=_rightRing.strokeColor=_rightKnob.strokeColor=line.CGColor;
    _ring.fillColor=(_sideControls ? [UIColor colorWithRed:0.56 green:0.72 blue:0.61 alpha:0.22] : k_ringFill).CGColor;
    _rightRing.fillColor=_ring.fillColor;
    [self refresh];
}
- (void)safeAreaInsetsDidChange { [super safeAreaInsetsDidChange]; [self setNeedsLayout]; }
- (void)refresh {   // pressed state → fill, sticks → knob position
    uint64_t all = _faceBits | _dpadBits | _btnBits;
    UIColor *idle=_sideControls ? [UIColor colorWithRed:1 green:0.98 blue:0.88 alpha:1] : k_idle;
    UIColor *pressed=_sideControls ? [UIColor colorWithRed:0.27 green:0.66 blue:0.58 alpha:1] : k_on;
    UIColor *text=_sideControls ? [UIColor colorWithRed:0.28 green:0.34 blue:0.26 alpha:1] : k_text;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (int b = 0; b < B_N; b++) { BOOL on = (all >> b) & 1;
        _key[b].fillColor = (on ? pressed : idle).CGColor; _label[b].foregroundColor = (on ? (_sideControls ? UIColor.whiteColor : k_textOn) : text).CGColor; }
    _swap.fillColor = (_swapHeld ? pressed : idle).CGColor; _swapLabel.foregroundColor = (_swapHeld ? (_sideControls ? UIColor.whiteColor : k_textOn) : text).CGColor;
    CGPoint h = self.stickHome, o = [self knobOffset:0];
    _knob.position = CGPointMake(h.x + o.x, h.y + o.y); _knob.fillColor = (_stick[0] ? pressed : idle).CGColor;
    if([self fixedRight]){
        CGPoint r=self.rightHome,o=[self knobOffset:1];
        _rightKnob.position=CGPointMake(r.x+o.x,r.y+o.y);_rightKnob.fillColor=(_stick[1] ? pressed : idle).CGColor;
        _rightLabel.foregroundColor=(_stick[1] ? UIColor.whiteColor : text).CGColor;
    }
    [CATransaction commit];
}

// ---- Physical controllers ----
static int32_t axis(float v) { return (int32_t)(fmaxf(-1.f, fminf(1.f, v)) * 32767); }
static void read_pad(GCExtendedGamepad *g) {
    dm_haptics_apple_controller(0, g.controller);
    uint64_t m = 0;
    #define K(btn, bit) if (btn.isPressed) m |= 1ull << bit
    K(g.buttonB, B_A); K(g.buttonA, B_B); K(g.buttonY, B_X); K(g.buttonX, B_Y);   // by position: right A, bottom B, top X, left Y
    K(g.leftShoulder, B_L); K(g.rightShoulder, B_R); K(g.leftTrigger, B_ZL); K(g.rightTrigger, B_ZR);
    K(g.buttonMenu, B_PLUS); if (g.buttonOptions) K(g.buttonOptions, B_MINUS);
    if (g.leftThumbstickButton) K(g.leftThumbstickButton, B_LS); if (g.rightThumbstickButton) K(g.rightThumbstickButton, B_RS);
    K(g.dpad.left, B_LEFT); K(g.dpad.up, B_UP); K(g.dpad.right, B_RIGHT); K(g.dpad.down, B_DOWN);
    #undef K
    pthread_mutex_lock(&g_mu);
    g_pad_btn = m; g_pad_lx = axis(g.leftThumbstick.xAxis.value); g_pad_ly = axis(g.leftThumbstick.yAxis.value);
    g_pad_rx = axis(g.rightThumbstick.xAxis.value); g_pad_ry = axis(g.rightThumbstick.yAxis.value);
    pthread_mutex_unlock(&g_mu);
    publish();
}
- (void)padsChanged {
    BOOL any = NO;
    for (GCController *c in GCController.controllers) if (c.extendedGamepad) {
        any = YES; c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *el) { (void)el; read_pad(g); };
        read_pad(c.extendedGamepad);
    }
    if (!any) { dm_haptics_apple_controller(0, nil); pthread_mutex_lock(&g_mu); g_pad_btn = 0; g_pad_lx = g_pad_ly = g_pad_rx = g_pad_ry = 0; pthread_mutex_unlock(&g_mu); publish(); }
    dispatch_async(dispatch_get_main_queue(), ^{ self->_padOff = any; self->_controls.hidden = any; [self reset]; });
}
@end

UIView *dm_gamepad_view(CGRect frame) { DmGamepad *v = [[DmGamepad alloc] initWithFrame:frame]; g_view = v; return v; }
UIView *dm_touch_controls_preview(BOOL portrait) {DmGamepad *v=[[DmGamepad alloc]initWithFrame:CGRectMake(0,0,834,440) preview:YES];[v configureProfile:@{} portrait:portrait];return v;}
void dm_touch_controls_configure(UIView *view,NSDictionary *profile,BOOL portrait){[(DmGamepad *)view configureProfile:profile portrait:portrait];}
NSArray *dm_touch_controls_handles(UIView *view){return [(DmGamepad *)view editingHandles];}
void dm_gamepad_presentation(BOOL dock, BOOL suppressed) { [g_view presentationCompanion:dock suppressed:suppressed]; }
void dm_gamepad_companion_frame(UIView *parent,CGRect frame) { [g_view companionCanvas:CGRectIsEmpty(frame)?CGRectZero:[g_view convertRect:frame fromView:parent]]; }
void dm_gamepad_native_surface(BOOL enabled) { [g_view nativeSurface:enabled]; }
void dm_gamepad_artwork_mode(int mode) { [g_view artworkMode:mode]; }
int dm_gamepad_layout(void) { return [g_view selectedLayout]; }
void dm_gamepad_select_layout(int layout) { [g_view selectLayout:layout]; }
CGRect dm_gamepad_settings_rect(UIView *parent) { return g_view ? [g_view convertRect:[g_view settingsRect] toView:parent] : CGRectNull; }
CGFloat dm_gamepad_settings_icon_size(void) { return g_view ? [g_view settingsIconSize]:18; }
void dm_gamepad_reset(void) {   // On resign active: release everything (a key held while switching away and released in background gets no "release")
    if(NSThread.isMainThread)[g_view reset];else dispatch_async(dispatch_get_main_queue(), ^{ [g_view reset]; });
    pthread_mutex_lock(&g_mu); g_pad_btn = 0; g_shake_btn = 0; g_pad_lx = g_pad_ly = g_pad_rx = g_pad_ry = 0; pthread_mutex_unlock(&g_mu); publish();
}
