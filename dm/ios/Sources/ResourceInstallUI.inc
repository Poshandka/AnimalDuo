// Installation runs after UIApplicationMain, keeping first launch responsive.
static NSString *resourceText(NSString *key){NSString *lang=getenv("DM_LANG")?@(getenv("DM_LANG")):@"zh-Hans";NSString *path=[NSBundle.mainBundle pathForResource:lang ofType:@"lproj"];NSBundle *b=path?[NSBundle bundleWithPath:path]:NSBundle.mainBundle;return [b localizedStringForKey:key value:key table:@"Resources"];}
@interface DMResourceInstallVC:UIViewController
@property DMResourceStore *store;
@property(copy) void (^ready)(void);
@property UILabel *heading,*detail,*amount;
@property UIProgressView *progress;
@property UIButton *retry;
@property BOOL busy,finished;
@property(atomic) BOOL cancelled;
- (void)beginInstallation;
@end
@implementation DMResourceInstallVC
- (void)viewDidLoad{
    [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;
    self.heading=[UILabel new];self.heading.text=resourceText(@"Installing game resources");self.heading.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];self.heading.textColor=UIColor.whiteColor;self.heading.textAlignment=NSTextAlignmentCenter;self.heading.numberOfLines=0;
    self.detail=[UILabel new];self.detail.text=resourceText(@"This is only needed once. Future app updates can be small.");self.detail.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];self.detail.textColor=[UIColor colorWithWhite:.8 alpha:1];self.detail.textAlignment=NSTextAlignmentCenter;self.detail.numberOfLines=0;
    self.amount=[UILabel new];self.amount.textColor=UIColor.whiteColor;self.amount.textAlignment=NSTextAlignmentCenter;self.amount.font=[UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    self.progress=[UIProgressView new];self.retry=[UIButton buttonWithType:UIButtonTypeSystem];[self.retry setTitle:resourceText(@"Check again") forState:UIControlStateNormal];[self.retry addTarget:self action:@selector(beginInstallation) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[self.heading,self.detail,self.progress,self.amount,self.retry]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=22;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:stack];
    NSLayoutConstraint *width=[stack.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:.85];width.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],[stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],[stack.widthAnchor constraintLessThanOrEqualToConstant:460],[stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:28],[stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-28],width]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resign:) name:UIApplicationWillResignActiveNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];[self beginInstallation];}
- (void)resign:(NSNotification *)note{(void)note;self.cancelled=YES;}
- (void)active:(NSNotification *)note{(void)note;[self beginInstallation];}
- (void)beginInstallation{
    if(self.busy || self.finished || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    NSError *error=nil;
    if([self.store ready:&error]){self.finished=YES;self.ready();return;}
    if(![self.store hasInstaller]){self.heading.text=resourceText(@"Game resources are not installed");self.detail.text=resourceText(@"Install and open the complete resource version once, then use the small update package. Keep the same app and its data.");self.progress.hidden=YES;self.amount.text=nil;self.retry.hidden=NO;return;}
    self.cancelled=NO;self.busy=YES;self.retry.hidden=YES;self.progress.hidden=NO;self.heading.text=resourceText(@"Installing game resources");self.detail.text=resourceText(@"Keep this app open. You can return later to continue.");
    UIApplication.sharedApplication.idleTimerDisabled=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool{
        NSError *failure=nil;BOOL ok=[self.store installWithProgress:^(uint64_t done,uint64_t total,NSUInteger files,NSUInteger count){(void)files;(void)count;dispatch_async(dispatch_get_main_queue(),^{self.progress.progress=total?(double)done/(double)total:0;self.amount.text=[NSString stringWithFormat:@"%@ / %@",[NSByteCountFormatter stringFromByteCount:done countStyle:NSByteCountFormatterCountStyleFile],[NSByteCountFormatter stringFromByteCount:total countStyle:NSByteCountFormatterCountStyleFile]];});} cancelled:^BOOL{return self.cancelled;} error:&failure];
        dispatch_async(dispatch_get_main_queue(),^{
            self.busy=NO;UIApplication.sharedApplication.idleTimerDisabled=NO;
            if(ok){self.finished=YES;self.ready();return;}
            self.retry.hidden=NO;
            if([failure.domain isEqual:@"nxnative.resources"] && failure.code==2){self.detail.text=resourceText(@"Installation paused. Return to this app to continue.");if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[self beginInstallation];}
            else{self.heading.text=resourceText(@"Resource installation needs attention");self.detail.text=failure.localizedDescription?:resourceText(@"Keep the complete version installed and try again.");fprintf(stderr,"[RED] resources: installation failed (%s, %ld)\n",failure.domain.UTF8String,(long)failure.code);}
        });
    }});
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (BOOL)prefersStatusBarHidden{return YES;}
@end
