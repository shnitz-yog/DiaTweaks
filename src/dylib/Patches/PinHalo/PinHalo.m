// When it opens and closes: a Control press held alone opens it, letting go runs the pick. Anything else that uses
// Control, such as Control-click or a shortcut, cancels it and carries on as usual.
#import "PinHalo.h"
#import "Patches/CommandPalette/CommandPalette.h"

static const NSTimeInterval DPHoldDelay = .14, DPFollowSeconds = 1.0 / 60;
static DPHaloView *DPOpenHalo;
static NSTimer *DPHoldTimer, *DPFollowTimer;

NSDictionary *DPHaloDebugState(void) { return DPOpenHalo.debugState; }

static void DPStopTimers(void) {
    [DPHoldTimer invalidate];
    [DPFollowTimer invalidate];
    DPHoldTimer = DPFollowTimer = nil;
}

static void DPCancelHalo(void) {
    DPStopTimers();
    [DPOpenHalo close];
    DPOpenHalo = nil;
}

static NSWindow *DPHaloWindow(void) {
    NSWindow *window = NSApp.keyWindow;
    BOOL browser = window && ![window isKindOfClass:NSPanel.class] && !NSApp.modalWindow
        && DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaContentPane); });
    return browser && NSPointInRect(NSEvent.mouseLocation, window.frame) ? window : nil;
}

static void DPOpenHaloAt(NSWindow *window, NSPoint point) {
    DPOpenHalo = [[DPHaloView alloc] initInWindow:window at:point];
    DPFollowTimer = [NSTimer timerWithTimeInterval:DPFollowSeconds repeats:YES block:^(NSTimer *_) {
        [DPOpenHalo pointerAt:[DPOpenHalo.window convertPointFromScreen:NSEvent.mouseLocation]];
    }];
    [NSRunLoop.mainRunLoop addTimer:DPFollowTimer forMode:NSRunLoopCommonModes];
}

static void DPStartHold(void) {
    DPHoldTimer = [NSTimer scheduledTimerWithTimeInterval:DPHoldDelay repeats:NO block:^(NSTimer *_) {
        DPHoldTimer = nil;
        NSWindow *window = DPHaloWindow();
        if (window) DPOpenHaloAt(window, [window convertPointFromScreen:NSEvent.mouseLocation]);
    }];
}

static void DPFlagsChanged(NSEvent *event) {
    NSEventModifierFlags flags = event.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption);
    if (flags == NSEventModifierFlagControl) {
        if (!DPOpenHalo && !DPHoldTimer && !DPPaletteIsOpen()) DPStartHold();
    } else if (flags == 0 && DPOpenHalo) {
        DPHaloView *halo = DPOpenHalo;
        DPOpenHalo = nil;
        DPStopTimers();
        [halo closeRunningPick];
    } else DPCancelHalo();
}

static NSEvent *DPHandleEvent(NSEvent *event) {
    if (event.type == NSEventTypeFlagsChanged) {
        if (DPPinHalo.on) DPFlagsChanged(event);
        return event;
    }
    BOOL escape = event.type == NSEventTypeKeyDown && event.keyCode == 53 && DPOpenHalo;
    DPCancelHalo();
    return escape ? nil : event;
}

// With the developer tools on, a script can look at it: com.diapatches.dev.halo, object "open" or "close".
static void DPListenForScripts(void) {
    if (![[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] boolForKey:@"devTools"]) return;
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:@"com.diapatches.dev.halo" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        NSWindow *window = NSApp.mainWindow;
        DPCancelHalo();
        if ([note.object isEqual:@"open"] && window) DPOpenHalo = [[DPHaloView alloc] initInWindow:window at:NSMakePoint(NSMidX(window.contentView.bounds), NSMidY(window.contentView.bounds))];
    }];
}

static void DPInstallPinHalo(void) {
    DPListenForScripts();
    DPOnLaunch(^{
        NSEventMask mask = NSEventMaskFlagsChanged | NSEventMaskKeyDown | NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown | NSEventMaskScrollWheel;
        [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) { return DPHandleEvent(event); }];
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification *_) { DPCancelHalo(); }];
    });
}

static void DPApplyPinHalo(DPPatch *patch) {
    if (!patch->on) DPCancelHalo();
}

static NSString *DPVerifyPinHalo(DPPatch *patch) {
    NSString *problem = DPHaloCheckPicks();
    if (problem) return problem;
    return !patch->on && DPOpenHalo ? @"open while off" : nil;
}

DP_PATCH(DPPinHalo) {
    .key = @"pinHalo",
    .order = 120,
    .title = @"Pin halo",
    .detail = @"Hold Control to fan your pinned tabs and search out around the pointer, then flick toward one and let go.",
    .symbol = @"circle.dashed",
    .tint = @"systemTealColor",
    .section = @"Window",
    .classes = DPClasses("DiaAppleScriptTab", DPDiaContentPane),
    .install = DPInstallPinHalo,
    .apply = DPApplyPinHalo,
    .verify = DPVerifyPinHalo,
};
