#import "PinnedNotch.h"
#import "Patches/CommandPalette/CommandPalette.h"
#import "Patches/HideToolbar/HideToolbar.h"

static const NSTimeInterval DPRefreshSeconds = .5;
static char DPNotchKey;

BOOL DPNotchWanted(void) { return DPPinnedNotch.on && DPHideToolbar.on; }

static DPNotchView *DPNotchOf(NSWindow *window) { return window ? DPGet(window, &DPNotchKey) : nil; }

NSDictionary *DPNotchDebugState(NSWindow *window) { return DPNotchOf(window).debugState; }

static void DPUpdateNotch(NSWindow *window) {
    if (!window) return;
    DPNotchView *notch = DPNotchOf(window);
    if (!DPNotchWanted()) {
        [notch detach];
        DPSet(window, &DPNotchKey, nil);
        return;
    }
    if (!notch) {
        NSView *page = DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaContentContainer); });
        if (!page || [window isKindOfClass:NSPanel.class]) return;
        notch = [[DPNotchView alloc] initWithPage:page];
        DPSet(window, &DPNotchKey, notch);
        [notch refresh];
    }
    [notch place];
}

static void DPPane_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPPane_layout, self);
    DPUpdateNotch(self.window);
}

// The toolbar's address field is hidden with it, so ⌘L would have you typing into nothing.
static NSEvent *DPHandleKey(NSEvent *event) {
    NSWindow *window = NSApp.keyWindow;
    if (!DPNotchOf(window) || !DPIsCommand(event, @"l") || NSApp.modalWindow) return event;
    if (!event.isARepeat) DPPaletteOpen(window, DPNotchAddress());
    return nil;
}

// With the developer tools on, a script can look at it: com.diapatches.dev.notch, object "open", "close", "center" or "corner".
static void DPListenForScripts(void) {
    if (![[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] boolForKey:@"devTools"]) return;
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:@"com.diapatches.dev.notch" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if ([note.object isEqual:@"center"] || [note.object isEqual:@"corner"]) DPSetPatchChoice(&DPPinnedNotch, [note.object isEqual:@"corner"]);
        else [DPNotchOf(NSApp.mainWindow) setOpen:[note.object isEqual:@"open"]];
    }];
}

static void DPInstallPinnedNotch(void) {
    DPNotchInstallDock();
    DPListenForScripts();
    DPHook(DPDiaContentPane, @selector(layout), (IMP)DPPane_layout);
    DPOnLaunch(^{
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { return DPHandleKey(event); }];
        [NSTimer scheduledTimerWithTimeInterval:DPRefreshSeconds repeats:YES block:^(NSTimer *_) {
            if (NSApp.isActive) [DPNotchOf(NSApp.mainWindow) refresh];
        }];
    });
}

static void DPRelayoutNotch(void) {
    for (NSWindow *window in NSApp.windows) DPUpdateNotch(window);
    DPNotchRelayoutDock();
}

static NSString *DPVerifyPinnedNotch(DPPatch *patch) {
    NSString *problem = DPNotchCheckNames();
    if (problem) return problem;
    BOOL wanted = DPNotchWanted();
    for (NSView *list in DPFindViews(DPDiaTabList))
        if (DPNotchDockHidden(list) != wanted) return wanted ? @"pins are still in the sidebar" : @"pins are missing from the sidebar";
    for (NSView *page in DPFindViews(DPDiaContentContainer)) {
        DPNotchView *notch = DPNotchOf(page.window);
        if ((notch != nil) != wanted) return wanted ? @"window has no notch" : @"notch still shows";
        if ((page.layer.mask != nil) != wanted) return wanted ? @"page has no hole" : @"page still has a hole";
        if (wanted && !notch.shown.length) return @"notch shows no address";
        if (wanted && notch.superview.subviews.lastObject != notch) return @"notch is behind the page";
    }
    return nil;
}

DP_PATCH(DPPinnedNotch) {
    .key = @"pinnedNotch",
    .order = 110,
    .title = @"Pinned notch",
    .detail = @"Replace the toolbar with a notch at the bottom of the window that shows the site’s domain. Hover it for back, forward, extensions and your pinned tabs, which leave the sidebar, and to search with the command palette.",
    .symbol = @"pin",
    .tint = @"systemIndigoColor",
    .requires = @"hideToolbar",
    .choiceTitle = @"Placement",
    .choices = DPClasses("Bottom center", "Bottom left corner"),
    .classes = DPClasses("DiaAppleScriptTab", DPDiaContentPane, DPDiaContentContainer, DPDiaTabList, DPDiaTabDock),
    .install = DPInstallPinnedNotch,
    .relayout = DPRelayoutNotch,
    .verify = DPVerifyPinnedNotch,
};
