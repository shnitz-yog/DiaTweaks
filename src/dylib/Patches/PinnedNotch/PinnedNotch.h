// Pinned notch: a bite out of the bottom of the page that shows the current site's domain. Hovering it brings up the
// toolbar's buttons and floats the pinned tabs out above it on a light curve; they leave the sidebar. With the toolbar
// hidden it's the address bar too: clicking the domain or pressing ⌘L edits the address in the command palette.
#import "StdPatch/StdPatch.h"

extern DPPatch DPPinnedNotch;
typedef NS_ENUM(NSInteger, DPNotchPlacement) { DPNotchPlacementCenter, DPNotchPlacementCorner };  // In `choices` order.
BOOL DPNotchWanted(void);  // The patch and the hidden toolbar it replaces are both on.

@interface DPNotchPin : NSObject
@property (nonatomic, copy) NSString *name, *host;
@property (nonatomic, copy) void (^open)(void);
@property (nonatomic) BOOL active;
@property (nonatomic, strong) id image, litImage;  // Art.m draws them.
@property (nonatomic) NSSize size;
@end

@interface DPNotchTool : NSObject
@property (nonatomic, copy) NSString *symbol, *title;  // title: the Dia menu or menu item it stands for.
@property (nonatomic) BOOL enabled, isMenu;
@property (nonatomic, strong) id image, litImage;  // Art.m draws them.
@property (nonatomic, strong) CALayer *layer;
@property (nonatomic) NSRect rect;  // Points from the view's top left.
@end

// Tools.m
NSArray<DPNotchTool *> *DPNotchMakeTools(void);  // Half go left of the address, half right.
void DPNotchRefreshTools(NSArray<DPNotchTool *> *tools);
void DPNotchRunTool(DPNotchTool *tool);          // Menus pop up from the notch instead; NotchView.m does that.

// Tabs.m
NSString *DPNotchAddress(void);  // The front window's active tab, or @"".
NSString *DPNotchTitle(void);
NSString *DPNotchDomain(NSString *address, NSString *title);  // The address's host without www., or the title for a page with no web address.
NSString *DPNotchPinName(NSString *title, NSString *host);
NSArray<DPNotchPin *> *DPNotchPins(void);
NSImage *DPNotchFavicon(NSString *host);  // Dia's own copy, or nil.
NSString *DPNotchCheckNames(void);        // nil, or which check failed.

// Art.m
extern const CGFloat DPNotchMoonHeight;
void DPNotchDrawSymbol(NSString *name, CGFloat points, NSColor *color, NSRect rect);
void DPNotchDrawFavicon(NSImage *favicon, NSRect rect, CGFloat radius);  // A globe if there's no favicon.
id DPNotchDrawText(NSString *text, NSAppearance *appearance, CGFloat scale, NSSize *size);
id DPNotchDrawIcon(NSString *host, NSAppearance *appearance, CGFloat scale, NSSize size);
void DPNotchDrawTool(DPNotchTool *tool, NSAppearance *appearance, CGFloat scale);
void DPNotchDrawPin(DPNotchPin *pin, NSAppearance *appearance, CGFloat scale);

// Shape.m
CGPathRef DPNotchCreateHole(CGFloat center, CGFloat width, CGFloat height, CGFloat pageHeight, BOOL topDown);
CGPathRef DPNotchCreateCornerHole(CGFloat width, CGFloat height, CGFloat pageHeight, BOOL topDown);  // In the page's bottom left corner.
void DPNotchSpring(CALayer *layer, NSString *keyPath, id from, id to, CFTimeInterval delay);

// Dock.m
void DPNotchInstallDock(void);
void DPNotchRelayoutDock(void);
BOOL DPNotchDockHidden(NSView *tabList);

// NotchView.m
@interface DPNotchView : NSView
@property (nonatomic, readonly, weak) NSView *page;
@property (nonatomic, readonly, copy) NSString *shown;
- (instancetype)initWithPage:(NSView *)page;
- (void)place;    // Follows the window, once Dia has laid it out.
- (void)refresh;  // Reads the active tab again.
- (void)detach;
- (void)setOpen:(BOOL)open;
- (NSDictionary *)debugState;
@end
