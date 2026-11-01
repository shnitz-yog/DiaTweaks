// The panel over the browser window: the search bar, the keys and mouse, and the motion Orbit.m draws.
#import "CommandPalette.h"

extern const NSInteger DPOrbitLoopsFrom;

static const NSTimeInterval DPMoonWait = 2, DPScrollSettle = .11;
static const CGFloat DPPillHeight = 58, DPIdleWidth = 460, DPOpenWidth = 240, DPCollapsedWidth = 58, DPScrollPerStep = 70;
static const double DPSpinRate = 16, DPRevealRate = 12, DPFocusRate = 11;

@interface DPPalettePanel : NSPanel
@end

@implementation DPPalettePanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface DPPaletteRoot : NSView
@property (nonatomic, copy) void (^onClick)(NSPoint point);
@property (nonatomic, copy) void (^onScroll)(NSEvent *event);
@end

@implementation DPPaletteRoot
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event { self.onClick([self convertPoint:event.locationInWindow fromView:nil]); }
- (void)scrollWheel:(NSEvent *)event { self.onScroll(event); }
@end

static void DPEase(CGFloat *value, CGFloat goal, double rate, double seconds, BOOL instant) {
    *value += (goal - *value) * (instant ? 1 : 1 - exp(-seconds * rate));
    if (fabs(goal - *value) < .002) *value = goal;
}

static NSInteger DPWrap(NSInteger value, NSInteger count) { return ((value % count) + count) % count; }

@interface DPPaletteController : NSObject <NSTextFieldDelegate, NSWindowDelegate>
@end

@implementation DPPaletteController {
    DPPalettePanel *_panel;
    DPPaletteRoot *_root;
    DPOrbit *_orbit;
    NSVisualEffectView *_backdrop;
    NSView *_pill;
    NSImageView *_icon;
    NSTextField *_field, *_ghost, *_shortcut;
    __weak NSWindow *_parent;
    NSArray<DPPaletteRow *> *_all, *_shown;
    NSString *_completion, *_query;
    CADisplayLink *_link;
    NSTimer *_moonTimer;
    CFTimeInterval _lastTick;
    NSRect _pillRect;  // Points from the top left.
    double _position, _target;
    CGFloat _reveal, _moonReveal, _focus;
    NSInteger _moonFocus;
    BOOL _moonsOpen;
}

- (instancetype)init {
    self = [super init];
    _panel = [[DPPalettePanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:YES];
    _panel.delegate = self;
    _panel.releasedWhenClosed = NO;
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = NO;

    _root = [[DPPaletteRoot alloc] initWithFrame:NSZeroRect];
    _root.wantsLayer = YES;
    __weak DPPaletteController *weakSelf = self;
    _root.onClick = ^(NSPoint point) { [weakSelf clickedAt:point]; };
    _root.onScroll = ^(NSEvent *event) { [weakSelf scrolled:event]; };
    _panel.contentView = _root;

    // Blurs the page itself, so its text and images can't compete with the results.
    _backdrop = [[NSVisualEffectView alloc] initWithFrame:_root.bounds];
    _backdrop.material = NSVisualEffectMaterialHUDWindow;
    _backdrop.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _backdrop.state = NSVisualEffectStateActive;
    _backdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_root addSubview:_backdrop];

    _orbit = [DPOrbit new];
    _orbit.view.frame = _root.bounds;
    [_root addSubview:_orbit.view];

    _pill = [[NSView alloc] initWithFrame:NSZeroRect];
    _pill.wantsLayer = YES;
    _pill.layer.cornerRadius = 18;
    _pill.layer.borderWidth = 1;
    _pill.layer.shadowColor = NSColor.blackColor.CGColor;
    _pill.layer.shadowOpacity = .22;
    _pill.layer.shadowRadius = 13;
    _pill.layer.shadowOffset = CGSizeMake(0, -12);
    [_root addSubview:_pill];

    _icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"magnifyingglass" accessibilityDescription:nil]];
    _icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightMedium];
    [_pill addSubview:_icon];

    _ghost = [NSTextField labelWithString:@""];
    _ghost.font = [NSFont systemFontOfSize:17];
    _ghost.lineBreakMode = NSLineBreakByClipping;
    [_pill addSubview:_ghost];

    _field = [NSTextField textFieldWithString:@""];
    _field.bezeled = NO;
    _field.drawsBackground = NO;
    _field.focusRingType = NSFocusRingTypeNone;
    _field.font = [NSFont systemFontOfSize:17];
    _field.placeholderString = @"Search or ask anything";
    _field.accessibilityLabel = @"Command palette search";
    _field.cell.scrollable = YES;
    _field.cell.usesSingleLineMode = YES;
    _field.delegate = self;
    [_pill addSubview:_field];

    _shortcut = [NSTextField labelWithString:@"⌘T"];
    _shortcut.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    [_pill addSubview:_shortcut];
    return self;
}

- (BOOL)isOpen { return _panel.visible; }
- (DPPaletteRow *)activeRow { return _shown.count ? _shown[DPWrap(lround(_target), _shown.count)] : nil; }

#pragma mark Opening and closing

- (void)paint {
    NSAppearance *appearance = _panel.effectiveAppearance;
    [appearance performAsCurrentDrawingAppearance:^{
        self->_pill.layer.backgroundColor = DPPaletteSurfaceColor().CGColor;
        self->_pill.layer.borderColor = DPPaletteLineColor().CGColor;
    }];
    _icon.contentTintColor = _shortcut.textColor = DPPaletteFaintTextColor();
    BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    // Results need something to stand against: dark ones on a brightened page, light ones on a tinted one.
    [_orbit setScrimColor:dark ? [NSColor colorWithWhite:1 alpha:.08] : [NSColor colorWithSRGBRed:.18 green:.16 blue:.12 alpha:.2] appearance:appearance];
}

- (void)showOver:(NSWindow *)parent {
    _parent = parent;
    _panel.appearance = parent.effectiveAppearance;
    _orbit.scale = parent.backingScaleFactor;
    [_panel setFrame:parent.frame display:NO];
    [self paint];
    _all = DPPaletteSnapshot();
    _field.stringValue = @"";
    _position = _target = _reveal = _moonReveal = _focus = 0;
    [self reload];
    _pillRect = [self pillGoal];
    [parent addChildWindow:_panel ordered:NSWindowAbove];
    [_panel makeKeyAndOrderFront:nil];
    [_panel makeFirstResponder:_field];
    [self layoutPanel];
    _lastTick = CACurrentMediaTime();
    _link = [_root displayLinkWithTarget:self selector:@selector(tick:)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)fill:(NSString *)text {
    _field.stringValue = text;
    [self reload];
    [_field selectText:nil];
}

- (void)dismiss {
    if (!_panel.visible) return;
    [_link invalidate];
    _link = nil;
    [self closeMoons];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(settle) object:nil];
    [_panel.parentWindow removeChildWindow:_panel];
    [_panel orderOut:nil];
    _all = _shown = nil;
    _orbit.rows = nil;
    _orbit.moonRow = nil;
}

- (void)dismissToParent {
    NSWindow *parent = _parent;
    [self dismiss];
    [parent makeKeyWindow];
}

- (void)run {
    DPPaletteRow *row = self.activeRow;
    void (^action)(void) = _moonFocus >= 0 ? row.moons[_moonFocus].action : row.action;
    if (!row) action = ^{ DPPaletteRunMenuItem(@"New Tab"); };  // ⌘T then Enter is still a new tab.
    [self dismissToParent];  // Dia's commands act on the key window.
    dispatch_async(dispatch_get_main_queue(), action);
}

- (void)runMoon:(NSInteger)index {
    if (index >= (NSInteger)self.activeRow.moons.count) return;
    _moonFocus = index;
    [self run];
}

// A late notification from the last time it closed mustn't close it again.
- (void)windowDidResignKey:(NSNotification *)note { if (!_panel.isKeyWindow) [self dismiss]; }

#pragma mark Results

- (void)reload {
    _query = [_field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    _shown = DPPaletteFilter(_all, _query);
    for (DPPaletteRow *row in _shown) DPPaletteDrawRow(row, _query, _panel.effectiveAppearance, _orbit.scale);
    _orbit.rows = _shown;
    _position = _target = 0;
    [self restartMoons];
    [self showCompletion];
}

- (void)showCompletion {
    NSString *typed = _field.stringValue;
    DPPaletteRow *row = self.activeRow;
    _completion = nil;
    for (NSString *candidate in @[row.searchText ?: @"", row.title ?: @""]) {
        if (!typed.length || [candidate rangeOfString:typed options:NSCaseInsensitiveSearch | NSAnchoredSearch].location == NSNotFound) continue;
        _completion = candidate;
        break;
    }
    NSMutableAttributedString *ghost = [NSMutableAttributedString new];
    if (_completion) {
        [ghost appendAttributedString:[[NSAttributedString alloc] initWithString:typed attributes:@{NSFontAttributeName: _ghost.font, NSForegroundColorAttributeName: NSColor.clearColor}]];
        [ghost appendAttributedString:[[NSAttributedString alloc] initWithString:[_completion substringFromIndex:typed.length] attributes:@{NSFontAttributeName: _ghost.font, NSForegroundColorAttributeName: DPPaletteFaintTextColor()}]];
    }
    _ghost.attributedStringValue = ghost;
    if (row) NSAccessibilityPostNotificationWithUserInfo(_field, NSAccessibilityAnnouncementRequestedNotification, @{NSAccessibilityAnnouncementKey: row.title});
}

- (void)spin:(NSInteger)steps {
    _target = round(_target) + steps;
    [self restartMoons];
    [self showCompletion];
}

- (void)scrolled:(NSEvent *)event {
    if (!_shown.count || !event.scrollingDeltaY) return;
    _target -= event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / DPScrollPerStep : copysign(1, event.scrollingDeltaY);
    [self restartMoons];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(settle) object:nil];
    [self performSelector:@selector(settle) withObject:nil afterDelay:DPScrollSettle inModes:@[NSRunLoopCommonModes]];
}

- (void)settle {
    [self spin:0];
}

- (void)clickedAt:(NSPoint)point {
    if (NSPointInRect(point, _pill.frame)) return;
    NSInteger moon = [_orbit moonAt:point], steps = [_orbit stepsToResultAt:point];
    if (moon >= 0) {
        _moonFocus = moon;
        [self run];
    } else if (steps == NSNotFound) [self dismissToParent];
    else if (steps == 0) [self run];
    else [self spin:steps];
}

#pragma mark Moons

- (void)closeMoons {
    [_moonTimer invalidate];
    _moonTimer = nil;
    _moonsOpen = NO;
    _moonFocus = -1;
}

// They wait for a pause, so spinning past results doesn't flash everyone's actions.
- (void)restartMoons {
    [self closeMoons];
    if (!self.activeRow.moons.count) return;
    _moonTimer = [NSTimer timerWithTimeInterval:DPMoonWait repeats:NO block:^(NSTimer *_) { self->_moonsOpen = YES; }];
    [NSRunLoop.mainRunLoop addTimer:_moonTimer forMode:NSRunLoopCommonModes];
}

- (void)enterMoons {
    [_moonTimer invalidate];
    _moonsOpen = YES;
    _moonFocus = 0;
}

#pragma mark Keys

- (void)controlTextDidChange:(NSNotification *)note { [self reload]; }

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    NSInteger moons = self.activeRow.moons.count;
    BOOL inMoons = _moonFocus >= 0, atEnd = textView.selectedRange.location == textView.string.length && !textView.selectedRange.length;
    if (command == @selector(moveDown:) || command == @selector(moveUp:)) {
        NSInteger step = command == @selector(moveDown:) ? 1 : -1;
        if (inMoons) _moonFocus = DPWrap(_moonFocus + step, moons);
        else if (_shown.count) [self spin:step];
    } else if (command == @selector(moveRight:) && !inMoons && moons && atEnd) [self enterMoons];
    else if (command == @selector(moveRight:) && inMoons) return YES;
    else if (command == @selector(moveLeft:) && inMoons) [self closeMoons];
    else if (command == @selector(insertNewline:)) [self run];
    else if (command == @selector(insertTab:)) {
        if (_completion) {
            _field.stringValue = _completion;
            textView.selectedRange = NSMakeRange(_completion.length, 0);
            [self reload];
        }
    } else if (command == @selector(cancelOperation:)) {
        if (_moonsOpen) [self closeMoons];
        else if (_field.stringValue.length) {
            _field.stringValue = @"";
            [self reload];
        } else [self dismissToParent];
    } else return NO;
    return YES;
}

#pragma mark Motion

- (NSRect)pillGoal {
    NSSize size = _panel.frame.size;
    DPOrbitFit fit = DPOrbitFitIn(size);
    CGFloat top = fit.hubY - DPPillHeight / 2;
    if (!_shown.count) {
        CGFloat width = MIN(DPIdleWidth, size.width - 32);
        return NSMakeRect(floor((size.width - width) / 2), top, width, DPPillHeight);
    }
    if (_moonFocus >= 0) return NSMakeRect(MAX(14, fit.chipLeft - fit.shift - DPCollapsedWidth - 10), top, DPCollapsedWidth, DPPillHeight);
    return NSMakeRect(fit.left, top, DPOpenWidth, DPPillHeight);
}

- (void)layoutPanel {
    NSSize size = _panel.frame.size;
    _backdrop.alphaValue = _reveal;
    _backdrop.hidden = !_reveal;
    _pill.frame = NSMakeRect(_pillRect.origin.x, size.height - NSMaxY(_pillRect), _pillRect.size.width, _pillRect.size.height);
    CGFloat width = _pillRect.size.width, fieldHeight = _field.intrinsicContentSize.height;
    // Faded, not hidden: a hidden field would lose the keyboard, and every key after → with it.
    NSRect text = NSMakeRect(45, floor((DPPillHeight - fieldHeight) / 2), MAX(width - 61, 40), fieldHeight);
    _field.frame = _ghost.frame = text;
    _field.alphaValue = _ghost.alphaValue = MAX(0, 1 - _focus * 2);
    _icon.frame = NSMakeRect(16 + 3.5 * _focus, (DPPillHeight - 19) / 2, 19, 19);
    _pill.alphaValue = 1 - .4 * _focus;
    _shortcut.hidden = _shown.count > 0;
    [_shortcut sizeToFit];
    _shortcut.frame = NSMakeRect(width - NSWidth(_shortcut.frame) - 16, floor((DPPillHeight - NSHeight(_shortcut.frame)) / 2), NSWidth(_shortcut.frame), NSHeight(_shortcut.frame));
    [_orbit layoutInSize:size motion:(DPOrbitMotion){_position, _reveal, _moonReveal, _focus, _moonFocus}];
}

- (void)tick:(CADisplayLink *)link {
    NSWindow *parent = _parent;
    if (!parent) return [self dismiss];
    if (!NSEqualRects(_panel.frame, parent.frame)) [_panel setFrame:parent.frame display:NO];
    CFTimeInterval now = CACurrentMediaTime();
    double seconds = MIN(now - _lastTick, .04);
    _lastTick = now;
    BOOL instant = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    NSInteger count = _shown.count;
    if (count && count < DPOrbitLoopsFrom) _target = MAX(0, MIN(count - 1, _target));
    CGFloat position = _position;
    DPEase(&position, _target, DPSpinRate, seconds, instant);
    _position = position;
    DPPaletteRow *row = self.activeRow;
    if (row != _orbit.moonRow && row.moons.count) DPPaletteDrawMoons(row, _panel.effectiveAppearance, _orbit.scale);
    if (row != _orbit.moonRow && !_moonReveal) _orbit.moonRow = row;
    DPEase(&_reveal, count ? 1 : 0, DPRevealRate, seconds, instant);
    DPEase(&_moonReveal, _moonsOpen && row == _orbit.moonRow && fabs(_target - _position) < .03 ? 1 : 0, DPSpinRate, seconds, instant);
    DPEase(&_focus, _moonFocus >= 0 ? 1 : 0, DPFocusRate, seconds, instant);
    NSRect goal = [self pillGoal];
    CGFloat x = _pillRect.origin.x, y = _pillRect.origin.y, width = _pillRect.size.width;
    DPEase(&x, goal.origin.x, DPRevealRate, seconds, instant);
    DPEase(&y, goal.origin.y, DPRevealRate, seconds, instant);
    DPEase(&width, goal.size.width, DPRevealRate, seconds, instant);
    _pillRect = NSMakeRect(x, y, width, DPPillHeight);
    [self layoutPanel];
}

- (NSDictionary *)debugState {
    DPPaletteRow *row = self.activeRow;
    return @{@"open": @(self.isOpen), @"query": _field.stringValue, @"count": @(_shown.count), @"active": row.title ?: @"",
             @"moonsOpen": @(_moonsOpen), @"moonReveal": @(_moonReveal), @"focus": @(_focus), @"moon": _moonFocus >= 0 ? row.moons[_moonFocus].title : @"",
             @"keyboard": @(_field.currentEditor != nil), @"completion": _completion ?: @"", @"pillWidth": @(_pillRect.size.width)};
}
@end

static DPPaletteController *DPController(void) {
    static DPPaletteController *controller;
    return controller = controller ?: [DPPaletteController new];
}

BOOL DPPaletteIsOpen(void) { return DPController().isOpen; }

void DPPaletteHide(void) { [DPController() dismiss]; }

NSDictionary *DPPaletteDebugState(void) { return DPController().debugState; }

void DPPaletteRunMoon(NSInteger index) { [DPController() runMoon:index]; }

void DPPaletteOpen(NSWindow *parent, NSString *text) {
    if (DPController().isOpen) return;
    [DPController() showOver:parent];
    [DPController() fill:text];
}

void DPPaletteToggle(NSWindow *parent) {
    if (DPController().isOpen) [DPController() dismissToParent];
    else [DPController() showOver:parent];
}
