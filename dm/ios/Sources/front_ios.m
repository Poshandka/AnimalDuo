// iOS front end: a scene-sized phone canvas or the regular fitted tablet game
// view, with an adaptive companion and virtual controls above the content.
// The host runs on the big-stack thread started by main.m; front_run runs the guest directly on the calling thread.
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <AVFAudio/AVFAudio.h>
#import <GameController/GameController.h>
#include <errno.h>
#include "front.h"
#include "hle.h"
#include "dm.h"
#include "haptics_apple.h"
#include "companion.h"
#include "companion_layout.h"
#include "control_presentation.h"
#include "present_layout.h"
#include "hle_lan.h"
#import "lan_wait_text_apple.h"
#include "DisplayOrientation.h"
#include <stdatomic.h>
#import "companion_apple.h"
void *dm_companion_view_controller(void);
void dm_companion_ui_state(int hidden,int physical,int presented);
static _Atomic int g_phone_canvas,g_display_policy_known;
static void front_ios_lan_audio(int paused);
static UIBackgroundTaskIdentifier g_lan_task;
static BOOL g_lan_task_active;
static unsigned g_lan_task_epoch;
static void front_lan_task_end(void) {
    if (!g_lan_task_active) return;
    UIBackgroundTaskIdentifier task = g_lan_task; g_lan_task = UIBackgroundTaskInvalid; g_lan_task_active = NO; g_lan_task_epoch++;
    [UIApplication.sharedApplication endBackgroundTask:task];
}
static void front_lan_task_prepare(void) {
    dm_lan_wait_info info; dm_lan_wait_snapshot(&info);
    if (!info.supported || g_lan_task_active) return;
    // Finish the pause notification/acknowledgement only. The 30/60 second room
    // reservation does not require the app to execute continuously in background.
    g_lan_task = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"Finish local-play pause" expirationHandler:^{front_lan_task_end();}];
    g_lan_task_active = g_lan_task != UIBackgroundTaskInvalid;
    if (!g_lan_task_active) return;
    unsigned epoch = ++g_lan_task_epoch;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{if (epoch == g_lan_task_epoch) front_lan_task_end();});
}
int front_controls_full_canvas(void) {
    // UIKit can query the launch policy before a root view or hinge observation
    // exists. Expanded Duo scenes subsequently publish their native policy.
    return atomic_load(&g_display_policy_known)?atomic_load(&g_phone_canvas):UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPhone;
}
UIInterfaceOrientationMask front_ios_orientation_mask(void) {
    if(!DMCompanion.shared.supported || front_controls_full_canvas())return UIInterfaceOrientationMaskLandscape;
    return UIInterfaceOrientationMaskAll;
}
static _Atomic int g_present_mode;
static _Atomic uint64_t g_present_source=(UINT64_C(1280)<<32)|720;
int front_present_mode(void) { int mode=atomic_load(&g_present_mode);return mode==DM_PRESENT_EXPAND && (!dm_view_available() || dm_view_aspect()<=0)?DM_PRESENT_FIT:mode; }
void front_present_source_size(unsigned w,unsigned h) { if(w&&h)atomic_store(&g_present_source,((uint64_t)w<<32)|h); }

UIView *dm_gamepad_view(CGRect frame);
void dm_gamepad_reset(void);
void dm_gamepad_presentation(BOOL companion, BOOL suppressed);
void dm_gamepad_companion_frame(UIView *parent,CGRect frame);
void dm_gamepad_native_surface(BOOL enabled);
void dm_gamepad_artwork_mode(int mode);
int dm_gamepad_layout(void);
void dm_gamepad_select_layout(int layout);
CGRect dm_gamepad_settings_rect(UIView *parent);
CGFloat dm_gamepad_settings_icon_size(void);
void front_ios_boot(void);
int front_ios_boot_ok(void);
bool dm_show_launcher(void *view_controller, void (*done)(void));   // Launcher.swift: false = no launcher (no dm/launcher.json, or DM_LAUNCHER=0)

static CAMetalLayer *g_layer;
static void front_ios_power_watch(void);
static void front_ios_audio_watch(void);
static UILabel *front_ios_fps_label(void);
static void front_native_touch_activity(int active);
static void front_startup_begin(void);
static void front_startup_tick(void);
static void front_loading_top(void);

@interface DmGameView : UIView
@property(nonatomic) BOOL nativeTouchEnabled;
- (void)cancelNativeTouches;
- (BOOL)nativePoint:(CGPoint)point x:(double *)x y:(double *)y;
@end
@implementation DmGameView {
    UITouch *_nativeTouches[16];CGSize _touchSize;
}
+ (Class)layerClass { return CAMetalLayer.class; }
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        CAMetalLayer *l = (CAMetalLayer *)self.layer;
        l.device = MTLCreateSystemDefaultDevice(); l.pixelFormat = MTLPixelFormatBGRA8Unorm;
        l.contentsScale = self.traitCollection.displayScale; l.framebufferOnly = NO; l.opaque = YES;
        self.backgroundColor = UIColor.blackColor;self.multipleTouchEnabled=YES;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if(!CGSizeEqualToSize(_touchSize,self.bounds.size)){[self cancelNativeTouches];_touchSize=self.bounds.size;}
    CAMetalLayer *l = (CAMetalLayer *)self.layer;
    CGFloat scale=self.window.windowScene.screen.nativeScale;
    if(scale<=0)scale=self.traitCollection.displayScale;
    l.contentsScale=scale>0?scale:1;
    l.drawableSize = CGSizeMake(self.bounds.size.width * l.contentsScale, self.bounds.size.height * l.contentsScale);
}
- (BOOL)nativePoint:(CGPoint)point x:(double *)x y:(double *)y {
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height;if(w<=0||h<=0)return NO;
    uint64_t source=atomic_load(&g_present_source);unsigned sw=(unsigned)(source>>32),sh=(unsigned)source;
    CGSize pixels=((CAMetalLayer*)self.layer).drawableSize;
    dm_present_layout layout=dm_present_layout_make(sw,sh,pixels.width,pixels.height,front_present_mode());
    return dm_present_touch(layout,sw,sh,point.x/w*pixels.width,point.y/h*pixels.height,x,y);
}
- (void)publishNativeTouches {
    if(!self.nativeTouchEnabled)return;
    dm_touch points[16];int count=0;
    for(int i=0;i<16;i++)if(_nativeTouches[i]){double u=0,v=0;[self nativePoint:[_nativeTouches[i]locationInView:self] x:&u y:&v];points[count++]=(dm_touch){(uint32_t)i,(float)fmin(u,0.999),(float)fmin(v,0.999)};}
    dm_touch_set(points,count);
    front_native_touch_activity(count>0 && dm_view_touch_context()!=0);
}
- (void)cancelNativeTouches {for(int i=0;i<16;i++)_nativeTouches[i]=nil;[self publishNativeTouches];}
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if(!self.nativeTouchEnabled){[super touchesBegan:touches withEvent:event];return;}
    for(UITouch *t in touches){double x=0,y=0;if(![self nativePoint:[t locationInView:self] x:&x y:&y])continue;for(int i=0;i<16;i++)if(!_nativeTouches[i]){_nativeTouches[i]=t;break;}}
    [self publishNativeTouches];
}
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {if(self.nativeTouchEnabled)[self publishNativeTouches];else [super touchesMoved:touches withEvent:event];}
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {for(UITouch*t in touches)for(int i=0;i<16;i++)if(_nativeTouches[i]==t)_nativeTouches[i]=nil;[self publishNativeTouches];}
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {[self touchesEnded:touches withEvent:event];}

@end

// The menu artwork follows the adjacent +/- height. Its invisible touch area
// remains usable without covering the portrait footer or leaving the canvas.
@interface DmControlsMenuButton : UIButton
@property(nonatomic) CGRect touchLimit;
@end
@implementation DmControlsMenuButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;CGFloat dx=MAX(0,(44-self.bounds.size.width)/2),dy=MAX(0,(44-self.bounds.size.height)/2);
    return CGRectContainsPoint(CGRectInset(self.bounds,-dx,-dy),point) && CGRectContainsPoint(self.touchLimit,[self convertPoint:point toView:self.superview]);
}
@end

@interface DmRootVC : UIViewController {
    dm_game_touch_controls _gameTouchState;uint64_t _gameTouchEpoch;
    dm_keyboard_controls _keyboardControls;
}
@property (nonatomic, strong) DmGameView *game;
@property (nonatomic, strong) UIView *canvas;
@property (nonatomic, strong) UIView *pad;
@property (nonatomic, strong) UILabel *fps;
@property (nonatomic, strong) UIViewController *companion;
@property (nonatomic) BOOL launched;
@property (nonatomic) BOOL foldingDevice;
@property (nonatomic) BOOL hingeStatusKnown,hingeClosed;
@property (nonatomic) BOOL displayRoleKnown,displayRoleOuter;
@property (nonatomic,strong) UIScreen *hingeScreen,*displayRoleScreen;
@property (nonatomic) UIInterfaceOrientationMask lastOrientationPolicy;
@property (nonatomic) BOOL nativeKeyboardActive;
@property (nonatomic) unsigned nativeContext;
@property (nonatomic) BOOL canvasInverted;
@property (nonatomic) NSInteger canvasQuarterTurns;
@property (nonatomic,strong) UIButton *visibilityButton;
@property (nonatomic,strong) UIView *lanWaitOverlay;
@property (nonatomic,strong) UILabel *lanWaitTitle,*lanWaitDetail;
@property (nonatomic,strong) UIButton *lanWaitButton;
@property (nonatomic,strong) NSTimer *lanWaitTimer;
@property (nonatomic) BOOL lanWaitDismissed;
- (void)updateLocalPlayWait;
- (void)scheduleLocalPlayPoll:(NSTimeInterval)seconds;
- (void)refreshCompanionControls;
- (void)companionActivity:(unsigned)source busy:(BOOL)busy;
- (void)gameTouchActivity:(BOOL)active;
- (void)nativeUIContext:(unsigned)context;
- (void)queueGameTouchRestoration;
- (void)updateOrientation:(BOOL)force;
- (void)hingeStatusChanged:(NSInteger)status;
- (void)hingeUnavailable;
- (void)displayTraitsChanged;
- (UIScreen *)activeDisplay;
- (BOOL)isOuterDisplay;
- (UIInterfaceOrientation)sceneOrientation;
- (void)applyCanvasOrientation;
- (UIEdgeInsets)canvasInsets;
- (UIDeviceOrientation)physicalOrientation;
- (void)startGame;
- (BOOL)showsCompanion;
- (BOOL)isStandardPhone;
- (BOOL)phoneHardware;
- (BOOL)usesAdaptiveCanvas;
- (NSString *)imageModePreferenceKey;
@end
static DmRootVC *g_root;
BOOL dm_canvas_half_turn(UIViewController *owner) {return [owner isKindOfClass:DmRootVC.class] && ((DmRootVC *)owner).canvasInverted;}
CGFloat dm_canvas_rotation(UIViewController *owner) {return [owner isKindOfClass:DmRootVC.class]?((DmRootVC *)owner).canvasQuarterTurns*M_PI_2:0;}
static void front_native_touch_activity(int active) { [g_root gameTouchActivity:active!=0]; }
void front_native_ui_context(unsigned context) { [g_root nativeUIContext:context];front_startup_tick(); }
int front_native_keyboard_controls_hidden(unsigned context) { [g_root nativeUIContext:context];return g_root.nativeKeyboardActive; }
void front_ios_geometry_changed(void) {
    [g_root.game cancelNativeTouches];dm_gamepad_reset();[g_root.view setNeedsLayout];
}
static void launcher_done(void) { [g_root startGame]; }
void dm_companion_ui_activity(int source,int busy) {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{dm_companion_ui_activity(source,busy);});return;}
    [g_root companionActivity:(unsigned)source busy:busy!=0];
}
@implementation DmRootVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.canvas=[[UIView alloc]initWithFrame:self.view.bounds];[self.view addSubview:self.canvas];
    [self registerForTraitChanges:@[UITraitHorizontalSizeClass.class,UITraitVerticalSizeClass.class] withHandler:^(id<UITraitEnvironment> environment,UITraitCollection *previous){
        (void)previous;[(DmRootVC *)environment displayTraitsChanged];
    }];
    front_ios_power_watch();
    // Runtime availability does not provide declarations to an older SDK.
    // Bounds/trait-driven layout remains available without hinge notifications.
#if __has_include(<UIKit/UIHingeInteraction.h>)
    if(@available(iOS 27.1,*)){
        __weak DmRootVC *weak=self;
        UIHingeInteraction *hinge=[[UIHingeInteraction alloc]initWithUpdateHandler:^(UIHingeInteraction *interaction,UIHingeInteractionUpdate *update){
            (void)interaction;DmRootVC *root=weak;
            if(update.hinge)[root hingeStatusChanged:update.hinge.status];else [root hingeUnavailable];
        }];
        [self.view addInteraction:hinge];
    }
#endif
    if (!front_ios_boot_ok()) {   // No game files: show a hint and do not start the host
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 40, 40)];
        lb.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        lb.numberOfLines = 0; lb.textAlignment = NSTextAlignmentCenter; lb.textColor = UIColor.whiteColor;
        lb.text = @"Game files not found.\nPut the RomFS folder into this App's Documents as \"romfs\" (Files app), then restart.";
        [self.view addSubview:lb]; return;
    }
    front_ios_audio_watch();
    NSNotificationCenter *nc=NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(presentationChanged:) name:@"DmTouchProfileChanged" object:nil];
    [nc addObserver:self selector:@selector(presentationChanged:) name:GCControllerDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(presentationChanged:) name:GCControllerDidDisconnectNotification object:nil];
    [nc addObserver:self selector:@selector(presentationChanged:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(presentationChanged:) name:UIApplicationWillResignActiveNotification object:nil];
}
// The game view, the pad and the frame-rate counter are made once the launcher has set the switches they read (DM_SHOW_FPS, DM_METAL_HUD); the host's loading began at app launch (main.m)
static void front_controls_defaults(void) {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    if([defaults boolForKey:@"DmControlsDefaultVisibleV2"])return;
    NSNumber *previous=[defaults objectForKey:@"DmPadVisibility"];
    if(!previous || previous.integerValue==0)[defaults setInteger:1 forKey:@"DmPadVisibility"];
    [defaults setBool:YES forKey:@"DmControlsDefaultVisibleV2"];
}
- (void)startGame {
    if (self.game) return;
    front_controls_defaults();
    front_hud_env();   // before the game view makes its device (an env file's DM_METAL_HUD sets it in main.m already)
    self.game = [[DmGameView alloc] initWithFrame:self.view.bounds];
    [self.canvas addSubview:self.game];
    g_layer = (CAMetalLayer *)self.game.layer;
    if (getenv("DM_METAL_HUD") && atoi(getenv("DM_METAL_HUD"))) { g_layer.developerHUDProperties = @{@"mode": @"default"}; LOG("front end: Metal performance HUD on (DM_METAL_HUD)"); }   // Apple's HUD over the game: frame rate, frame and GPU time, memory
    dm_haptics_apple_init();
    self.pad = dm_gamepad_view(self.view.bounds);
    self.pad.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.canvas addSubview:self.pad];
    self.fps = front_ios_fps_label();   // above the pad, which hides while a controller is connected
    if (self.fps) [self.canvas addSubview:self.fps];
    self.game.nativeTouchEnabled=YES;dm_touch_surface_available(1);dm_gamepad_native_surface(YES);
    if(DMCompanion.shared.supported){
        self.companion=(__bridge_transfer UIViewController *)dm_companion_view_controller();
        [self addChildViewController:self.companion];[self.canvas addSubview:self.companion.view];[self.companion didMoveToParentViewController:self];
        [self.canvas bringSubviewToFront:self.pad];
    }
    self.visibilityButton=[DmControlsMenuButton buttonWithType:UIButtonTypeSystem];
    [self.visibilityButton setImage:[UIImage systemImageNamed:@"slider.horizontal.3"] forState:UIControlStateNormal];
    self.visibilityButton.tintColor=[UIColor colorWithWhite:1 alpha:0.7];
    [self.visibilityButton setTitleColor:[UIColor colorWithWhite:1 alpha:0.65] forState:UIControlStateNormal];
    self.visibilityButton.backgroundColor=[UIColor colorWithWhite:0 alpha:0.16];self.visibilityButton.layer.cornerRadius=12;
    self.visibilityButton.showsMenuAsPrimaryAction=YES;[self.canvas addSubview:self.visibilityButton];[self updateVisibilityMenu];
    [self refreshCompanionControls];
    [self.view setNeedsLayout]; [self.view layoutIfNeeded];
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    front_startup_begin();front_ios_boot();
    [self scheduleLocalPlayPoll:1];
    [self updateLocalPlayWait];
}
- (BOOL)physicalController {
    for(GCController *c in GCController.controllers)if(c.extendedGamepad)return YES;
    return NO;
}
- (BOOL)showsCompanion {
    // Local available space owns layout, including compact inner windows and
    // intermediate screen/trait updates during a display handoff.
    return self.companion && !self.isStandardPhone && self.canvas.bounds.size.height>self.canvas.bounds.size.width;
}
- (BOOL)phoneHardware { return UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPhone; }
- (BOOL)isStandardPhone {
    if(!self.phoneHardware || self.foldingDevice)return NO;
    // A newly expanded phone can publish its regular environment before the
    // first hinge observation. That environment must retain the inner layout.
    return !(self.traitCollection.horizontalSizeClass==UIUserInterfaceSizeClassRegular && self.traitCollection.verticalSizeClass==UIUserInterfaceSizeClassRegular);
}
- (BOOL)usesAdaptiveCanvas { return self.foldingDevice || self.phoneHardware || UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad; }
- (NSString *)imageModePreferenceKey {
    if(!self.phoneHardware && !self.foldingDevice && UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad)return @"DmPadImageMode";
    return self.isStandardPhone?@"DmPhoneImageMode":@"DmFoldImageMode";
}
- (UIScreen *)activeDisplay { return self.view.window.windowScene.screen; }
- (void)displayTraitsChanged { [self updateOrientation:NO];[self.view setNeedsLayout]; }
- (void)hingeUnavailable {
    if(!self.foldingDevice)return;
    self.hingeStatusKnown=NO;self.hingeClosed=NO;self.hingeScreen=nil;
    [self updateOrientation:NO];[self.view setNeedsLayout];
}
- (void)hingeStatusChanged:(NSInteger)status {
    BOOL first=!self.foldingDevice;self.foldingDevice=YES;
    // Hinge observations belong to their current hierarchy. Unknown and nil
    // updates retire an old closed value instead of preserving it indefinitely.
    self.hingeStatusKnown=status!=0;self.hingeClosed=status==1;self.hingeScreen=[self activeDisplay];
    if(first)[self updateVisibilityMenu];
    [self updateOrientation:NO];[self.view setNeedsLayout];
}
- (BOOL)isOuterDisplay {
    if(!self.foldingDevice)return NO;
    UIScreen *screen=[self activeDisplay];BOOL screenChanged=screen!=self.displayRoleScreen;
    if(screenChanged){
        self.displayRoleKnown=NO;self.displayRoleScreen=screen;
        if(self.hingeScreen!=screen){self.hingeStatusKnown=NO;self.hingeClosed=NO;self.hingeScreen=nil;}
    }
    UIUserInterfaceSizeClass horizontal=self.traitCollection.horizontalSizeClass,vertical=self.traitCollection.verticalSizeClass;
    BOOL outer;
    if(horizontal!=UIUserInterfaceSizeClassUnspecified && vertical!=UIUserInterfaceSizeClassUnspecified){
        // Native traits describe the active environment. Hinge posture and a
        // cached minor dimension cannot override a newly expanded environment.
        outer=!(horizontal==UIUserInterfaceSizeClassRegular && vertical==UIUserInterfaceSizeClassRegular);
    }else if(self.hingeStatusKnown)outer=self.hingeClosed;
    else return self.displayRoleKnown?self.displayRoleOuter:NO;
    if(!self.displayRoleKnown || self.displayRoleOuter!=outer){
        LOG("display: active %s environment; traits %ld/%ld, hinge %s, view %.0fx%.0f",outer?"compact":"expanded",(long)horizontal,(long)vertical,self.hingeStatusKnown?(self.hingeClosed?"closed":"open"):"unavailable",self.view.bounds.size.width,self.view.bounds.size.height);
    }
    self.displayRoleKnown=YES;self.displayRoleOuter=outer;
    return self.displayRoleOuter;
}
- (void)updateVisibilityMenu {
    NSInteger mode=[NSUserDefaults.standardUserDefaults integerForKey:@"DmPadVisibility"];
    NSString *lang=getenv("DM_LANG") ? @(getenv("DM_LANG")):@"zh-Hans";
    NSString *path=[NSBundle.mainBundle pathForResource:lang ofType:@"lproj"];
    NSBundle *strings=path ? [NSBundle bundleWithPath:path]:NSBundle.mainBundle;
    NSString *(^tr)(NSString*)=^NSString*(NSString*k){return [strings localizedStringForKey:k value:k table:@"Companion"];};
    NSArray *titles=@[tr(@"Auto fade"),tr(@"Always show"),tr(@"Direct touch")];NSMutableArray *actions=[NSMutableArray new];
    __weak DmRootVC *weak=self;
    for(int i=0;i<3;i++){
        UIAction *a=[UIAction actionWithTitle:titles[i] image:nil identifier:nil handler:^(UIAction *a){
            [weak.game cancelNativeTouches];
            [NSUserDefaults.standardUserDefaults setInteger:i forKey:@"DmPadVisibility"];dm_gamepad_artwork_mode(i);[weak updateVisibilityMenu];[weak refreshCompanionControls];
        }];a.state=mode==i ? UIMenuElementStateOn:UIMenuElementStateOff;[actions addObject:a];
    }
    NSMutableArray *layouts=[NSMutableArray new];int selectedLayout=dm_gamepad_layout();
    NSArray *layoutTitles=dm_opmode()==0 ? @[@"2D",@"3D",tr(@"Touch")]:@[@"2D",@"3D"];
    for(int i=0;i<(int)layoutTitles.count;i++){
        UIAction *action=[UIAction actionWithTitle:layoutTitles[i] image:nil identifier:[NSString stringWithFormat:@"pad.layout.%d",i] handler:^(UIAction *action){
            [weak.game cancelNativeTouches];dm_gamepad_select_layout(i);[weak updateVisibilityMenu];[weak.view setNeedsLayout];
        }];action.state=i==selectedLayout?UIMenuElementStateOn:UIMenuElementStateOff;[layouts addObject:action];
    }
    [actions addObject:[UIMenu menuWithTitle:tr(@"Layout") children:layouts]];
    if(self.usesAdaptiveCanvas){
        NSArray *labels=@[tr(@"Expand game view"),tr(@"Fit entire image")];NSArray *values=@[@(DM_PRESENT_EXPAND),@(DM_PRESENT_FIT)];NSMutableArray *framing=[NSMutableArray new];
        NSString *key=self.imageModePreferenceKey;
        NSNumber *saved=[NSUserDefaults.standardUserDefaults objectForKey:key];NSInteger selected=saved && saved.intValue==DM_PRESENT_FIT?DM_PRESENT_FIT:DM_PRESENT_EXPAND;
        for(int i=0;i<2;i++){
            NSInteger value=[values[i]integerValue];
            UIAction *a=[UIAction actionWithTitle:labels[i] image:nil identifier:nil handler:^(UIAction *a){
                [weak.game cancelNativeTouches];dm_gamepad_reset();[NSUserDefaults.standardUserDefaults setInteger:value forKey:key];[weak updateVisibilityMenu];[weak.view setNeedsLayout];
            }];a.state=value==selected?UIMenuElementStateOn:UIMenuElementStateOff;[framing addObject:a];
        }
        [actions addObject:[UIMenu menuWithTitle:tr(@"Game image") children:framing]];
    }
    self.visibilityButton.menu=[UIMenu menuWithTitle:tr(@"Screen controls") children:actions];
    [self.visibilityButton setTitle:nil forState:UIControlStateNormal];
    self.visibilityButton.accessibilityLabel=tr(@"Screen controls");dm_gamepad_artwork_mode((int)mode);
}
- (void)refreshCompanionControls {
    if(!self.pad)return;
    BOOL portrait=[self showsCompanion];
    BOOL active=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
    BOOL physical=self.physicalController,presented=portrait && active;
    int mode=(int)[NSUserDefaults.standardUserDefaults integerForKey:@"DmPadVisibility"];
    BOOL hidden=portrait ? dm_companion_control_hidden(presented,physical,mode) : (!active || physical);
    // The keyboard editing phase owns landscape visibility. Portrait controls are on the
    // companion, so typing on the upper game never suppresses those controls.
    if(!portrait)hidden|=self.nativeKeyboardActive || dm_game_touch_hidden(&_gameTouchState,mode,CACurrentMediaTime());
    if(hidden!=self.pad.hidden || hidden!=!self.pad.userInteractionEnabled){
        self.pad.hidden=hidden;self.pad.userInteractionEnabled=!hidden;
    }
    dm_gamepad_presentation(portrait,hidden);
    self.visibilityButton.hidden=physical || !active;
    if(self.companion)dm_companion_ui_state(hidden,physical,presented);
}
- (void)nativeUIContext:(unsigned)context {
    BOOL keyboard=dm_keyboard_controls_context(&_keyboardControls,context);
    BOOL dialogChanged=((self.nativeContext^context)&8)!=0;
    BOOL drawingOpened=(context&2) && !(self.nativeContext&2),drawingClosed=!(context&2) && (self.nativeContext&2);
    self.nativeContext=context;
    if(self.nativeKeyboardActive==keyboard && !drawingOpened && !drawingClosed && !dialogChanged)return;
    self.nativeKeyboardActive=keyboard;_gameTouchState=(dm_game_touch_controls){0};++_gameTouchEpoch;
    if(drawingOpened && !keyboard){_gameTouchState.resume_at=CACurrentMediaTime()+1.1;[self queueGameTouchRestoration];}
    if(drawingClosed && !keyboard)[self.game cancelNativeTouches];
    [self refreshCompanionControls];
}
- (void)queueGameTouchRestoration {
    uint64_t epoch=_gameTouchEpoch;__weak DmRootVC *weak=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.12*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        DmRootVC *strong=weak;if(strong && strong->_gameTouchEpoch==epoch)[strong refreshCompanionControls];
    });
}
- (void)gameTouchActivity:(BOOL)active {
    unsigned context=dm_view_touch_context();
    dm_keyboard_controls_touch(&_keyboardControls,context,active);
    [self nativeUIContext:context];
    if(self.nativeKeyboardActive || (self.nativeContext&8) || _keyboardControls.submitted)return;
    double now=CACurrentMediaTime();
    if(!dm_game_touch_activity(&_gameTouchState,active,now))return;
    ++_gameTouchEpoch;[self refreshCompanionControls];
    if(!active)[self queueGameTouchRestoration];
}
- (void)companionActivity:(unsigned)source busy:(BOOL)busy {
    // Keep the bridge compatible with companion gesture/menu notifications.
    // Reserved side frames retain their controls throughout those operations.
    (void)source;(void)busy;
}
- (void)presentationChanged:(NSNotification *)note {
    if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{[self presentationChanged:note];});return;}
    if([note.name isEqual:UIApplicationWillResignActiveNotification]){[DMCompanion.shared action:@"bag_cancel" argument:0];[DMCompanion.shared setVisible:NO];}
    [self.view setNeedsLayout];
    if([note.name isEqual:UIApplicationDidBecomeActiveNotification]){[self updateOrientation:YES];}
}
- (UIDeviceOrientation)physicalOrientation { return UIDevice.currentDevice.orientation; }
- (UIInterfaceOrientation)sceneOrientation { return self.view.window.windowScene.effectiveGeometry.interfaceOrientation; }
- (UIEdgeInsets)canvasInsets {
    CGRect bounds=self.canvas.bounds;
    CGRect safe=[self.canvas convertRect:UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets) fromView:self.view];
    return UIEdgeInsetsMake(fmax(0,CGRectGetMinY(safe)-CGRectGetMinY(bounds)),fmax(0,CGRectGetMinX(safe)-CGRectGetMinX(bounds)),fmax(0,CGRectGetMaxY(bounds)-CGRectGetMaxY(safe)),fmax(0,CGRectGetMaxX(bounds)-CGRectGetMaxX(safe)));
}
- (void)applyCanvasOrientation {
    // Flexible Duo scenes already orient their view hierarchy. Reapplying a
    // sensor/interface-enum turn swaps a correctly resized portrait/landscape
    // viewport a second time. Keep the owned canvas in native view coordinates.
    CGRect native=self.view.bounds;CGSize size=native.size;
    BOOL changed=self.canvasQuarterTurns!=0 || !CGSizeEqualToSize(self.canvas.bounds.size,size);
    if(changed){[self.game cancelNativeTouches];dm_gamepad_reset();}
    self.canvasQuarterTurns=0;self.canvasInverted=NO;
    self.canvas.transform=CGAffineTransformIdentity;
    self.canvas.bounds=(CGRect){CGPointZero,size};self.canvas.center=CGPointMake(CGRectGetMidX(native),CGRectGetMidY(native));
    if(changed){
        [NSNotificationCenter.defaultCenter postNotificationName:@"DmCanvasOrientationChanged" object:self];
        LOG("display: native layout %s; root %.0fx%.0f, canvas %.0fx%.0f, scene direction %ld",size.height>size.width?"portrait":"landscape",size.width,size.height,size.width,size.height,(long)[self sceneOrientation]);
    }
}
- (void)deviceOrientationChanged:(NSNotification *)note { (void)note;[self updateOrientation:NO];[self.view setNeedsLayout]; }
- (void)updateOrientation:(BOOL)force {
    (void)force;
    BOOL fullPhone=[self isOuterDisplay] || self.isStandardPhone;
    BOOL changed=atomic_exchange(&g_phone_canvas,fullPhone)!=fullPhone;
    atomic_store(&g_display_policy_known,1);
    UIInterfaceOrientationMask policy=front_ios_orientation_mask();
    changed|=self.lastOrientationPolicy!=policy;self.lastOrientationPolicy=policy;
    if(changed){[self setNeedsUpdateOfSupportedInterfaceOrientations];[self.presentedViewController setNeedsUpdateOfSupportedInterfaceOrientations];}
    // Supported orientations already constrain the compact display. A separate
    // geometry request can retain that preference across a cold outer launch
    // and expansion, even after requesting All or an empty preference. Let the
    // native scene select its direction from the current supported policy.
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateOrientation:NO];
    [self applyCanvasOrientation];CGRect b=self.canvas.bounds;
    if (!self.game) return;
    CGRect previousGame=self.game.frame,previousPad=self.pad.frame;
    CGFloat w = b.size.width, h = b.size.height;   // Fit 16:9 into the whole screen
    if (w / h > 16.0 / 9.0) w = h * 16.0 / 9.0; else h = w * 9.0 / 16.0;
    self.game.frame = CGRectMake(floor((b.size.width - w) / 2), floor((b.size.height - h) / 2), w, h);
    BOOL adaptive=self.usesAdaptiveCanvas;
    if(adaptive)self.game.frame=b;
    NSString *framingKey=self.imageModePreferenceKey;
    NSNumber *saved=[NSUserDefaults.standardUserDefaults objectForKey:framingKey];
    int framing=adaptive && !(saved && saved.intValue==DM_PRESENT_FIT)?DM_PRESENT_EXPAND:DM_PRESENT_FIT;
    atomic_store(&g_present_mode,framing);
    self.pad.frame=b;
    if(self.companion){
        BOOL portrait=[self showsCompanion], physical=self.physicalController;
        CGRect safe=UIEdgeInsetsInsetRect(b,[self canvasInsets]);
        dm_companion_layout layout=adaptive?dm_companion_fold_layout(b,safe,portrait,!physical):dm_companion_screen_layout(safe,portrait,!physical);
        self.game.frame=layout.game;self.pad.frame=layout.controls;self.companion.view.frame=layout.panel;
        dm_gamepad_companion_frame(self.canvas,portrait && !physical?layout.panel:CGRectZero);
        if(!portrait && !self.companion.view.hidden)[DMCompanion.shared action:@"bag_cancel" argument:0];
        self.companion.view.hidden=!portrait;
        if(!portrait)self.pad.frame=b;
        [self refreshCompanionControls];
        [DMCompanion.shared setVisible:portrait && UIApplication.sharedApplication.applicationState==UIApplicationStateActive];
        self.fps.hidden=!portrait;
        self.view.backgroundColor=portrait ? [UIColor colorWithRed:1 green:0.945 blue:0.765 alpha:1] : UIColor.blackColor;
    }
    if(!CGRectEqualToRect(previousGame,self.game.frame)||!CGRectEqualToRect(previousPad,self.pad.frame)){[self.game cancelNativeTouches];dm_gamepad_reset();}
    dm_view_device(adaptive);
    dm_view_target(framing==DM_PRESENT_EXPAND && self.game.bounds.size.height>0?self.game.bounds.size.width/self.game.bounds.size.height:0);
    self.visibilityButton.frame=dm_gamepad_settings_rect(self.canvas);
    ((DmControlsMenuButton *)self.visibilityButton).touchLimit=CGRectIntersection(b,[self.pad convertRect:self.pad.bounds toView:self.canvas]);
    [self.visibilityButton setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:dm_gamepad_settings_icon_size() weight:UIImageSymbolWeightRegular] forImageInState:UIControlStateNormal];
    self.visibilityButton.layer.cornerRadius=self.visibilityButton.bounds.size.height/2;
    BOOL portrait=[self showsCompanion];
    self.visibilityButton.backgroundColor=portrait ? [UIColor colorWithRed:1 green:.98 blue:.88 alpha:1]:[UIColor colorWithWhite:0 alpha:.16];
    self.visibilityButton.tintColor=portrait ? [UIColor colorWithRed:.28 green:.34 blue:.26 alpha:1]:[UIColor colorWithWhite:1 alpha:.7];
    [self.canvas bringSubviewToFront:self.visibilityButton];front_loading_top();
    [self nativeUIContext:dm_view_touch_context()];[self refreshCompanionControls];
    if (self.fps) {   // the top row's free stretch: right of DmGamepad.m's L3 key (102 + 17 of its units from the safe edge), level with − / + (22 units down); u is its unit
        CGRect s = UIEdgeInsetsInsetRect(b, self.view.safeAreaInsets); CGFloat u = MIN(b.size.height / 430.0, 1.3);
        self.fps.frame = CGRectMake(floor(CGRectGetMinX(s) + 130 * u), floor(CGRectGetMinY(s) + 22 * u - 11), 64, 22);
        if(self.companion)self.fps.frame=CGRectMake(CGRectGetMaxX(self.game.frame)-70,CGRectGetMinY(self.game.frame)+6,64,22);
    }
    self.lanWaitOverlay.frame = self.canvas.bounds;
    if (self.lanWaitOverlay && !self.lanWaitOverlay.hidden) [self.canvas bringSubviewToFront:self.lanWaitOverlay];
}
- (void)viewDidAppear:(BOOL)a {
    [super viewDidAppear:a];
    if (self.launched || !front_ios_boot_ok()) return;
    self.launched = YES; g_root = self;
    if (!dm_show_launcher((__bridge void *)self, launcher_done)) [self startGame];   // the settings screen first (Launcher.swift), when the app has one
}
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [self.game cancelNativeTouches];dm_gamepad_reset();
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }   // Edge gestures need two swipes, to avoid accidental exits
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return front_ios_orientation_mask(); }
#include "LocalMultiplayerUI.inc"
@end
UIViewController *front_ios_root(void) { return [DmRootVC new]; }

// Thermal state and screen brightness for the power and present rows every 300 frames (hle_nvn.c; its weak defaults return -1 on the Mac). thermalState: 0 nominal, 1 fair, 2 serious, 3 critical.
// Brightness is read on the main thread at start and on each change; every change of the thermal state and of Low Power Mode (which lowers the CPU clock) is logged with the time since launch
static _Atomic double g_brightness = -1;
int dm_thermal_now(void) { return (int)NSProcessInfo.processInfo.thermalState; }
int dm_low_power_now(void) { return NSProcessInfo.processInfo.lowPowerModeEnabled; }   // the frame step does not probe in it (hle_nvn.c fstep_cpu_slowed)
double dm_brightness_now(void) { return g_brightness; }
static void front_ios_power_watch(void) {
    g_brightness = UIScreen.mainScreen.brightness;
    [NSNotificationCenter.defaultCenter addObserverForName:UIScreenBrightnessDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { (void)n; g_brightness = UIScreen.mainScreen.brightness; }];
    [NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        (void)n; LOG("front end: thermal state → %d (%.0f s after launch)", dm_thermal_now(), (now_ns() - g_t0_ns) / 1e9); }];
    [NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        (void)n; LOG("front end: Low Power Mode → %s (%.0f s after launch)", dm_low_power_now() ? "on" : "off", (now_ns() - g_t0_ns) / 1e9); }];
    LOG("front end: thermal state %d, brightness %.2f, Low Power Mode %s", dm_thermal_now(), g_brightness, dm_low_power_now() ? "on" : "off");
}

// Frame-rate counter: the frames put on screen in the last second (nvn_mtl.m counts them for NVN and for the Vulkan layer alike; frames the display link merged away are not counted).
// On when the IPA was built with it (the NSP script's SHOW_FPS / --show-fps → DMShowFPS in Info.plist); DM_SHOW_FPS=0 / 1 in Documents/env.txt overrides that without a rebuild. NULL when off
uint64_t mtl_present_count(void);
static UILabel *front_ios_fps_label(void) {
    const char *e = getenv("DM_SHOW_FPS");
    if (!(e ? atoi(e) != 0 : [[NSBundle.mainBundle objectForInfoDictionaryKey:@"DMShowFPS"] boolValue])) return nil;
    UILabel *l = [UILabel new];
    l.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold]; l.textColor = UIColor.whiteColor; l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45]; l.layer.cornerRadius = 6; l.layer.masksToBounds = YES; l.userInteractionEnabled = NO;
    l.text = @"-- fps";
    __block uint64_t n0 = mtl_present_count(); __block double t0 = CACurrentMediaTime();
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
        (void)t; uint64_t n = mtl_present_count(); double now = CACurrentMediaTime();
        if (now - t0 < 1.5) l.text = [NSString stringWithFormat:@"%.0f fps", (n - n0) / (now - t0)];   // a longer span is the time in the background: no reading
        n0 = n; t0 = now;
    }];
    LOG("front end: frame-rate counter on");
    return l;
}

// One continuous startup surface spans launcher dismissal, prepare phases and
// the first real drawable. The existing artwork tick observes an atomic flag
// published by the renderer's actual presentedTime callback.
static UIView *g_prog;
static UILabel *g_prog_count,*g_prog_title;
static UIProgressView *g_prog_bar;
static UIActivityIndicatorView *g_prog_activity;
static BOOL g_starting,g_progress_active;
static NSString *front_loading_text(NSString *key) {
    NSString *lang=getenv("DM_LANG")?@(getenv("DM_LANG")):@"zh-Hans";
    NSString *path=[NSBundle.mainBundle pathForResource:lang ofType:@"lproj"];
    NSBundle *strings=path?[NSBundle bundleWithPath:path]:NSBundle.mainBundle;
    return [strings localizedStringForKey:key value:key table:@"Companion"];
}
static void front_loading_view(void) {
    if(g_prog)return;
    UIView *root=g_root.canvas;if(!root)return;
    g_prog=[[UIView alloc]initWithFrame:root.bounds];g_prog.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    g_prog.backgroundColor=UIColor.blackColor;g_prog.opaque=YES;
    UIView *box=[[UIView alloc]initWithFrame:CGRectMake(floor((root.bounds.size.width-320)/2),floor((root.bounds.size.height-100)/2),320,100)];
    box.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
    g_prog_title=[[UILabel alloc]initWithFrame:CGRectMake(0,0,320,30)];g_prog_title.textAlignment=NSTextAlignmentCenter;g_prog_title.textColor=UIColor.whiteColor;g_prog_title.font=[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    g_prog_bar=[[UIProgressView alloc]initWithProgressViewStyle:UIProgressViewStyleDefault];g_prog_bar.frame=CGRectMake(20,47,280,4);g_prog_bar.hidden=YES;
    g_prog_count=[[UILabel alloc]initWithFrame:CGRectMake(0,70,320,22)];g_prog_count.textAlignment=NSTextAlignmentCenter;g_prog_count.textColor=[UIColor colorWithWhite:.72 alpha:1];g_prog_count.font=[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    g_prog_activity=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];g_prog_activity.color=UIColor.whiteColor;g_prog_activity.frame=CGRectMake(145,42,30,30);[g_prog_activity startAnimating];
    [box addSubview:g_prog_title];[box addSubview:g_prog_bar];[box addSubview:g_prog_count];[box addSubview:g_prog_activity];[g_prog addSubview:box];[root addSubview:g_prog];
}
static void front_loading_top(void) {if(g_prog.superview==g_root.canvas)[g_root.canvas bringSubviewToFront:g_prog];}
static void front_startup_begin(void) {
    if(dm_performance_has_presented())return;
    g_starting=YES;front_loading_view();g_prog_title.text=front_loading_text(@"Starting game…");front_loading_top();
}
void dm_launch_transition(void) { front_startup_begin(); }
static void front_startup_tick(void) {
    if(!g_starting || g_progress_active || !dm_performance_has_presented() || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    g_starting=NO;UIView *finished=g_prog;g_prog=nil;
    [finished removeFromSuperview];
}
void front_progress(const char *title,long done,long total) {
    if(!g_layer)return;NSString *text=title?@(title):nil;
    dispatch_async(dispatch_get_main_queue(),^{
        g_progress_active=text!=nil;
        if(!text){
            if(g_starting){g_prog_title.text=front_loading_text(@"Starting game…");g_prog_bar.hidden=YES;g_prog_count.text=nil;g_prog_activity.hidden=NO;front_startup_tick();}
            else{[g_prog removeFromSuperview];g_prog=nil;}
            return;
        }
        front_loading_view();g_prog_title.text=front_loading_text(text);g_prog_bar.hidden=NO;g_prog_activity.hidden=YES;
        g_prog_bar.progress=total>0?(float)done/(float)total:0;
        g_prog_count.text=[NSString stringWithFormat:@"%@ / %@",[NSNumberFormatter localizedStringFromNumber:@(done) numberStyle:NSNumberFormatterDecimalStyle],[NSNumberFormatter localizedStringFromNumber:@(total) numberStyle:NSNumberFormatterDecimalStyle]];front_loading_top();
    });
}
void *front_metal_layer(void) { return (__bridge void *)g_layer; }
void front_run(void (*guest)(void)) { dm_companion_host_ready();guest(); }   // Already on main.m's big-stack thread

// Software keyboard: show a UIAlertController on the main thread; the calling thread waits for the result.
int front_text_input(const char *title, const char *sub, const char *guide, const char *initial, int max_chars, char *out, int out_cap) {
    if (!g_layer) return -1;
    __block int r = 0; __block NSString *text = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSString *t = title && *title ? @(title) : @"", *m = [NSString stringWithFormat:@"%s%s%s", sub ? sub : "", sub && *sub && guide && *guide ? "\n" : "", guide ? guide : ""];
    NSString *init = initial ? @(initial) : @"", *ph = guide ? @(guide) : @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:t message:m preferredStyle:UIAlertControllerStyleAlert];
        [ac addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = init; f.placeholder = ph; }];
        [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { (void)x; r = 1; text = ac.textFields.firstObject.text; dispatch_semaphore_signal(done); }]];
        [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { (void)x; dispatch_semaphore_signal(done); }]];
        UIViewController *vc = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) if ([s isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow) vc = w.rootViewController;
        if (!vc) { dispatch_semaphore_signal(done); return; }
        [vc presentViewController:ac animated:YES completion:nil];
    });
    // The guest clock keeps running meanwhile, as on the Switch (hle_swkbd.c): a freeze here as well stopped Octopath Traveler 0's frame loop for as long as the box was up and made its sound stutter
    // (4,977 ms and 2,577 ms frames, 5,181 wakeups a second). The inline keyboard freezes around its own call (hle_swkbd.c)
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (!r) return 0;
    snprintf(out, out_cap, "%s", text.UTF8String ? text.UTF8String : "");
    return 1;
}

// Save write failed (most likely the phone's storage is full): show a notice on the main thread without blocking the game. hle_fs.c calls this when a save transaction is refused or a mount has to fall back to read-only;
// the iOS front end used not to implement it, so there was only a log line and the player never learned that progress was not being saved
void front_save_failed(int err) {
    LOG("front end: save data write failed errno=%d, telling the player", err);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) if ([s isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow) vc = w.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        if (!vc) { LOG("[RED] front end: no window for the save-failure alert errno=%d", err); return; }
        NSString *m = err == ENOSPC ? @"Storage is full, so progress was not saved. Free up space and save again."
                                    : [NSString stringWithFormat:@"Saving failed (errno %d); progress was not saved.", err];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Save failed" message:m preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

// Audio session: the frames RemoteIO asks for in each callback follow the I/O buffer duration, about 21 ms by default on iOS (1024 frames at 48 kHz). The game keeps only 4 blocks × 5 ms = 20 ms in flight,
// so every callback came up 1.3 ms short and was zero-filled, about 47 gaps per second (crackling; reproducible on the Mac by forcing 1024-frame callbacks: 1999 underruns in 2000 callbacks). Ask for 5 ms and the system picks the nearest it supports;
// the category stays the default SoloAmbient (silent switch and interrupting other apps' audio behave as before). Set once at boot and again on return to the foreground (the system may reset it after an interruption)
static int g_session_off;   // the last activation failed (another app or a call still held the session): tried again when the app becomes active
void front_ios_audio_session(void) {
    AVAudioSession *s = AVAudioSession.sharedInstance; NSError *e = nil;
    if (![s setCategory:AVAudioSessionCategorySoloAmbient error:&e]) LOG("[RED] audio session category could not be set: %s", e.localizedDescription.UTF8String);
    [s setPreferredSampleRate:48000 error:nil];
    if (![s setPreferredIOBufferDuration:0.005 error:&e]) LOG("[RED] audio session I/O buffer duration could not be set: %s", e.localizedDescription.UTF8String);
    g_session_off = ![s setActive:YES error:&e];
    if (g_session_off) LOG("[RED] audio session activation failed: %s", e.localizedDescription.UTF8String);
    LOG("audio session: sample rate %.0f Hz, I/O buffer %.2f ms (asked for 5 ms)", s.sampleRate, s.IOBufferDuration * 1000);
}

// Real audio output is suspended (the silent sink paces the game) while the app is in the background or another audio session has interrupted ours (Siri, an alarm, a call).
// Without the interruption observer the AudioUnits stayed "started" while iOS no longer called them, and a game waiting for its buffers back lost its sound until restart.
// All of this runs on the main queue, like the scene callbacks
static int g_audio_bg, g_audio_intr, g_audio_lan;
static void front_ios_audio_apply(void) { dm_audio_suspend(g_audio_bg || g_audio_intr || g_audio_lan); }
static void front_ios_lan_audio(int paused) {
    if (g_audio_lan == !!paused) return;
    g_audio_lan = !!paused; front_ios_audio_apply();
}
static void front_ios_audio_watch(void) {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue], reason = [n.userInfo[AVAudioSessionInterruptionReasonKey] unsignedIntegerValue];
        if (type == AVAudioSessionInterruptionTypeBegan) { LOG("audio session: interrupted (reason %lu)", (unsigned long)reason); g_audio_intr = 1; }
        else {
            LOG("audio session: interruption ended"); g_audio_intr = 0;
            if (!g_audio_bg) front_ios_audio_session();
        }
        front_ios_audio_apply();
    }];
    [nc addObserverForName:AVAudioSessionMediaServicesWereResetNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        (void)n; LOG("audio session: the media services were reset; setting the session and the outputs up again");
        front_ios_audio_session(); dm_audio_reset();
    }];
}

// Scene lifecycle (called by SceneDelegate in main.m): 0 resign active, 1 enter background, 2 return to foreground, 3 become active. On entering background, freeze the guest clock and suspend after in-flight GPU work completes (submitting GPU work in background gets the process killed).
// The screen stays on while the game is active: only touches reset the idle timer, so with a controller (or during a cutscene) the screen dimmed and locked mid-game
void front_ios_focus_event(int ev) {
    if (!g_layer) return;
    switch (ev) {
        case 0: front_lan_task_prepare(); [g_root.game cancelNativeTouches]; [g_root companionActivity:DM_UI_TOUCH busy:NO]; [g_root refreshCompanionControls]; [DMCompanion.shared action:@"bag_cancel" argument:0]; [DMCompanion.shared setVisible:NO]; dm_gamepad_reset(); dm_focus_set(2); break;
        case 1: front_lan_task_prepare(); dm_lan_background(1); UIApplication.sharedApplication.idleTimerDisabled = NO; dm_focus_set(3); g_audio_bg = 1; front_ios_audio_apply(); guest_clock_freeze_for(1, 1); dm_gfx_suspend(1); break;
        case 2: dm_lan_background(0); front_lan_task_end(); dm_gfx_suspend(0); guest_clock_freeze_for(1, 0); front_ios_audio_session(); g_audio_bg = 0; front_ios_audio_apply(); dm_focus_set(2); [g_root updateLocalPlayWait]; break;
        case 3:   // Becoming active again also ends an interruption whose "ended" never came (not every one sends it), and retries a session that would not activate on the way back
            UIApplication.sharedApplication.idleTimerDisabled = YES;
            front_lan_task_end();
            if (g_audio_intr) { LOG("audio session: active again with no interruption-ended notice; resuming"); g_audio_intr = 0; g_session_off = 1; }
            if (g_session_off) front_ios_audio_session();
            front_ios_audio_apply(); dm_focus_set(1); [g_root.view setNeedsLayout]; break;
    }
}
