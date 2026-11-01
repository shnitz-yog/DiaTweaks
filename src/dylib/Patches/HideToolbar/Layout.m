#import "HideToolbar.h"

NSHashTable<NSView *> *DPPanes;
static char DPFrameKey, DPFillsKey;

NSRect DPLaidOutFrame(NSView *view) {
    return [DPDiaValue(view, &DPFrameKey, @(view.frame)) rectValue];
}

static void DPAssignFrame(NSView *view, NSRect laidOut, NSRect frame) {
    DPOverride(view, &DPFrameKey, @(laidOut), @(frame));
    view.frame = frame;
}

CGFloat DPTop(NSView *pane, NSRect r) { return pane.isFlipped ? NSMinY(r) : NSHeight(pane.bounds) - NSMaxY(r); }
CGFloat DPBottom(NSView *pane, NSRect r) { return pane.isFlipped ? NSMaxY(r) : NSHeight(pane.bounds) - NSMinY(r); }

// Dia lays the bookmarks bar out right under the toolbar, so it hides and shows with it.
NSView *DPBookmarksUnder(NSView *pane, NSView *bar) {
    for (NSView *sub in pane.subviews)
        if (DPIsKind(sub, DPDiaBookmarksBar) && !sub.hidden && fabs(DPTop(pane, DPLaidOutFrame(sub)) - DPBottom(pane, bar.frame)) < 0.5) return sub;
    return nil;
}

// Hover animation changes opacity only; it never changes the page's reserved space.
void DPApplyToolbarOpacity(DPToolbarHover *hover) {
    CGFloat alpha = 1 - DPHideToolbar.progress * (1 - hover.progress);
    if (hover.bar && hover.bar.alphaValue != alpha) hover.bar.alphaValue = alpha;
    if (hover.bookmarks && hover.bookmarks.alphaValue != alpha) hover.bookmarks.alphaValue = alpha;
}

// Fades the bars out by `progress` and slides everything stacked under them up into their place.
void DPApplyToolbar(NSView *pane) {
    NSView *bar = DPSubview(pane, DPDiaToolbar);
    if (!bar) return;

    NSView *bookmarks = DPBookmarksUnder(pane, bar);
    NSArray<NSView *> *bars = bookmarks ? @[bar, bookmarks] : @[bar];
    DPToolbarHover *hover = [DPToolbarHover attachToPane:pane];
    [hover updateForBar:bar bookmarks:bookmarks];

    CGFloat progress = DPHideToolbar.progress;
    DPApplyToolbarOpacity(hover);
    NSIndexSet *slots = [pane.subviews indexesOfObjectsPassingTest:^BOOL(NSView *sub, NSUInteger i, BOOL *stop) { return [bars containsObject:sub]; }];
    BOOL onTop = slots.firstIndex == pane.subviews.count - bars.count, atBottom = slots.lastIndex == bars.count - 1;
    // Revealed on hover, the bars float over the page instead of pushing it down.
    if (hover.revealed || hover.progress > 0) {
        if (!onTop) for (NSView *view in bars) [pane addSubview:view positioned:NSWindowAbove relativeTo:nil];
    } else if (progress > 0 && !atBottom) {
        for (NSView *view in bars.reverseObjectEnumerator) [pane addSubview:view positioned:NSWindowBelow relativeTo:nil];
    } else if (progress == 0 && slots.firstIndex == 0) {
        for (NSView *view in bars) [pane addSubview:view positioned:NSWindowAbove relativeTo:nil];
    }

    CGFloat edge = DPBottom(pane, DPLaidOutFrame(bars.lastObject)), shift = (edge - DPTop(pane, bar.frame)) * progress;
    NSMutableArray<NSView *> *stack = [NSMutableArray new];
    for (NSView *sub in pane.subviews) if (![bars containsObject:sub]) [stack addObject:sub];
    [stack sortUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
        return [@(DPTop(pane, DPLaidOutFrame(a))) compare:@(DPTop(pane, DPLaidOutFrame(b)))];
    }];
    for (NSView *view in stack) {
        NSRect laidOut = DPLaidOutFrame(view);
        if (fabs(DPTop(pane, laidOut) - edge) > 0.5) continue;
        BOOL reachesBottom = fabs(DPBottom(pane, laidOut) - NSHeight(pane.bounds)) < 0.5;
        if (!reachesBottom) edge = DPBottom(pane, laidOut);
        NSRect frame = laidOut;
        if (reachesBottom) frame.size.height += shift;
        if (pane.isFlipped) frame.origin.y -= shift;
        else if (!reachesBottom) frame.origin.y += shift;
        DPAssignFrame(view, laidOut, frame);
        // Dia sizes the web view once instead of autoresizing it.
        for (NSView *child in view.subviews) {
            if (!DPGet(child, &DPFillsKey)) {
                if (!NSEqualRects(child.frame, (NSRect){NSZeroPoint, laidOut.size})) continue;
                DPSet(child, &DPFillsKey, @YES);
            }
            child.frame = view.bounds;
        }
    }
}

void DPRelayoutPanes(void) {
    DPRelayoutViews(DPPanes);
}
