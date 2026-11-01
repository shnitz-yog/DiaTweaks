// The pins leave the sidebar: Dia stacks their dock and a hairline above the tab list, which takes over their space.
#import "PinnedNotch.h"

static NSHashTable<NSView *> *DPTabLists;
static char DPSuppressedKey, DPFrameKey;

static NSView *DPTabScroller(NSView *list) {
    for (NSView *sub in list.subviews) if ([sub isKindOfClass:NSScrollView.class]) return sub;
    return nil;
}

// Only ever shows what this hid: Dia hides a dock of its own accord too.
static void DPSuppress(NSView *view, BOOL hide) {
    if (hide) {
        DPSet(view, &DPSuppressedKey, @YES);
        view.hidden = YES;
    } else if (DPGet(view, &DPSuppressedKey)) {
        DPSet(view, &DPSuppressedKey, nil);
        view.hidden = NO;
    }
}

static void DPApplyDock(NSView *list) {
    NSView *dock = DPSubview(list, DPDiaTabDock), *tabs = DPTabScroller(list);
    if (!dock || !tabs) return;
    BOOL hide = DPNotchWanted();
    for (NSView *sub in list.subviews) if (sub != tabs) DPSuppress(sub, hide);
    NSRect laidOut = [DPDiaValue(tabs, &DPFrameKey, @(tabs.frame)) rectValue];
    NSRect frame = hide ? NSUnionRect(laidOut, dock.frame) : laidOut;
    DPOverride(tabs, &DPFrameKey, @(laidOut), @(frame));
    if (!NSEqualRects(tabs.frame, frame)) tabs.frame = frame;
}

static void DPTabList_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPTabList_layout, self);
    [DPTabLists addObject:self];
    DPApplyDock(self);
}

void DPNotchInstallDock(void) {
    DPTabLists = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaTabList, @selector(layout), (IMP)DPTabList_layout);
}

void DPNotchRelayoutDock(void) { DPRelayoutViews(DPTabLists); }

BOOL DPNotchDockHidden(NSView *list) {
    NSView *dock = DPSubview(list, DPDiaTabDock), *tabs = DPTabScroller(list);
    if (!dock || !tabs) return DPNotchWanted();  // No pins here to hide.
    return DPGet(dock, &DPSuppressedKey) != nil && dock.hidden && NSMinY(tabs.frame) <= NSMinY(dock.frame);
}
