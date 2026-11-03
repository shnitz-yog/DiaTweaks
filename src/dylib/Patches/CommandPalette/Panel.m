// The panel over the browser window: the search bar, the keys and mouse, and the motion Orbit.m or Wheel.m draws.
#import "CommandPalette.h"

extern DPPatch DPCommandPalette;

static const NSTimeInterval DPMoonWait = 2, DPScrollSettle = .11, DPSuggestWait = .1;
static const CGFloat DPScrollPerStep = 70;
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
    id<DPPaletteLayout> _layout;  // One of these two, from the Style setting.
    DPOrbit *_orbit;
    DPWheel *_wheel;
    NSVisualEffectView *_backdrop;
    NSView *_pill;
    NSImageView *_icon;
    NSTextField *_field, *_ghost, *_shortcut, *_label, *_hint;
    __weak NSWindow *_parent;
    NSArray<DPPaletteRow *> *_all, *_matches, *_shown;  // _shown: _matches with Google's suggestions added.
    NSArray<NSString *> *_suggestions;
    NSString *_completion, *_query;
    CADisplayLink *_link;
    NSTimer *_moonTimer;
    CFTimeInterval _lastTick;
    NSRect _pillRect;  // Points from the top left.
    double _position, _target;
    CGFloat _reveal, _moonReveal, _focus;
    NSInteger _moonFocus;
    BOOL _moonsOpen, _rightToLeft;
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
    _wheel = [DPWheel new];

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

    // The wheel's: the active result's tag before the text, and the keys above the bar.
    _label = [NSTextField labelWithString:@""];
    _label.alignment = NSTextAlignmentRight;
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    [_pill addSubview:_label];
    _hint = [NSTextField labelWithString:@"↑ ↓ to choose   ·   → for actions   ·   Tab to complete"];
    _hint.font = [NSFont systemFontOfSize:13];
    _hint.alignment = NSTextAlignmentCenter;
    [_root addSubview:_hint];
    return self;
}

- (void)useLayout:(id<DPPaletteLayout>)layout {
    if (layout == _layout) return;
    [_layout.view removeFromSuperview];
    _layout = layout;
    layout.view.frame = _root.bounds;
    [_root addSubview:layout.view positioned:NSWindowBelow relativeTo:_pill];
    DPPaletteBarStyle style = layout.barStyle;
    BOOL wheel = style.labelWidth > 0;
    _field.font = _ghost.font = _label.font = [NSFont systemFontOfSize:style.fontSize];
    _pill.layer.cornerRadius = style.radius;
    _pill.layer.borderWidth = wheel ? 0 : 1;
    _pill.layer.shadowOpacity = wheel ? .12 : .22;
    _pill.layer.shadowRadius = wheel ? 24 : 13;
    _pill.layer.shadowOffset = CGSizeMake(0, wheel ? -8 : -12);
    _icon.hidden = wheel;
    _label.hidden = !wheel;
    _hint.hidden = !style.hintRise;
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
    _icon.contentTintColor = _shortcut.textColor = _label.textColor = _hint.textColor = DPPaletteFaintTextColor();
    BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    // Results need something to stand against: dark ones on a brightened page, light ones on a tinted one.
    [_layout setScrimColor:dark ? [NSColor colorWithWhite:1 alpha:.08] : [NSColor colorWithSRGBRed:.18 green:.16 blue:.12 alpha:.2] appearance:appearance];
}

- (void)showOver:(NSWindow *)parent {
    _parent = parent;
    _panel.appearance = parent.effectiveAppearance;
    [self useLayout:DPPatchChoice(&DPCommandPalette) == 1 ? _wheel : _orbit];
    _layout.scale = parent.backingScaleFactor;
    [_panel setFrame:parent.frame display:NO];
    [self paint];
    _all = DPPaletteSnapshot();
    _suggestions = nil;
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
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_panel.parentWindow removeChildWindow:_panel];
    [_panel orderOut:nil];
    _all = _matches = _shown = nil;
    _layout.rows = nil;
    _layout.moonRow = nil;
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
    NSString *typed = _field.stringValue;
    _query = [typed stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    _matches = DPPaletteFilter(_all, _query);
    // Guesses that still fit stay until new ones come, so results don't flicker between keys.
    _suggestions = [_suggestions filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH[c] %@ AND NOT SELF ==[c] %@", typed, _query]];
    _shown = DPPaletteAddSuggestions(_matches, _suggestions);
    for (DPPaletteRow *row in _shown) [_layout drawRow:row query:_query appearance:_panel.effectiveAppearance];
    _layout.rows = _shown;
    _position = _target = 0;
    [self restartMoons];
    [self showCompletion];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchSuggestions) object:nil];
    if (_query.length) [self performSelector:@selector(fetchSuggestions) withObject:nil afterDelay:DPSuggestWait inModes:@[NSRunLoopCommonModes]];
}

- (void)fetchSuggestions {
    NSString *typed = _field.stringValue;
    __weak DPPaletteController *weakSelf = self;
    DPPaletteFetchSuggestions(typed, ^(NSArray<NSString *> *suggestions) { [weakSelf showSuggestions:suggestions for:typed]; });
}

// Guesses arrive after the results are up, so they slot in without moving the one in front.
- (void)showSuggestions:(NSArray<NSString *> *)suggestions for:(NSString *)typed {
    if (!self.isOpen || !_shown.count || ![typed isEqualToString:_field.stringValue] || [suggestions isEqualToArray:_suggestions ?: @[]]) return;
    DPPaletteRow *active = self.activeRow;
    NSInteger was = DPWrap(lround(_target), _shown.count);
    _suggestions = suggestions;
    _shown = DPPaletteAddSuggestions(_matches, suggestions);
    for (DPPaletteRow *row in _shown) if (!row.image) [_layout drawRow:row query:_query appearance:_panel.effectiveAppearance];
    _layout.rows = _shown;
    NSUInteger now = [_shown indexOfObjectPassingTest:^BOOL(DPPaletteRow *row, NSUInteger i, BOOL *stop) {
        return row == active || (row.kind == active.kind && [row.title isEqualToString:active.title]);
    }];
    double shift = (now == NSNotFound ? MIN(was, (NSInteger)_shown.count - 1) : (NSInteger)now) - lround(_target);
    _target += shift;
    _position += shift;
    [self showCompletion];
}

- (void)showCompletion {
    NSString *typed = _field.stringValue;
    DPPaletteRow *row = self.activeRow;
    _completion = nil;
    // The result in front first, so a site you know beats Google's guess.
    for (NSString *candidate in [@[row.searchText ?: @"", row.title ?: @""] arrayByAddingObjectsFromArray:_suggestions ?: @[]]) {
        if (!typed.length || [candidate rangeOfString:typed options:NSCaseInsensitiveSearch | NSAnchoredSearch].location == NSNotFound) continue;
        _completion = candidate;
        break;
    }
    // The wheel has no chip for the result in front, so the bar names it even when it doesn't start with what's typed.
    BOOL wheel = _layout.barStyle.labelWidth > 0;
    NSString *rest = _completion ? [_completion substringFromIndex:typed.length] : wheel && row && typed.length ? [@"  —  " stringByAppendingString:row.title] : nil;
    // Hebrew and Arabic keep to the bar's right end, so the rest of the word has room to grow leftwards. The ghost is
    // told the same direction, or a guess starting with a letter the typing lacks could turn it the other way.
    _rightToLeft = DPPaletteIsRightToLeft(typed);
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = _rightToLeft ? NSTextAlignmentRight : NSTextAlignmentLeft;
    paragraph.baseWritingDirection = _rightToLeft ? NSWritingDirectionRightToLeft : NSWritingDirectionLeftToRight;
    // Only the field editor while typing: changing the field's own alignment ends editing, and every key after it is lost.
    NSText *editor = _field.currentEditor;
    if (editor) editor.alignment = paragraph.alignment;
    else _field.alignment = paragraph.alignment;
    NSMutableAttributedString *ghost = [NSMutableAttributedString new];
    if (rest) {
        [ghost appendAttributedString:[[NSAttributedString alloc] initWithString:typed attributes:@{NSFontAttributeName: _ghost.font, NSForegroundColorAttributeName: NSColor.clearColor, NSParagraphStyleAttributeName: paragraph}]];
        // Darker on the wheel, where the bar is the only place the result in front is named.
        NSColor *color = wheel ? DPPaletteSoftTextColor() : DPPaletteFaintTextColor();
        [ghost appendAttributedString:[[NSAttributedString alloc] initWithString:rest attributes:@{NSFontAttributeName: _ghost.font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: paragraph}]];
    }
    _ghost.attributedStringValue = ghost;
    _label.stringValue = row.tag ?: @"Search";
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
    NSInteger moon = [_layout moonAt:point], steps = [_layout stepsToResultAt:point];
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

- (NSRect)pillGoal { return [_layout barIn:_panel.frame.size results:_shown.count > 0 inMoons:_moonFocus >= 0]; }

- (void)layoutPanel {
    NSSize size = _panel.frame.size;
    _backdrop.alphaValue = _reveal;
    _backdrop.hidden = !_reveal;
    DPPaletteBarStyle style = _layout.barStyle;
    BOOL wheel = style.labelWidth > 0;
    _pill.frame = NSMakeRect(_pillRect.origin.x, size.height - NSMaxY(_pillRect), _pillRect.size.width, _pillRect.size.height);
    CGFloat width = _pillRect.size.width, height = style.height, fieldHeight = _field.intrinsicContentSize.height;
    // Faded, not hidden: a hidden field would lose the keyboard, and every key after → with it.
    NSRect text = NSMakeRect(style.textLeft, floor((height - fieldHeight) / 2), MAX(width - style.textLeft - style.textRight, 40), fieldHeight);
    _field.frame = _ghost.frame = text;
    _field.alphaValue = _ghost.alphaValue = style.keepsText ? 1 - .4 * _focus : MAX(0, 1 - _focus * 2);
    _label.frame = NSMakeRect(16, NSMinY(text), style.labelWidth, fieldHeight);
    _icon.frame = NSMakeRect(16 + 3.5 * _focus, (height - 19) / 2, 19, 19);
    _pill.alphaValue = 1 - .4 * _focus;
    _shortcut.stringValue = wheel && _shown.count ? @"↵" : @"⌘T";
    _shortcut.hidden = !wheel && _shown.count > 0;
    [_shortcut sizeToFit];
    _shortcut.frame = NSMakeRect(width - NSWidth(_shortcut.frame) - 16, floor((height - NSHeight(_shortcut.frame)) / 2), NSWidth(_shortcut.frame), NSHeight(_shortcut.frame));
    [_hint sizeToFit];
    _hint.frame = NSMakeRect(floor((size.width - NSWidth(_hint.frame)) / 2), NSMaxY(_pill.frame) + style.hintRise - height / 2, NSWidth(_hint.frame), NSHeight(_hint.frame));
    [_layout layoutInSize:size motion:(DPOrbitMotion){_position, _reveal, _moonReveal, _focus, _moonFocus, _rightToLeft}];
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
    if (count && count < _layout.loopsFrom) _target = MAX(0, MIN(count - 1, _target));
    CGFloat position = _position;
    DPEase(&position, _target, DPSpinRate, seconds, instant);
    _position = position;
    DPPaletteRow *row = self.activeRow;
    if (row != _layout.moonRow && row.moons.count) DPPaletteDrawMoons(row, _panel.effectiveAppearance, _layout.scale);
    if (row != _layout.moonRow && !_moonReveal) _layout.moonRow = row;
    DPEase(&_reveal, count ? 1 : 0, DPRevealRate, seconds, instant);
    DPEase(&_moonReveal, _moonsOpen && row == _layout.moonRow && fabs(_target - _position) < .03 ? 1 : 0, DPSpinRate, seconds, instant);
    DPEase(&_focus, _moonFocus >= 0 ? 1 : 0, DPFocusRate, seconds, instant);
    NSRect goal = [self pillGoal];
    CGFloat x = _pillRect.origin.x, y = _pillRect.origin.y, width = _pillRect.size.width;
    DPEase(&x, goal.origin.x, DPRevealRate, seconds, instant);
    DPEase(&y, goal.origin.y, DPRevealRate, seconds, instant);
    DPEase(&width, goal.size.width, DPRevealRate, seconds, instant);
    _pillRect = NSMakeRect(x, y, width, _layout.barStyle.height);
    [self layoutPanel];
}

- (void)press:(SEL)command {
    NSTextView *editor = (NSTextView *)_field.currentEditor;
    if (editor && ![self control:_field textView:editor doCommandBySelector:command]) [editor doCommandBySelector:command];
}

- (NSDictionary *)debugState {
    DPPaletteRow *row = self.activeRow;
    return @{@"open": @(self.isOpen), @"query": _field.stringValue, @"count": @(_shown.count), @"active": row.title ?: @"",
             @"moonsOpen": @(_moonsOpen), @"moonReveal": @(_moonReveal), @"focus": @(_focus), @"moon": _moonFocus >= 0 ? row.moons[_moonFocus].title : @"",
             @"keyboard": @(_field.currentEditor != nil), @"completion": _completion ?: @"", @"suggestions": _suggestions ?: @[], @"pillWidth": @(_pillRect.size.width)};
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

void DPPalettePress(SEL command) { if (DPController().isOpen) [DPController() press:command]; }

void DPPaletteOpen(NSWindow *parent, NSString *text) {
    if (DPController().isOpen) return;
    [DPController() showOver:parent];
    [DPController() fill:text];
}

void DPPaletteToggle(NSWindow *parent) {
    if (DPController().isOpen) [DPController() dismissToParent];
    else [DPController() showOver:parent];
}
