#import <UIKit/UIKit.h>
UIView *dm_touch_controls_preview(BOOL portrait);
void dm_touch_controls_configure(UIView *view,NSDictionary *profile,BOOL portrait);
NSArray *dm_touch_controls_handles(UIView *view);
BOOL dm_canvas_half_turn(UIViewController *owner);
CGFloat dm_canvas_rotation(UIViewController *owner);
