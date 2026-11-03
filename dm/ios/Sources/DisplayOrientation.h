// Native geometry follows the logical axis; the owned canvas supplies reversals
// relative to the effective scene. Display-role detection is independent of it.
#pragma once
#import <UIKit/UIKit.h>
static inline UIInterfaceOrientation dm_display_direction(UIDeviceOrientation device) {
    switch(device){
        case UIDeviceOrientationPortrait:return UIInterfaceOrientationPortrait;
        case UIDeviceOrientationPortraitUpsideDown:return UIInterfaceOrientationPortraitUpsideDown;
        case UIDeviceOrientationLandscapeLeft:return UIInterfaceOrientationLandscapeRight;
        case UIDeviceOrientationLandscapeRight:return UIInterfaceOrientationLandscapeLeft;
        default:return UIInterfaceOrientationUnknown;
    }
}
static inline NSInteger dm_display_quarter(UIInterfaceOrientation orientation) {
    switch(orientation){
        case UIInterfaceOrientationLandscapeRight:return 1;
        case UIInterfaceOrientationPortraitUpsideDown:return 2;
        case UIInterfaceOrientationLandscapeLeft:return 3;
        default:return 0;
    }
}
static inline NSInteger dm_display_rotation(UIInterfaceOrientation native,UIInterfaceOrientation content) {
    return (dm_display_quarter(content)-dm_display_quarter(native)+4)%4;
}
static inline UIInterfaceOrientationMask dm_display_native_axis(UIInterfaceOrientation content,BOOL portraitReferenceWide) {
    // A folding panel can be wide in the device's portrait reference. Its
    // display layout axis must include that panel basis, not just the enum.
    BOOL portrait=UIInterfaceOrientationIsPortrait(content)!=portraitReferenceWide;
    return portrait?UIInterfaceOrientationMaskPortrait:UIInterfaceOrientationMaskLandscapeRight;
}
static inline CGSize dm_display_canvas_size(CGSize native,NSInteger quarters) {
    return quarters&1?CGSizeMake(native.height,native.width):native;
}
