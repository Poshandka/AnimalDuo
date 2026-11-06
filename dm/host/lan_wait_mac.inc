// Native waiting UI for Mac peers; guest GPU frames can remain stopped.
static NSView *g_lan_cover;
static NSTextField *g_lan_title, *g_lan_detail;
static NSButton *g_lan_button;
static NSVisualEffectView *g_lan_card;
static BOOL g_lan_dismissed, g_lan_audio;
static dispatch_source_t g_lan_poll;
static __weak NSWindow *g_lan_window;
static void local_play_update(void);
@interface DmLocalPlayCover : NSView
@end
@implementation DmLocalPlayCover
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (void)mouseDown:(NSEvent *)event { (void)event; }
- (void)mouseUp:(NSEvent *)event { (void)event; }
- (void)waitAction:(id)sender {
    (void)sender; dm_lan_wait_info info; dm_lan_wait_snapshot(&info);
    if (info.state == DM_LAN_WAIT_ENDED) g_lan_dismissed = YES;
    else dm_lan_wait_cancel();
    local_play_update();
}
@end
static void local_play_update(void) {
    NSWindow *window = g_lan_window; if (!window) return;
    dm_lan_wait_info info; dm_lan_wait_snapshot(&info);
    int waiting = info.state >= DM_LAN_WAIT_PREPARING && info.state <= DM_LAN_WAIT_RESUMING;
    if (g_lan_audio != waiting) { g_lan_audio = waiting; dm_audio_suspend(waiting || window.miniaturized); }
    if (info.state != DM_LAN_WAIT_ENDED) g_lan_dismissed = NO;
    BOOL visible = info.state != DM_LAN_WAIT_NONE && !(info.state == DM_LAN_WAIT_ENDED && g_lan_dismissed);
    BOOL wasVisible = g_lan_cover && !g_lan_cover.hidden;
    if (!visible) {
        g_lan_cover.hidden = YES;
        if (wasVisible && window.keyWindow) input_resume();
        return;
    }
    NSView *parent = window.contentView;
    if (!g_lan_cover) {
        DmLocalPlayCover *cover = [[DmLocalPlayCover alloc] initWithFrame:parent.bounds];
        cover.wantsLayer = YES; cover.layer.backgroundColor = [NSColor colorWithWhite:0 alpha:.48].CGColor;
        cover.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        g_lan_card = [NSVisualEffectView new]; g_lan_card.material = NSVisualEffectMaterialHUDWindow;
        g_lan_card.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        g_lan_card.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        g_lan_card.wantsLayer = YES; g_lan_card.layer.cornerRadius = 18; g_lan_card.layer.masksToBounds = YES;
        [cover addSubview:g_lan_card];
        g_lan_title = [NSTextField labelWithString:@""]; g_lan_title.font = [NSFont systemFontOfSize:21 weight:NSFontWeightSemibold];
        g_lan_detail = [NSTextField wrappingLabelWithString:@""]; g_lan_detail.font = [NSFont systemFontOfSize:15];
        for (NSTextField *label in @[g_lan_title, g_lan_detail]) { label.alignment = NSTextAlignmentCenter; label.textColor = NSColor.whiteColor; [g_lan_card addSubview:label]; }
        g_lan_button = [NSButton buttonWithTitle:@"" target:cover action:@selector(waitAction:)]; [g_lan_card addSubview:g_lan_button];
        g_lan_cover = cover; [parent addSubview:cover];
    }
    if (!wasVisible) input_release();
    g_lan_cover.frame = parent.bounds; g_lan_cover.hidden = NO;
    CGFloat width = fmin(430, parent.bounds.size.width-48);
    g_lan_card.frame = NSMakeRect((parent.bounds.size.width-width)/2, (parent.bounds.size.height-210)/2, width, 210);
    g_lan_title.frame = NSMakeRect(24,142,width-48,48); g_lan_detail.frame = NSMakeRect(24,66,width-48,70); g_lan_button.frame = NSMakeRect(24,18,width-48,36);
    NSString *title = @"Local play is paused", *detail;
    if (info.state == DM_LAN_WAIT_PREPARING) { title = @"Preparing a brief pause"; detail = dm_local_play_text(@"Coordinating all players. Please wait."); }
    else if (info.state == DM_LAN_WAIT_RESUMING) { title = @"Restoring local play"; detail = dm_local_play_text(@"Checking that every player is ready."); }
    else if (info.state == DM_LAN_WAIT_ENDED) { title = @"Local-play wait ended"; detail = dm_local_play_text(@"Return to the game and visit the island again."); }
    else detail = [NSString stringWithFormat:dm_local_play_text(@"Waiting for a player to return. %d seconds remaining."),info.seconds];
    g_lan_title.stringValue = dm_local_play_text(title); g_lan_detail.stringValue = detail;
    g_lan_button.title = dm_local_play_text(waiting ? @"End local play" : @"Return to game");
}
static void local_play_watch(NSWindow *window) {
    g_lan_window = window; g_lan_poll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(g_lan_poll,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,50*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(g_lan_poll,^{
        local_play_update(); dm_lan_wait_info info; dm_lan_wait_snapshot(&info);
        uint64_t interval = info.supported || info.state != DM_LAN_WAIT_NONE ? 200*NSEC_PER_MSEC : NSEC_PER_SEC;
        dispatch_source_set_timer(g_lan_poll,dispatch_time(DISPATCH_TIME_NOW,interval),interval,20*NSEC_PER_MSEC);
    });
    dispatch_resume(g_lan_poll);
}
