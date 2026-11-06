#pragma once
#import <Foundation/Foundation.h>
#include <stdlib.h>
NS_ASSUME_NONNULL_BEGIN
static inline NSString *dm_local_play_text(NSString *key) {
    NSString *lang = getenv("DM_LANG") ? @(getenv("DM_LANG")) : NSBundle.mainBundle.preferredLocalizations.firstObject;
    NSString *path = lang.length ? [NSBundle.mainBundle pathForResource:lang ofType:@"lproj"] : nil;
    NSBundle *bundle = path ? [NSBundle bundleWithPath:path] : NSBundle.mainBundle;
    return [bundle localizedStringForKey:key value:key table:@"Multiplayer"];
}
NS_ASSUME_NONNULL_END
