// Run the actual serial-queue adapter with fake engines: no controller, actuator or app is opened.
#import <Foundation/Foundation.h>
static void capture_after(dispatch_time_t when, dispatch_queue_t target, dispatch_block_t block);
#define dispatch_after capture_after
#import "../haptics_apple.m"
#undef dispatch_after
#include <assert.h>

// Advance scheduled callbacks explicitly: a fixed wall-clock sleep can finish
// before libdispatch delivers an eligible timer on a busy or suspended runner.
static NSMutableArray<dispatch_block_t> *idleTimers;
static void capture_after(dispatch_time_t when, dispatch_queue_t target, dispatch_block_t block) {
    (void)when; assert(target == queue && dispatch_get_specific(&queue));
    if (!idleTimers) idleTimers = [NSMutableArray new];
    [idleTimers addObject:[block copy]];
}
static void fire_idle_timers(void) {
    dispatch_sync(queue, ^{
        assert(idleTimers.count);
        NSArray<dispatch_block_t> *pending = [idleTimers copy];
        [idleTimers removeAllObjects];
        for (dispatch_block_t block in pending) block();
    });
}

@interface TestPlayer : NSObject
@property BOOL loopEnabled, isMuted;
@property BOOL mutedAtStart;
@property float intensityAtStart;
@property int starts, stops;
@property NSMutableArray<NSNumber *> *levels;
@property BOOL failStart, failSend;
@end
@implementation TestPlayer
- (instancetype)init { if ((self = [super init])) _levels = [NSMutableArray new]; return self; }
- (BOOL)startAtTime:(NSTimeInterval)t error:(NSError **)e {
    (void)t; (void)e; self.starts++;
    self.mutedAtStart = self.isMuted;
    self.intensityAtStart = self.levels.count ? self.levels.lastObject.floatValue : 1;
    return !self.failStart;
}
- (BOOL)stopAtTime:(NSTimeInterval)t error:(NSError **)e { (void)t; (void)e; self.stops++; return YES; }
- (BOOL)sendParameters:(NSArray<CHHapticDynamicParameter *> *)p atTime:(NSTimeInterval)t error:(NSError **)e {
    (void)t; (void)e;
    if (self.failSend) return NO;
    for (CHHapticDynamicParameter *v in p) if ([v.parameterID isEqual:CHHapticDynamicParameterIDHapticIntensityControl]) [self.levels addObject:@(v.value)];
    return YES;
}
@end
@interface TestEngine : NSObject
@property BOOL playsHapticsOnly, autoShutdownEnabled;
@property(copy) void (^resetHandler)(void);
@property(copy) void (^stoppedHandler)(CHHapticEngineStoppedReason);
@property TestPlayer *testPlayer;
@property int starts, stops;
@property int standardPlayers, advancedPlayers;
@property NSTimeInterval patternDuration;
@property BOOL rejectAdvanced;
@property BOOL fail;
@property BOOL failPattern, failPlayer, failSend, handlersAtStart, resetDuringStart;
@property(copy) void (^startingReset)(void);
@end
@implementation TestEngine
- (BOOL)startAndReturnError:(NSError **)e {
    self.starts++; self.handlersAtStart = self.resetHandler && self.stoppedHandler;
    self.startingReset = self.resetHandler;
    if (self.resetDuringStart && self.resetHandler) self.resetHandler();
    if (self.fail && e) *e = [NSError errorWithDomain:CoreHapticsErrorDomain code:CHHapticErrorCodeServerInitFailed userInfo:nil];
    return !self.fail;
}
- (void)stopWithCompletionHandler:(CHHapticCompletionHandler)handler { self.stops++; if (handler) handler(nil); }
- (id<CHHapticPatternPlayer>)createPlayerWithPattern:(CHHapticPattern *)p error:(NSError **)e {
    (void)e; self.standardPlayers++; self.patternDuration = p.duration;
    if (self.failPattern) return nil;
    self.testPlayer = [TestPlayer new]; self.testPlayer.failStart = self.failPlayer; self.testPlayer.failSend = self.failSend;
    return (id)self.testPlayer;
}
- (id<CHHapticAdvancedPatternPlayer>)createAdvancedPlayerWithPattern:(CHHapticPattern *)p error:(NSError **)e {
    self.advancedPlayers++; self.patternDuration = p.duration;
    if (self.rejectAdvanced) {
        if (e) *e = [NSError errorWithDomain:NSCocoaErrorDomain code:4097 userInfo:nil];
        return nil;
    }
    if (self.failPattern) return nil;
    self.testPlayer = [TestPlayer new]; self.testPlayer.failStart = self.failPlayer; self.testPlayer.failSend = self.failSend;
    return (id)self.testPlayer;
}
@end
@interface TestHaptics : NSObject
@property NSSet *supportedLocalities;
@property NSMutableArray<TestEngine *> *engines;
@property NSMutableArray<GCHapticsLocality> *requestedLocalities;
@property int attempts, failureStage;
@end
@implementation TestHaptics
- (instancetype)init {
    if ((self = [super init])) {
        _supportedLocalities = [NSSet setWithObject:GCHapticsLocalityDefault];
        _engines = [NSMutableArray new]; _requestedLocalities = [NSMutableArray new];
    }
    return self;
}
- (CHHapticEngine *)createEngineWithLocality:(GCHapticsLocality)locality {
    assert([self.supportedLocalities containsObject:locality]);
    self.attempts++;
    [self.requestedLocalities addObject:locality];
    if (self.attempts == 1 && self.failureStage == 1) return nil;
    TestEngine *e = [TestEngine new]; e.rejectAdvanced = YES; [self.engines addObject:e];
    if (self.attempts == 1) {
        e.fail = self.failureStage == 2; e.failPattern = self.failureStage == 3;
        e.failPlayer = self.failureStage == 4; e.failSend = self.failureStage == 5;
        e.resetDuringStart = self.failureStage == 2;
    }
    return (id)e;
}
@end
@interface TestController : NSObject
@property TestHaptics *haptics;
@property NSString *vendorName;
@end
@implementation TestController
@end
static void drain(void) { dispatch_sync(queue, ^{}); dispatch_sync(queue, ^{}); }
static void expire_retries(void) {
    dispatch_sync(queue, ^{ for (DmRumbleChannel *c in channels[0]) c.retryAfter = 0; });
}
static void send_pair(float left, float right) {
    dm_vibration_update u[] = {{0, 0, {left, 160, 0, 320}}, {0, 1, {right, 160, 0, 320}}};
    dm_haptics_send(u, 2); drain();
}
static int made;   // engines the test factories made
int main(void) { @autoreleasepool {
    queue = dispatch_queue_create("test.rumble", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(queue, &queue, &queue, NULL);
    dm_haptics_init(apply, 1); drain();
    TestEngine *left = [TestEngine new], *right = [TestEngine new];
    dispatch_sync(queue, ^{
        channels[0] = [NSMutableArray new];
        add_engine(0, @"test left", ^CHHapticEngine *(NSError **e) { (void)e; made++; return (id)left; });
        add_engine(0, @"test right", ^CHHapticEngine *(NSError **e) { (void)e; made++; return (id)right; });
        dm_haptics_route(0, 1);
    }); drain();
    send_pair(0.2, 0.7);
    // Physical A/B on iPadOS: muted startup stays silent after unmuting, while
    // parameters sent before unmuted startup vibrate. Also avoid a full-strength
    // spike before the first low-intensity update, for phone and controller alike.
    assert(!left.testPlayer.mutedAtStart && !right.testPlayer.mutedAtStart);
    assert(left.testPlayer.intensityAtStart == 0.2f && right.testPlayer.intensityAtStart == 0.7f);
    assert(left.testPlayer.levels.lastObject.floatValue == 0.2f && right.testPlayer.levels.lastObject.floatValue == 0.7f);
    assert(left.advancedPlayers == 1 && left.standardPlayers == 0 && left.patternDuration == 30 && left.testPlayer.loopEnabled);
    send_pair(0, 0);
    assert(left.testPlayer.levels.lastObject.floatValue == 0 && right.testPlayer.levels.lastObject.floatValue == 0);
    assert(left.testPlayer.levels.count == 2);   // short pulse ends immediately, without a minimum duration
    send_pair(0.4, 0.5);
    fire_idle_timers(); drain();
    assert(left.testPlayer.levels.lastObject.floatValue == 0.4f && left.testPlayer.stops == 0);   // old idle timer cannot stop a new effect
    assert(left.starts == 1);   // reused player; no per-frame engine restart
    dm_haptic_state stale = {0, dm_haptics_epoch(0), {{1, 160, 0, 320}, {1, 160, 0, 320}}};
    suspend(DM_HAPTICS_INACTIVE, YES); suspend(DM_HAPTICS_INACTIVE, NO); drain();
    int starts = left.starts; apply(stale); drain(); assert(left.starts == starts);
    send_pair(0.3, 0.6); assert(left.starts == starts + 1);
    void (^oldReset)(void) = left.resetHandler;
    suspend(DM_HAPTICS_INACTIVE, YES); suspend(DM_HAPTICS_INACTIVE, NO); drain();
    send_pair(0.5, 0.5); oldReset(); drain();
    assert(dm_haptics_actual(0, 0).amplitude_low == 0.5f);   // delayed callback from a stopped engine is stale
    left.resetHandler(); drain(); drain();
    assert(dm_haptics_actual(0, 0).amplitude_low == 0 && right.testPlayer.levels.lastObject.floatValue == 0);
    left.fail = YES; send_pair(0.8, 0.8); drain();
    assert(dm_haptics_actual(0, 0).amplitude_low == 0);   // failed output is cleared, so a fresh identical send may retry
    left.fail = NO; expire_retries(); send_pair(0.8, 0.8);
    assert(left.testPlayer.levels.lastObject.floatValue == 0.8f);
    send_pair(0, 0); fire_idle_timers(); drain();
    assert(left.testPlayer.stops == 1);   // idle hardware eventually released
    int engines = made; starts = left.starts; send_pair(0.7, 0.7);
    assert(made == engines && left.starts == starts + 1 && left.testPlayer.levels.lastObject.floatValue == 0.7f);   // the released engine is restarted, not made again
    // A permanently broken helper/engine is replaced, rather than retried for the rest of the session.
    // Exercise the real controller route (including a nil engine factory result), without hardware.
    for (int stage = 1; stage <= 5; stage++) {
        TestController *controller = [TestController new]; controller.vendorName = @"test controller";
        TestHaptics *h = [TestHaptics new]; h.failureStage = stage; controller.haptics = h;
        dm_haptics_apple_controller(0, (id)controller); drain();
        assert(dm_haptics_available() & 1);
        send_pair(0.6, 0); drain();
        assert(h.attempts == 1 && dm_haptics_actual(0, 0).amplitude_low == 0);
        if (stage == 5) assert(h.engines[0].testPlayer.starts == 0);   // failed initial controls must not start an uncontrolled effect
        assert(stage == 1 || h.engines[0].handlersAtStart);   // callbacks cover startup itself
        void (^lateReset)(void) = h.engines.firstObject.startingReset;
        for (int i = 0; i < 20; i++) send_pair(0.6, 0);
        assert(h.attempts == 1);   // an ongoing effect must not hammer a failing XPC service
        expire_retries(); send_pair(0.6, 0); drain();
        assert(h.attempts == 2);
        TestEngine *recovered = h.engines.lastObject;
        assert(recovered.testPlayer.levels.lastObject.floatValue == 0.6f);
        assert(dm_haptics_actual(0, 0).amplitude_low == 0.6f);
        if (lateReset) { lateReset(); drain(); }
        assert(recovered.testPlayer.levels.lastObject.floatValue == 0.6f);   // old callbacks cannot silence the replacement
        send_pair(0, 0); drain();
        assert(recovered.testPlayer.levels.lastObject.floatValue == 0);
    }
    // The real controller helper may reject advanced players. Both handle motors must
    // use standard infinite players, retain unequal levels and stop without a new player.
    TestController *standard = [TestController new]; standard.haptics = [TestHaptics new];
    standard.haptics.supportedLocalities = [NSSet setWithObjects:GCHapticsLocalityDefault, GCHapticsLocalityLeftHandle, GCHapticsLocalityRightHandle, nil];
    dm_haptics_apple_controller(0, (id)standard); drain(); send_pair(0.25, 0.8);
    assert(standard.haptics.engines.count == 2);
    for (TestEngine *e in standard.haptics.engines) {
        assert(e.standardPlayers == 1 && e.advancedPlayers == 0);
        assert(e.patternDuration == GCHapticDurationInfinite && !e.testPlayer.loopEnabled);
        assert(!e.testPlayer.mutedAtStart && e.testPlayer.levels.count == 1);
    }
    assert(standard.haptics.engines[0].testPlayer.levels.lastObject.floatValue == 0.25f);
    assert(standard.haptics.engines[1].testPlayer.levels.lastObject.floatValue == 0.8f);
    assert(standard.haptics.engines[0].testPlayer.intensityAtStart == 0.25f);
    assert(standard.haptics.engines[1].testPlayer.intensityAtStart == 0.8f);
    send_pair(0.4, 0.6); send_pair(0, 0);
    for (TestEngine *e in standard.haptics.engines) {
        assert(e.standardPlayers == 1 && e.starts == 1 && e.testPlayer.levels.lastObject.floatValue == 0);
    }
    TestController *split = [TestController new]; split.haptics = [TestHaptics new];
    split.haptics.supportedLocalities = [NSSet setWithObjects:GCHapticsLocalityDefault, GCHapticsLocalityLeftHandle, GCHapticsLocalityRightHandle, nil];
    split.haptics.failureStage = 2;
    dm_haptics_apple_controller(0, (id)split); drain();
    send_pair(0.3, 0.4); drain();
    assert(split.haptics.attempts == 1);   // the old right-hand route must not replay the failed batch
    assert(channels[0].count == 1);
    expire_retries(); send_pair(0.3, 0.4); drain();
    assert(split.haptics.attempts == 2 && [split.haptics.requestedLocalities.lastObject isEqual:GCHapticsLocalityDefault]);
    assert(split.haptics.engines.lastObject.standardPlayers == 1 && split.haptics.engines.lastObject.advancedPlayers == 0);
    assert(fabsf(split.haptics.engines.lastObject.testPlayer.levels.lastObject.floatValue - 0.5f) < 1e-6f);
    TestController *split2 = [TestController new]; split2.haptics = [TestHaptics new];
    split2.haptics.supportedLocalities = split.haptics.supportedLocalities;
    split2.haptics.failureStage = 3;
    dm_haptics_apple_controller(0, (id)split2); drain();
    send_pair(0.3, 0.4); drain();
    assert(split2.haptics.attempts == 1 && channels[0].count == 2);   // a player failure keeps the handle route
    expire_retries(); send_pair(0.3, 0.4); drain();
    NSArray *asked = split2.haptics.requestedLocalities;
    assert(split2.haptics.attempts == 3 && [asked[1] isEqual:GCHapticsLocalityLeftHandle] && [asked[2] isEqual:GCHapticsLocalityRightHandle]);
    assert(fabsf(split2.haptics.engines[1].testPlayer.levels.lastObject.floatValue - 0.3f) < 1e-6f);
    assert(fabsf(split2.haptics.engines[2].testPlayer.levels.lastObject.floatValue - 0.4f) < 1e-6f);
    dm_haptics_apple_controller(0, nil); drain();   // disconnect discards the controller factory and its old callbacks
    assert(!(dm_haptics_available() & 1));
    TestController *unsupported = [TestController new]; unsupported.haptics = [TestHaptics new];
    unsupported.haptics.supportedLocalities = [NSSet set];
    dm_haptics_apple_controller(0, (id)unsupported); drain();
    assert(!(dm_haptics_available() & 1) && unsupported.haptics.attempts == 0);
    dm_haptics_apple_shutdown();
    puts("Apple haptics: standard controller players, infinite duration, channels, pulses, idle release, startup handlers, engine replacement, backoff and stale callbacks passed");
} }
