// Methods of DmRootVC. A native overlay remains responsive while guest time and
// game data sockets are stopped. It never submits guest GPU work in background.
- (void)scheduleLocalPlayPoll:(NSTimeInterval)seconds {
    if (self.lanWaitTimer && fabs(self.lanWaitTimer.timeInterval-seconds) < .01) return;
    [self.lanWaitTimer invalidate]; __weak DmRootVC *weak = self;
    self.lanWaitTimer = [NSTimer scheduledTimerWithTimeInterval:seconds repeats:YES block:^(NSTimer *timer){
        DmRootVC *root = weak; if (root) [root updateLocalPlayWait]; else [timer invalidate];
    }];
}
- (void)makeLocalPlayWaitOverlay {
    UIView *overlay = [[UIView alloc] initWithFrame:self.canvas.bounds];
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:.48];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.accessibilityIdentifier = @"local-play.wait.overlay"; overlay.accessibilityViewIsModal = YES;
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    card.translatesAutoresizingMaskIntoConstraints = NO; card.layer.cornerRadius = 22; card.clipsToBounds = YES;
    [overlay addSubview:card];
    UILabel *title = [UILabel new], *detail = [UILabel new];
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    detail.font = [UIFont systemFontOfSize:16];
    for (UILabel *label in @[title, detail]) { label.textColor = UIColor.whiteColor; label.textAlignment = NSTextAlignmentCenter; label.numberOfLines = 0; }
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.configuration = UIButtonConfiguration.tintedButtonConfiguration;
    button.tintColor = UIColor.whiteColor; button.accessibilityIdentifier = @"local-play.wait.action";
    [button addTarget:self action:@selector(localPlayWaitAction:) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, detail, button]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:stack];
    NSLayoutConstraint *width = [card.widthAnchor constraintEqualToAnchor:overlay.widthAnchor constant:-48]; width.priority = 750;
    [NSLayoutConstraint activateConstraints:@[
        width, [card.widthAnchor constraintLessThanOrEqualToConstant:430],
        [card.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor], [card.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor constant:-24]
    ]];
    self.lanWaitOverlay = overlay; self.lanWaitTitle = title; self.lanWaitDetail = detail; self.lanWaitButton = button;
    [self.canvas addSubview:overlay];
}
- (void)localPlayWaitAction:(UIButton *)sender {
    (void)sender; dm_lan_wait_info info; dm_lan_wait_snapshot(&info);
    if (info.state == DM_LAN_WAIT_ENDED) self.lanWaitDismissed = YES;
    else dm_lan_wait_cancel();
    [self updateLocalPlayWait];
}
- (void)updateLocalPlayWait {
    dm_lan_wait_info info; dm_lan_wait_snapshot(&info);
    [self scheduleLocalPlayPoll:info.supported || info.state != DM_LAN_WAIT_NONE ? .2 : 1];
    BOOL waiting = info.state >= DM_LAN_WAIT_PREPARING && info.state <= DM_LAN_WAIT_RESUMING;
    front_ios_lan_audio(waiting);
    if (info.local_background && !info.settling) front_lan_task_end();
    if (info.state != DM_LAN_WAIT_ENDED) self.lanWaitDismissed = NO;
    BOOL visible = info.state != DM_LAN_WAIT_NONE && !(info.state == DM_LAN_WAIT_ENDED && self.lanWaitDismissed);
    if (!visible) {
        if (self.lanWaitOverlay && !self.lanWaitOverlay.hidden) { [self.game cancelNativeTouches]; dm_gamepad_reset(); }
        self.lanWaitOverlay.hidden = YES; return;
    }
    BOOL appeared = !self.lanWaitOverlay || self.lanWaitOverlay.hidden;
    if (!self.lanWaitOverlay) [self makeLocalPlayWaitOverlay];
    self.lanWaitOverlay.hidden = NO; self.lanWaitOverlay.frame = self.canvas.bounds;
    [self.canvas bringSubviewToFront:self.lanWaitOverlay];
    if (appeared) { [self.game cancelNativeTouches]; dm_gamepad_reset(); }
    NSString *title = @"Local play is paused", *detail;
    if (info.state == DM_LAN_WAIT_PREPARING) { title = @"Preparing a brief pause"; detail = dm_local_play_text(@"Coordinating all players. Please wait."); }
    else if (info.state == DM_LAN_WAIT_RESUMING) { title = @"Restoring local play"; detail = dm_local_play_text(@"Checking that every player is ready."); }
    else if (info.state == DM_LAN_WAIT_ENDED) { title = @"Local-play wait ended"; detail = dm_local_play_text(@"Return to the game and visit the island again."); }
    else detail = [NSString stringWithFormat:dm_local_play_text(@"Waiting for a player to return. %d seconds remaining."), info.seconds];
    self.lanWaitTitle.text = dm_local_play_text(title); self.lanWaitDetail.text = detail;
    [self.lanWaitButton setTitle:dm_local_play_text(waiting ? @"End local play" : @"Return to game") forState:UIControlStateNormal];
}
