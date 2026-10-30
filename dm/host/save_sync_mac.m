// AppKit setup uses the same checkpoint engine and format as iPad/iPhone.
#import <AppKit/AppKit.h>
#import "save_sync_apple.h"
static NSString *T(NSString *key){return dm_save_sync_text(key);}
static NSString *setupKey(void){return [@"save-sync-show-setup-" stringByAppendingString:NSBundle.mainBundle.bundleIdentifier ?: @"host"];}
static NSString *seenKey(void){return [setupKey() stringByAppendingString:@"-seen"];}
static BOOL chooseFolder(DMSaveSync *sync) {
    NSOpenPanel *panel=NSOpenPanel.openPanel;panel.canChooseFiles=NO;panel.canChooseDirectories=YES;panel.allowsMultipleSelection=NO;
    panel.message=T(@"Choose the same iCloud Drive folder on every device.");panel.prompt=T(@"Use this folder");
    if([panel runModal]!=NSModalResponseOK)return NO;
    NSError *e;if([sync selectFolder:panel.URL error:&e])return YES;
    NSAlert *a=[NSAlert new];a.messageText=T(@"Cloud saves");a.informativeText=T(e.localizedDescription);[a runModal];return NO;
}
static id workWithProgressTitle(NSString *title,id (^work)(NSError **),NSError **error) {
    NSAlert *a=[NSAlert new];a.messageText=T(title);
    [a addButtonWithTitle:T(@"Working…")].enabled=NO;
    NSProgressIndicator *spinner=[[NSProgressIndicator alloc]initWithFrame:NSMakeRect(0,0,300,20)];spinner.style=NSProgressIndicatorStyleBar;spinner.indeterminate=YES;[spinner startAnimation:nil];a.accessoryView=spinner;
    __block id result;__block NSError *e;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{result=work(&e);dispatch_async(dispatch_get_main_queue(),^{[NSApp stopModal];[a.window orderOut:nil];});}});
    [a runModal];if(error)*error=e;return result;
}
static id workWithProgress(id (^work)(NSError **),NSError **error) {return workWithProgressTitle(@"Checking cloud saves…",work,error);}
static NSString *manageKey(void){return [setupKey()stringByAppendingString:@"-manage"];}
static void showSaveCenter(DMSaveSync *s,BOOL beforeStart) {
    for(;;){
        NSError *error;NSDictionary *center=workWithProgressTitle(@"Reading save status…",^id(NSError **e){return [s saveCenter:e];},&error);
        if(!center){NSAlert *a=[NSAlert new];a.messageText=T(@"Save center");a.informativeText=T(error.localizedDescription ?: @"The save center could not be read.");[a runModal];return;}
        NSArray *rows=center[@"history"];NSAlert *a=[NSAlert new];a.messageText=T(@"Save center");
        a.informativeText=[NSString stringWithFormat:@"%@: %@\n%@: %@\n%@\n\n%@",T(@"Last game save"),[center[@"localSavedAt"]length] ? center[@"localSavedAt"]:T(@"Not recorded yet"),T(@"Last folder publication"),[center[@"publishedAt"]length] ? center[@"publishedAt"]:T(@"Not recorded yet"),T(center[@"uploadState"]),T(@"Writing a checkpoint to the folder is separate from uploading it. An uploaded file does not confirm that another device has read it.")];
        NSTextField *name=[NSTextField new];name.placeholderString=T(@"Checkpoint name");
        NSPopUpButton *history=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(0,0,460,28) pullsDown:NO];
        for(NSDictionary *row in rows)[history addItemWithTitle:[NSString stringWithFormat:@"%@ · %@",T(row[@"name"]),row[@"date"]]];
        NSStackView *stack=[NSStackView stackViewWithViews:@[name,history]];stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=12;stack.frame=NSMakeRect(0,0,460,76);name.frame=NSMakeRect(0,0,460,28);a.accessoryView=stack;
        [a addButtonWithTitle:T(@"Done")];[a addButtonWithTitle:T(@"Create checkpoint")];[a addButtonWithTitle:T(@"Restore")];[a addButtonWithTitle:T(@"Delete")];
        if(!beforeStart)[a addButtonWithTitle:T(@"Manage saves next launch")];
        a.buttons[1].enabled=beforeStart;a.buttons[2].enabled=beforeStart && rows.count>0;a.buttons[3].enabled=beforeStart && rows.count>0;
        NSModalResponse response=[a runModal];if(response==NSAlertFirstButtonReturn)return;
        if(response==NSAlertFirstButtonReturn+4){[NSUserDefaults.standardUserDefaults setBool:YES forKey:manageKey()];return;}
        NSDictionary *selected=history.indexOfSelectedItem>=0 && history.indexOfSelectedItem<(NSInteger)rows.count ? rows[history.indexOfSelectedItem]:nil;
        if(response==NSAlertFirstButtonReturn+2 || response==NSAlertFirstButtonReturn+3){
            NSAlert *confirm=[NSAlert new];confirm.messageText=T(response==NSAlertFirstButtonReturn+2 ? @"Restore this complete island?":@"Delete this named checkpoint?");confirm.informativeText=[NSString stringWithFormat:@"%@\n%@",T(selected[@"name"] ?: @""),response==NSAlertFirstButtonReturn+2 ? T(@"Your current local save will be backed up before replacement."):@""];
            [confirm addButtonWithTitle:T(@"Cancel")];[confirm addButtonWithTitle:T(response==NSAlertFirstButtonReturn+2 ? @"Restore":@"Delete")];if([confirm runModal]!=NSAlertSecondButtonReturn)continue;
        }
        NSString *checkpointName=name.stringValue;
        NSString *progress=response==NSAlertFirstButtonReturn+1 ? @"Creating checkpoint…":(response==NSAlertFirstButtonReturn+2 ? @"Restoring checkpoint…":@"Deleting checkpoint…");
        NSNumber *ok=workWithProgressTitle(progress,^id(NSError **e){
            if(response==NSAlertFirstButtonReturn+1)return @([s createCheckpoint:checkpointName error:e]);
            if(response==NSAlertFirstButtonReturn+2)return @([s restoreCheckpoint:selected[@"id"] token:selected[@"token"] error:e]);
            return @([s deleteCheckpoint:selected[@"id"] error:e]);
        },&error);
        if(!ok.boolValue){NSAlert *failure=[NSAlert new];failure.messageText=T(@"Save center");failure.informativeText=T(error.localizedDescription ?: @"The operation failed.");[failure runModal];}
    }
}
void dm_save_sync_mac_prepare(void (^ready)(void)) {
    DMSaveSync *s=DMSaveSync.shared;NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    if([d boolForKey:manageKey()]){[d removeObjectForKey:manageKey()];showSaveCenter(s,YES);}
    BOOL configured=[s.status[@"configured"]boolValue], needs=[s.status[@"needsAccess"]boolValue];
    BOOL setup=[d boolForKey:setupKey()] || ([[NSBundle.mainBundle objectForInfoDictionaryKey:@"DMCloudSaveSetup"]boolValue] && ![d boolForKey:seenKey()]);
    if(setup || needs){
        NSModalResponse r;
        do {
            NSAlert *a=[NSAlert new];a.messageText=T(@"Cloud saves");a.informativeText=T(@"Share one complete island between iPad, iPhone and Mac. Choose an iCloud Drive folder once on each device.");
            [a addButtonWithTitle:T(@"Choose iCloud folder")];[a addButtonWithTitle:T(@"Use local saves")];[a addButtonWithTitle:T(@"Save center")];r=[a runModal];
            if(r==NSAlertThirdButtonReturn)showSaveCenter(s,YES);
        } while(r==NSAlertThirdButtonReturn);
        [d setBool:YES forKey:seenKey()];[d removeObjectForKey:setupKey()];
        if(r==NSAlertFirstButtonReturn){if(!chooseFolder(s)){[s beginOfflineSession];ready();return;}configured=YES;}
        else{[s disconnect];[s beginOfflineSession];ready();return;}
    }
    if(!configured){[s beginOfflineSession];ready();return;}
    for(;;){
        NSError *e;NSDictionary *p=workWithProgress(^id(NSError **err){return [s inspect:err];},&e);
        NSString *choice=@"";
        if(p && [p[@"conflict"]boolValue]){
            NSAlert *a=[NSAlert new];a.messageText=T(@"Choose which save to continue");a.informativeText=T(@"Devices have different progress. Your current local save will be backed up before replacement.");
            NSPopUpButton *list=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(0,0,440,28) pullsDown:NO];
            for(NSDictionary *r in p[@"choices"])[list addItemWithTitle:[NSString stringWithFormat:@"%@  %@",T(r[@"label"]),r[@"date"]]];
            a.accessoryView=list;[a addButtonWithTitle:T(@"Use selected save")];[a addButtonWithTitle:T(@"Play local for this session")];
            if([a runModal]!=NSAlertFirstButtonReturn){[s beginOfflineSession];ready();return;}
            choice=p[@"choices"][[list indexOfSelectedItem]][@"id"];
        }
        if(p){NSNumber *ok=workWithProgress(^id(NSError **err){return @([s prepareChoice:choice token:p[@"token"] error:err]);},&e);if(ok.boolValue){[s beginSession];ready();return;}}
        NSAlert *a=[NSAlert new];a.messageText=T(@"Cloud sync needs attention");a.informativeText=T(e.localizedDescription ?: @"Cloud sync failed. The local save is retained.");
        [a addButtonWithTitle:T(@"Retry")];[a addButtonWithTitle:T(@"Play local for this session")];[a addButtonWithTitle:T(@"Choose iCloud folder")];
        NSModalResponse r=[a runModal];if(r==NSAlertSecondButtonReturn){[s beginOfflineSession];ready();return;}
        if(r==NSAlertThirdButtonReturn){if(!chooseFolder(s)){[s beginOfflineSession];ready();return;}}
    }
}
@interface DMSaveSyncMenu : NSObject
- (void)show:(id)sender;
- (void)center:(id)sender;
- (void)performance:(id)sender;
@end
@implementation DMSaveSyncMenu
- (void)center:(id)sender {(void)sender;showSaveCenter(DMSaveSync.shared,NO);}
- (void)performance:(id)sender {
    (void)sender;NSAlert *a=[NSAlert new];a.messageText=T(@"Performance recording");a.informativeText=T(@"Recording begins when the game starts. Every 10 seconds, it records displayed frame rate, frame times, memory and thermal state. The next launch uses this setting.");
    NSButton *toggle=[NSButton checkboxWithTitle:T(@"Record a 30-minute performance session") target:nil action:nil];toggle.state=[NSUserDefaults.standardUserDefaults boolForKey:@"DmPerformanceRecord"] ? NSControlStateValueOn:NSControlStateValueOff;a.accessoryView=toggle;
    [a addButtonWithTitle:T(@"Done")];[a addButtonWithTitle:T(@"Open reports folder")];NSModalResponse response=[a runModal];[NSUserDefaults.standardUserDefaults setBool:toggle.state==NSControlStateValueOn forKey:@"DmPerformanceRecord"];
    if(response==NSAlertSecondButtonReturn && getenv("DM_ROOT")){
        NSURL *folder=[[NSURL fileURLWithPath:@(getenv("DM_ROOT")) isDirectory:YES]URLByAppendingPathComponent:@"performance" isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];[NSWorkspace.sharedWorkspace openURL:folder];
    }
}
- (void)show:(id)sender {
    (void)sender;NSAlert *a=[NSAlert new];a.messageText=T(@"Cloud saves");a.informativeText=[NSString stringWithFormat:@"%@\n\n%@",T(DMSaveSync.shared.status[@"message"]),T(@"Save and restart the game to change the cloud folder or load another save.")];
    [a addButtonWithTitle:T(@"OK")];[a addButtonWithTitle:T(@"Configure next launch")];if([a runModal]==NSAlertSecondButtonReturn)[NSUserDefaults.standardUserDefaults setBool:YES forKey:setupKey()];
}
@end
void dm_save_sync_mac_menu(void) {
    static DMSaveSyncMenu *target;target=[DMSaveSyncMenu new];
    NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:T(@"Cloud saves…") action:@selector(show:) keyEquivalent:@""];item.target=target;
    [NSApp.mainMenu.itemArray.firstObject.submenu insertItem:item atIndex:0];
    NSMenuItem *center=[[NSMenuItem alloc]initWithTitle:T(@"Save center") action:@selector(center:) keyEquivalent:@""];center.target=target;[NSApp.mainMenu.itemArray.firstObject.submenu insertItem:center atIndex:0];
    NSMenuItem *performance=[[NSMenuItem alloc]initWithTitle:T(@"Performance recording") action:@selector(performance:) keyEquivalent:@""];performance.target=target;[NSApp.mainMenu.itemArray.firstObject.submenu insertItem:performance atIndex:1];
}
