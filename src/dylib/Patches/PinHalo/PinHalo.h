// Pin halo: holding Control fans the pinned tabs and search out around the pointer. Flick toward one and let go.
#import "StdPatch/StdPatch.h"

extern DPPatch DPPinHalo;

// Which slot a pointer this far from the centre points at, or -1. Slots run clockwise from straight up; mirrored runs them anticlockwise.
NSInteger DPHaloPick(CGFloat dx, CGFloat dy, NSInteger count, BOOL mirrored);
NSString *DPHaloCheckPicks(void);  // nil, or which check failed.

// Over one window, for as long as it's open. It never takes the pointer: the page keeps working under it.
@interface DPHaloView : NSView
@property (nonatomic, readonly, copy) NSString *picked;
- (instancetype)initInWindow:(NSWindow *)window at:(NSPoint)point;  // In the window's coordinates.
- (void)pointerAt:(NSPoint)point;
- (void)close;                 // Without doing anything.
- (void)closeRunningPick;
- (NSDictionary *)debugState;
@end
