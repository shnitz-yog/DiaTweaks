// The notch over one window: its hover zone, its clicks, and the layers that move when it opens. Everything sits on one
// centre line, so the address stays put and what's left of it mirrors what's right of it.
#import "PinnedNotch.h"
#import "Patches/CommandPalette/CommandPalette.h"

static const NSTimeInterval DPOpenDelay = .06, DPCloseDelay = .28, DPMoonStagger = .038, DPFadeIn = .18, DPFadeOut = .1, DPFadeDelay = .1, DPToolsSettle = .4;
static const CGFloat DPIdleHeight = 34, DPOpenHeight = 46, DPIdlePadding = 20, DPCapsuleHeight = 36, DPCapsuleRadius = 12;
static const CGFloat DPIcon = 18, DPSlot = 30, DPSlotGap = 4, DPCapsuleInset = 3, DPTool = 36, DPToolGap = 2, DPToolsGap = 8, DPToolGroupGap = 6;
static const CGFloat DPMinZoneWidth = 640, DPZoneHeight = 140, DPZoneMargin = 48, DPMoonGap = 12, DPMoonRise = 12, DPMoonLift = 14, DPMoonTilt = 3.5 * M_PI / 180;

static void DPWithoutAnimation(void (^changes)(void)) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    changes();
    [CATransaction commit];
}

// Waits for the notch to grow, so nothing shows on the page beside it.
static void DPFade(CALayer *layer, float opacity, BOOL animated) {
    float from = layer.presentationLayer ? layer.presentationLayer.opacity : layer.opacity;
    DPWithoutAnimation(^{ layer.opacity = opacity; });
    if (!animated) return;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @(from);
    fade.toValue = @(opacity);
    fade.duration = opacity ? DPFadeIn : DPFadeOut;
    fade.fillMode = kCAFillModeBackwards;
    if (opacity) fade.beginTime = CACurrentMediaTime() + DPFadeDelay;
    [layer addAnimation:fade forKey:@"opacity"];
}

@implementation DPNotchView {
    CAShapeLayer *_hole;
    CALayer *_capsule, *_icon, *_domain;
    NSArray<DPNotchTool *> *_tools;  // Their rects are laid out by -arrangeToolsAtY:.
    DPNotchTool *_search, *_hotTool;
    NSArray<CALayer *> *_moons;
    NSArray<DPNotchPin *> *_pins;
    NSArray<NSValue *> *_moonRects, *_moonGoals;  // Rects are points from the view's top left.
    NSTrackingArea *_tracking;
    CGFloat _textWidth, _gap, _pageCenter, _moonsWidth;  // _gap: from the page's bottom edge down to the window's.
    NSInteger _hot;
    BOOL _open, _inside, _corner;
}

- (instancetype)initWithPage:(NSView *)page {
    self = [super initWithFrame:NSZeroRect];
    _page = page;
    _hot = -1;
    self.layer = [CALayer layer];
    self.wantsLayer = YES;
    _capsule = [CALayer layer];
    _capsule.cornerRadius = DPCapsuleRadius;
    _capsule.opacity = 0;
    _icon = [CALayer layer];
    _icon.opacity = 0;
    _domain = [CALayer layer];
    _search = [DPNotchTool new];
    _search.symbol = @"magnifyingglass";
    _search.enabled = YES;
    _tools = DPNotchMakeTools();
    for (CALayer *layer in @[_capsule, _icon, _domain]) [self.layer addSublayer:layer];
    for (DPNotchTool *tool in [_tools arrayByAddingObject:_search]) {
        tool.layer = [CALayer layer];
        tool.layer.opacity = 0;
        [self.layer addSublayer:tool.layer];
    }
    _hole = [CAShapeLayer layer];
    _hole.fillRule = kCAFillRuleEvenOdd;
    page.layer.mask = _hole;
    [page.superview addSubview:self];
    return self;
}

- (void)detach {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (_page.layer.mask == _hole) _page.layer.mask = nil;
    [self removeFromSuperview];
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

#pragma mark Placing

- (void)place {
    NSView *page = _page, *parent = self.superview;
    if (!page || !parent) return;
    if (parent.subviews.lastObject != self) [parent addSubview:self positioned:NSWindowAbove relativeTo:nil];
    if (self.layer.contentsAreFlipped) self.layer.geometryFlipped = !self.layer.geometryFlipped;  // Laid out from the bottom left, whatever Dia's parent does.
    BOOL corner = DPPatchChoice(&DPPinnedNotch) == DPNotchPlacementCorner;
    NSRect pageFrame = [parent convertRect:page.bounds fromView:page];
    CGFloat width = MAX(DPMinZoneWidth, _moonsWidth + DPZoneMargin), center = NSMidX(parent.bounds), height = NSHeight(parent.bounds);
    NSRect frame = NSMakeRect(corner ? NSMinX(pageFrame) : round(center - width / 2), parent.isFlipped ? height - DPZoneHeight : 0, width, DPZoneHeight);
    CGFloat gap = parent.isFlipped ? height - NSMaxY(pageFrame) : NSMinY(pageFrame), pageCenter = center - NSMinX(pageFrame);
    if (corner == _corner && NSEqualRects(self.frame, frame) && gap == _gap && pageCenter == _pageCenter && NSEqualRects(_hole.frame, page.layer.bounds)) return;
    if (corner != _corner) {  // The two shapes can't animate into each other.
        _corner = corner;
        _open = _inside = NO;
        [_hole removeAllAnimations];
        for (CALayer *moon in _moons) [moon removeFromSuperlayer];
        _moons = nil;
        _moonRects = nil;
    }
    self.frame = frame;
    _gap = gap;
    _pageCenter = pageCenter;
    [self arrange:NO];
}

- (CGFloat)capsuleWidth { return _textWidth + 2 * (DPSlot + DPSlotGap + DPCapsuleInset); }
- (CGFloat)toolsWidth { return (_tools.count / 2) * (DPTool + DPToolGap) - DPToolGap; }

// The domain's centre, which never moves: in the corner everything else grows to the right of it.
- (CGFloat)addressX { return _corner ? self.openMargin + self.capsuleWidth / 2 : NSMidX(self.bounds); }

// The same margin on every side of what's inside, the window's own edge included.
- (CGFloat)openMargin { return (_gap + DPOpenHeight - DPCapsuleHeight) / 2; }

- (CGFloat)holeWidth {
    if (_corner && !_open) return self.addressX + _textWidth / 2 + DPIdlePadding;
    if (_corner) return self.openMargin * 2 + self.capsuleWidth + DPToolsGap + self.toolsWidth * 2 + DPToolGap + DPToolGroupGap;
    if (!_open) return _textWidth + DPIdlePadding * 2;
    return self.capsuleWidth + 2 * (self.toolsWidth + DPToolsGap + self.openMargin);
}

- (void)arrangeToolsAtY:(CGFloat)y {
    NSUInteger half = _tools.count / 2;
    CGFloat center = self.addressX, height = NSHeight(self.bounds), capsule = self.capsuleWidth / 2, step = DPTool + DPToolGap, right = center + capsule + DPToolsGap;
    [_tools enumerateObjectsUsingBlock:^(DPNotchTool *tool, NSUInteger i, BOOL *stop) {
        CGFloat x = self->_corner ? right + DPTool / 2 + i * step + (i < half ? 0 : DPToolGroupGap)
                  : i < half      ? center - capsule - DPToolsGap - self.toolsWidth + DPTool / 2 + i * step
                                  : right + DPTool / 2 + (i - half) * step;
        tool.rect = NSMakeRect(x - DPTool / 2, height - y - DPTool / 2, DPTool, DPTool);
    }];
    CGFloat x = center + _textWidth / 2 + DPSlotGap + DPSlot / 2;
    _search.rect = NSMakeRect(x - DPSlot / 2, height - y - DPSlot / 2, DPSlot, DPSlot);
    for (DPNotchTool *tool in [_tools arrayByAddingObject:_search]) {
        tool.layer.position = CGPointMake(NSMidX(tool.rect), y);
        tool.layer.bounds = (CGRect){CGPointZero, tool.rect.size};
    }
}

- (void)arrange:(BOOL)animated {
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) animated = NO;
    NSView *page = _page;
    CGFloat height = _open ? DPOpenHeight : DPIdleHeight, center = self.addressX, y = (_gap + height) / 2, pageHeight = NSHeight(page.bounds);
    BOOL topDown = page.layer.contentsAreFlipped;
    CGPathRef path = _corner ? DPNotchCreateCornerHole(self.holeWidth, height, pageHeight, topDown) : DPNotchCreateHole(_pageCenter, self.holeWidth, height, pageHeight, topDown);
    id from = (__bridge id)(((CAShapeLayer *)_hole.presentationLayer).path ?: _hole.path);
    DPWithoutAnimation(^{
        self->_hole.frame = page.layer.bounds;
        self->_hole.path = path;
        [self arrangeToolsAtY:(self->_gap + DPOpenHeight) / 2];
    });
    if (animated) DPNotchSpring(_hole, @"path", from, (__bridge id)path, 0);
    CGPathRelease(path);
    void (^move)(void) = ^{
        CGFloat half = self->_textWidth / 2;
        self->_domain.position = CGPointMake(center, y);
        self->_icon.position = CGPointMake(center - half - DPSlotGap - DPSlot / 2, y);
        self->_capsule.position = CGPointMake(center, y);
        self->_capsule.bounds = CGRectMake(0, 0, self.capsuleWidth, DPCapsuleHeight);
    };
    animated ? move() : DPWithoutAnimation(move);
    DPFade(_capsule, _open, animated);
    DPFade(_icon, _open || _corner, animated);  // There's room for it in the corner.
    for (DPNotchTool *tool in [_tools arrayByAddingObject:_search]) DPFade(tool.layer, _open, animated);
}

- (void)paintTools {
    NSAppearance *appearance = self.effectiveAppearance;
    CGFloat scale = self.window.backingScaleFactor ?: 2;
    for (DPNotchTool *tool in [_tools arrayByAddingObject:_search]) {
        DPNotchDrawTool(tool, appearance, scale);
        DPWithoutAnimation(^{ DPSetContents(tool.layer, tool == self->_hotTool ? tool.litImage : tool.image, tool.rect.size, scale); });
    }
}

- (void)paint {
    if (!_shown) return;
    NSAppearance *appearance = self.effectiveAppearance;
    CGFloat scale = self.window.backingScaleFactor ?: 2;
    NSSize text, icon = NSMakeSize(DPIcon, DPIcon);
    id image = DPNotchDrawText(_shown, appearance, scale, &text);
    _textWidth = text.width;
    DPWithoutAnimation(^{
        DPSetContents(self->_domain, image, text, scale);
        DPSetContents(self->_icon, DPNotchDrawIcon(self->_shown, appearance, scale, icon), icon, scale);
        [appearance performAsCurrentDrawingAppearance:^{ self->_capsule.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:.1].CGColor; }];
        [self arrangeToolsAtY:(self->_gap + DPOpenHeight) / 2];
    });
    [self paintTools];
}

- (void)refresh {
    NSString *domain = DPNotchDomain(DPNotchAddress(), DPNotchTitle());
    if ([domain isEqualToString:_shown]) return;
    _shown = domain;
    [self paint];
    [self arrange:_hole.path != nil];
    if (_open) [self performSelector:@selector(refreshTools) withObject:nil afterDelay:DPToolsSettle];
}

- (void)refreshTools {
    DPNotchRefreshTools(_tools);
    [self paintTools];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self paint];
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [self paint];
}

#pragma mark Moons

- (void)loadMoons {
    for (CALayer *moon in _moons) [moon removeFromSuperlayer];
    NSAppearance *appearance = self.effectiveAppearance;
    CGFloat scale = self.window.backingScaleFactor ?: 2;
    _pins = DPNotchPins();
    _hot = -1;
    _moonsWidth = -DPMoonGap;
    for (DPNotchPin *pin in _pins) {
        DPNotchDrawPin(pin, appearance, scale);
        _moonsWidth += pin.size.width + DPMoonGap;
    }
    [self place];
    NSMutableArray<CALayer *> *moons = [NSMutableArray new];
    NSMutableArray<NSValue *> *rects = [NSMutableArray new], *goals = [NSMutableArray new];
    CGFloat center = self.addressX, left = _corner ? self.openMargin - center : -_moonsWidth / 2, height = NSHeight(self.bounds), hub = _gap + DPIdleHeight;
    double middle = (_pins.count - 1) / 2.0;
    for (NSUInteger i = 0; i < _pins.count; i++) {
        DPNotchPin *pin = _pins[i];
        // By place in the row, not by distance: moons of different widths still pair up at the same height.
        // In the corner they curve away from it: highest by the page's edge, lowest at the far end.
        CGFloat offset = left + pin.size.width / 2, k = !middle ? 0 : _corner ? i / (middle * 2) : (i - middle) / middle;
        CGFloat y = _gap + DPOpenHeight + DPMoonRise + DPNotchMoonHeight / 2 + DPMoonLift * (1 - k * k);
        CALayer *moon = [CALayer layer];
        DPWithoutAnimation(^{
            DPSetContents(moon, pin.image, pin.size, scale);
            DPAddShadow(moon, 9);
            DPSetShadowShape(moon, pin.size, DPNotchMoonHeight / 2);
            moon.position = CGPointMake(center, hub);
            moon.opacity = 0;
            moon.transform = CATransform3DMakeScale(.6, .6, 1);
        });
        [self.layer insertSublayer:moon atIndex:0];
        [moons addObject:moon];
        [rects addObject:[NSValue valueWithRect:NSMakeRect(center + offset - pin.size.width / 2, height - y - DPNotchMoonHeight / 2, pin.size.width, DPNotchMoonHeight)]];
        [goals addObject:[NSValue valueWithCATransform3D:CATransform3DRotate(CATransform3DMakeTranslation(offset, y - hub, 0), -k * DPMoonTilt, 0, 0, 1)]];
        left += pin.size.width + DPMoonGap;
    }
    _moons = moons;
    _moonRects = rects;
    _moonGoals = goals;
}

- (void)moveMoons {
    double middle = (_moons.count - 1) / 2.0;
    [_moons enumerateObjectsUsingBlock:^(CALayer *moon, NSUInteger i, BOOL *stop) {
        CATransform3D goal = self->_open ? self->_moonGoals[i].CATransform3DValue : CATransform3DMakeScale(.6, .6, 1);
        NSValue *from = [moon.presentationLayer valueForKeyPath:@"transform"] ?: [NSValue valueWithCATransform3D:moon.transform];
        NSNumber *opacity = @(moon.presentationLayer.opacity);
        DPWithoutAnimation(^{
            moon.transform = goal;
            moon.opacity = self->_open;
        });
        CFTimeInterval delay = self->_open ? fabs(i - middle) * DPMoonStagger : 0;
        DPNotchSpring(moon, @"transform", from, [NSValue valueWithCATransform3D:goal], delay);
        DPNotchSpring(moon, @"opacity", opacity, @(self->_open), delay);
    }];
}

- (void)setHot:(NSInteger)hot {
    if (hot == _hot) return;
    DPWithoutAnimation(^{
        if (self->_hot >= 0) self->_moons[self->_hot].contents = self->_pins[self->_hot].image;
        if (hot >= 0) self->_moons[hot].contents = self->_pins[hot].litImage;
    });
    _hot = hot;
}

- (void)setHotTool:(DPNotchTool *)tool {
    if (tool == _hotTool) return;
    DPWithoutAnimation(^{
        self->_hotTool.layer.contents = self->_hotTool.image;
        tool.layer.contents = tool.litImage;
    });
    _hotTool = tool;
}

#pragma mark Pointer

- (void)setOpen:(BOOL)open {
    if (_open == open) return;
    _open = open;
    if (open) {
        [self loadMoons];
        [self refreshTools];
    }
    [self arrange:YES];
    [self moveMoons];
}

- (NSRect)hoverZone {
    if (_open) return self.bounds;
    CGFloat width = self.holeWidth + (_corner ? 4 : 8), height = _gap + DPIdleHeight + 4;
    return NSMakeRect(_corner ? 0 : NSMidX(self.bounds) - width / 2, NSHeight(self.bounds) - height, width, height);
}

- (NSRect)capsuleRect {
    CGFloat y = NSHeight(self.bounds) - (_gap + DPOpenHeight) / 2;
    return NSMakeRect(self.addressX - self.capsuleWidth / 2, y - DPCapsuleHeight / 2, self.capsuleWidth, DPCapsuleHeight);
}

- (NSView *)hitTest:(NSPoint)point {
    return NSPointInRect([self convertPoint:point fromView:self.superview], self.hoverZone) ? self : nil;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (void)settleHover { [self setOpen:_inside]; }

- (void)pointerInside:(BOOL)inside {
    if (inside == _inside) return;
    _inside = inside;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(settleHover) object:nil];
    [self performSelector:@selector(settleHover) withObject:nil afterDelay:inside ? DPOpenDelay : DPCloseDelay];
}

- (NSInteger)moonAt:(NSPoint)point {
    if (!_open) return -1;
    for (NSUInteger i = 0; i < _moonRects.count; i++) if (NSPointInRect(point, _moonRects[i].rectValue)) return i;
    return -1;
}

- (DPNotchTool *)toolAt:(NSPoint)point {
    if (!_open) return nil;
    for (DPNotchTool *tool in [_tools arrayByAddingObject:_search]) if (NSPointInRect(point, tool.rect)) return tool;
    return nil;
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self pointerInside:NSPointInRect(point, self.hoverZone)];
    [self setHot:[self moonAt:point]];
    [self setHotTool:[self toolAt:point]];
}

- (void)mouseExited:(NSEvent *)event {
    [self pointerInside:NO];
    [self setHot:-1];
    [self setHotTool:nil];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger moon = [self moonAt:point];
    DPNotchTool *tool = [self toolAt:point];
    if (moon >= 0) [self openPin:_pins[moon]];
    else if (tool == _search) [self openPalette:@""];
    else if (tool) [self runTool:tool];
    else if (!_open || NSPointInRect(point, self.capsuleRect)) [self openPalette:DPNotchAddress()];
}

- (void)runTool:(DPNotchTool *)tool {
    if (!tool.enabled) return;
    if (tool.isMenu) {
        NSMenu *menu = [NSApp.mainMenu itemWithTitle:tool.title].submenu;
        [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(tool.rect), NSMinY(tool.rect) - menu.size.height - 8) inView:self];
    } else DPNotchRunTool(tool);
    [self performSelector:@selector(refreshTools) withObject:nil afterDelay:DPToolsSettle];
}

- (void)openPin:(DPNotchPin *)pin {
    pin.open();
    for (DPNotchPin *each in _pins) each.active = each == pin;
    NSInteger hot = _hot;
    [self setHot:-1];
    [_pins enumerateObjectsUsingBlock:^(DPNotchPin *each, NSUInteger i, BOOL *stop) {
        DPNotchDrawPin(each, self.effectiveAppearance, self.window.backingScaleFactor);
        DPWithoutAnimation(^{ self->_moons[i].contents = each.image; });
    }];
    [self setHot:hot];
    [self performSelector:@selector(refresh) withObject:nil afterDelay:.1];
}

- (void)openPalette:(NSString *)text {
    _inside = NO;
    [self setOpen:NO];
    DPPaletteOpen(self.window, text);
}

- (NSDictionary *)debugState {
    NSMutableArray<NSString *> *names = [NSMutableArray new], *active = [NSMutableArray new], *rects = [NSMutableArray new], *tools = [NSMutableArray new], *enabled = [NSMutableArray new];
    for (DPNotchPin *pin in _pins) {
        [names addObject:pin.name];
        if (pin.active) [active addObject:pin.name];
    }
    NSString *(^window)(NSRect) = ^NSString *(NSRect rect) { return NSStringFromRect([self convertRect:rect toView:nil]); };
    for (NSValue *rect in _moonRects) [rects addObject:window(rect.rectValue)];
    for (DPNotchTool *tool in _tools) {
        [tools addObject:window(tool.rect)];
        if (tool.enabled) [enabled addObject:tool.title];
    }
    return @{@"open": @(_open), @"shown": _shown ?: @"", @"pins": names, @"active": active, @"hot": @(_hot), @"moons": rects,
             @"tools": tools, @"enabled": enabled, @"hotTool": _hotTool.title ?: @"", @"capsule": window(self.capsuleRect), @"holeWidth": @(self.holeWidth), @"margin": @(self.openMargin),
             @"domain": NSStringFromPoint([self convertPoint:NSMakePoint(self.addressX, NSHeight(self.bounds) - (_gap + DPIdleHeight) / 2) toView:nil]),
             @"corner": @(_corner),
             @"search": window(_search.rect), @"flipped": @(_page.layer.contentsAreFlipped), @"frame": NSStringFromRect(self.frame)};
}
@end
