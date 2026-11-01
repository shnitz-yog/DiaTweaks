// The halo itself: slots 45° apart on a circle, so a few pins sit on one side and a full ring only tightens past eight.
// Search takes the slot nearest straight ahead, where a flick is easiest.
#import "PinHalo.h"
#import "Patches/CommandPalette/CommandPalette.h"
#import "Patches/PinnedNotch/PinnedNotch.h"

static const CGFloat DPRadius = 112, DPTile = 54, DPTileMargin = 3, DPIcon = 26, DPDeadZone = 16, DPEdge = 44, DPLabelGap = 10, DPPickedScale = 1.16;
static const NSTimeInterval DPStagger = .014, DPCloseSeconds = .12;

static double DPStep(NSInteger count) { return MIN(M_PI_4, 2 * M_PI / count); }
static BOOL DPIsFullRing(NSInteger count) { return count * DPStep(count) > 2 * M_PI - .01; }

NSInteger DPHaloPick(CGFloat dx, CGFloat dy, NSInteger count, BOOL mirrored) {
    if (hypot(dx, dy) < DPDeadZone) return -1;
    double step = DPStep(count), angle = atan2(mirrored ? -dx : dx, dy);
    if (angle < 0) angle += 2 * M_PI;
    NSInteger slot = lround(angle / step);
    if (DPIsFullRing(count)) return slot % count;
    return slot < count ? slot : angle > 2 * M_PI - step * .75 ? 0 : -1;  // Just past the ends still counts; behind them cancels.
}

NSString *DPHaloCheckPicks(void) {
    if (DPHaloPick(60, 0, 5, NO) != 2) return @"search isn't straight ahead";
    if (DPHaloPick(0, 60, 5, NO) != 0 || DPHaloPick(0, -60, 5, NO) != 4) return @"ends of the arc";
    if (DPHaloPick(-60, 0, 5, NO) != -1) return @"behind the arc should cancel";
    if (DPHaloPick(3, 3, 5, NO) != -1) return @"dead zone";
    if (DPHaloPick(-60, 0, 5, YES) != 2 || DPHaloPick(60, 0, 5, YES) != -1) return @"mirrored arc";
    if (DPHaloPick(-60, 0, 9, NO) < 0) return @"a full ring has no cancel side";
    return nil;
}

@interface DPHaloSlot : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) void (^run)(void);
@property (nonatomic, strong) id image, litImage, label;
@property (nonatomic) NSSize labelSize;
@property (nonatomic, strong) CALayer *layer;
@property (nonatomic) CGPoint offset;
@end

@implementation DPHaloSlot
@end

static void DPDrawTile(NSImage *favicon, NSSize size, BOOL search, BOOL lit, BOOL active) {
    NSRect rect = NSInsetRect((NSRect){NSZeroPoint, size}, DPTileMargin, DPTileMargin), icon = NSInsetRect(rect, (DPTile - DPIcon) / 2, (DPTile - DPIcon) / 2);
    NSBezierPath *edge = [NSBezierPath bezierPathWithOvalInRect:rect];
    [DPPaletteSurfaceColor() setFill];
    [edge fill];
    [lit ? NSColor.secondaryLabelColor : DPPaletteLineColor() setStroke];
    edge.lineWidth = lit ? 2 : 1;
    [edge stroke];
    if (search) DPNotchDrawSymbol(@"magnifyingglass", 20, NSColor.labelColor, icon);
    else DPNotchDrawFavicon(favicon, icon, 6);
    if (!active) return;
    [NSColor.labelColor setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(rect) - 3, NSMinY(rect) + 4, 6, 6)] fill];
}

static id DPDrawLabel(NSString *text, NSAppearance *appearance, CGFloat scale, NSSize *size) {
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:12.5], NSForegroundColorAttributeName: NSColor.labelColor};
    NSSize fit = [text sizeWithAttributes:attributes], drawn = NSMakeSize(ceil(fit.width) + 20, 24);
    *size = drawn;
    return DPImage(drawn, appearance, scale, ^{
        NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect((NSRect){NSZeroPoint, drawn}, 1, 1) xRadius:9 yRadius:9];
        [DPPaletteSurfaceColor() setFill];
        [edge fill];
        [DPPaletteLineColor() setStroke];
        [edge stroke];
        [text drawAtPoint:NSMakePoint(10, floor((drawn.height - ceil(fit.height)) / 2)) withAttributes:attributes];
    });
}

@implementation DPHaloView {
    NSArray<DPHaloSlot *> *_slots;
    CALayer *_label;
    NSPoint _anchor;
    NSInteger _pick;
    BOOL _mirrored;
}

- (NSView *)hitTest:(NSPoint)point { return nil; }

- (NSArray<DPHaloSlot *> *)makeSlots {
    NSAppearance *appearance = self.effectiveAppearance;
    CGFloat scale = self.window.backingScaleFactor ?: 2;
    NSSize size = NSMakeSize(DPTile + DPTileMargin * 2, DPTile + DPTileMargin * 2);
    NSMutableArray<DPHaloSlot *> *slots = [NSMutableArray new];
    for (DPNotchPin *pin in DPNotchPins()) {
        NSImage *favicon = DPNotchFavicon(pin.host);
        DPHaloSlot *slot = [DPHaloSlot new];
        slot.name = pin.name;
        slot.run = pin.open;
        slot.image = DPImage(size, appearance, scale, ^{ DPDrawTile(favicon, size, NO, NO, pin.active); });
        slot.litImage = DPImage(size, appearance, scale, ^{ DPDrawTile(favicon, size, NO, YES, pin.active); });
        [slots addObject:slot];
    }
    __weak NSWindow *window = self.window;
    DPHaloSlot *search = [DPHaloSlot new];
    search.name = @"Search";
    search.run = ^{ DPPaletteOpen(window, @""); };
    search.image = DPImage(size, appearance, scale, ^{ DPDrawTile(nil, size, YES, NO, NO); });
    search.litImage = DPImage(size, appearance, scale, ^{ DPDrawTile(nil, size, YES, YES, NO); });
    NSInteger count = slots.count + 1;
    [slots insertObject:search atIndex:MIN((NSInteger)slots.count, lround(M_PI_2 / DPStep(count)))];
    return slots;
}

- (instancetype)initInWindow:(NSWindow *)window at:(NSPoint)point {
    NSView *parent = window.contentView;
    self = [super initWithFrame:parent.bounds];
    self.layer = [CALayer layer];
    self.wantsLayer = YES;
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [parent addSubview:self positioned:NSWindowAbove relativeTo:nil];
    if (self.layer.contentsAreFlipped) self.layer.geometryFlipped = !self.layer.geometryFlipped;  // Laid out from the bottom left, whatever Dia's parent does.
    _pick = -1;
    _slots = [self makeSlots];
    [self placeAround:[self convertPoint:point fromView:nil]];
    [self fanOut];
    return self;
}

- (void)placeAround:(NSPoint)point {
    NSSize size = self.bounds.size;
    CGFloat reach = DPRadius + DPEdge;
    BOOL full = DPIsFullRing(_slots.count);
    _mirrored = !full && point.x > size.width - reach;  // Against the right edge, it opens to the left.
    CGFloat low = full || _mirrored ? reach : DPEdge, high = !full && _mirrored ? size.width - DPEdge : size.width - reach;
    _anchor = NSMakePoint(MAX(low, MIN(high, point.x)), MAX(reach, MIN(size.height - reach, point.y)));
}

- (void)fanOut {
    CGFloat scale = self.window.backingScaleFactor ?: 2;
    double step = DPStep(_slots.count);
    [_slots enumerateObjectsUsingBlock:^(DPHaloSlot *slot, NSUInteger i, BOOL *stop) {
        CGFloat angle = i * step, x = DPRadius * sin(angle) * (self->_mirrored ? -1 : 1), y = DPRadius * cos(angle);
        CALayer *layer = [CALayer layer];
        NSSize size = NSMakeSize(DPTile + DPTileMargin * 2, DPTile + DPTileMargin * 2);
        CATransform3D goal = CATransform3DMakeTranslation(x, y, 0), start = CATransform3DMakeScale(.5, .5, 1);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        DPSetContents(layer, slot.image, size, scale);
        DPAddShadow(layer, 9);
        DPSetShadowShape(layer, size, size.width / 2);
        layer.position = self->_anchor;
        layer.transform = goal;
        [self.layer addSublayer:layer];
        [CATransaction commit];
        slot.layer = layer;
        slot.offset = CGPointMake(x, y);
        NSSize labelSize;
        slot.label = DPDrawLabel(slot.name, self.effectiveAppearance, scale, &labelSize);
        slot.labelSize = labelSize;
        DPNotchSpring(layer, @"transform", [NSValue valueWithCATransform3D:start], [NSValue valueWithCATransform3D:goal], i * DPStagger);
        DPNotchSpring(layer, @"opacity", @0, @1, i * DPStagger);
    }];
    _label = [CALayer layer];
    _label.opacity = 0;
    [self.layer addSublayer:_label];
}

- (void)setPick:(NSInteger)pick {
    if (pick == _pick) return;
    CGFloat scale = self.window.backingScaleFactor ?: 2;
    [CATransaction begin];
    [CATransaction setAnimationDuration:.12];
    if (_pick >= 0) {
        _slots[_pick].layer.contents = _slots[_pick].image;
        _slots[_pick].layer.transform = CATransform3DMakeTranslation(_slots[_pick].offset.x, _slots[_pick].offset.y, 0);
    }
    _label.opacity = pick >= 0;
    if (pick >= 0) {
        DPHaloSlot *slot = _slots[pick];
        slot.layer.contents = slot.litImage;
        slot.layer.transform = CATransform3DScale(CATransform3DMakeTranslation(slot.offset.x, slot.offset.y, 0), DPPickedScale, DPPickedScale, 1);
        CGFloat reach = DPTile * DPPickedScale / 2 + DPLabelGap, sideways = fabs(slot.offset.x) > fabs(slot.offset.y);
        CGPoint outward = sideways ? CGPointMake(copysign(reach + slot.labelSize.width / 2, slot.offset.x), 0)
                                   : CGPointMake(0, copysign(reach + slot.labelSize.height / 2, slot.offset.y));
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        DPSetContents(_label, slot.label, slot.labelSize, scale);
        _label.position = CGPointMake(_anchor.x + slot.offset.x + outward.x, _anchor.y + slot.offset.y + outward.y);
        [CATransaction commit];
    }
    [CATransaction commit];
    _pick = pick;
}

- (void)pointerAt:(NSPoint)point {
    NSPoint here = [self convertPoint:point fromView:nil];
    [self setPick:DPHaloPick(here.x - _anchor.x, here.y - _anchor.y, _slots.count, _mirrored)];
}

- (NSString *)picked { return _pick >= 0 ? _slots[_pick].name : nil; }

- (void)close {
    [CATransaction begin];
    [CATransaction setAnimationDuration:DPCloseSeconds];
    for (DPHaloSlot *slot in _slots) slot.layer.opacity = 0;
    _label.opacity = 0;
    [CATransaction setCompletionBlock:^{ [self removeFromSuperview]; }];
    [CATransaction commit];
}

- (void)closeRunningPick {
    void (^run)(void) = _pick >= 0 ? _slots[_pick].run : nil;
    [self close];
    if (run) dispatch_async(dispatch_get_main_queue(), run);
}

- (NSDictionary *)debugState {
    NSMutableArray<NSString *> *names = [NSMutableArray new], *points = [NSMutableArray new];
    for (DPHaloSlot *slot in _slots) {
        [names addObject:slot.name];
        [points addObject:NSStringFromPoint([self convertPoint:NSMakePoint(_anchor.x + slot.offset.x, _anchor.y + slot.offset.y) toView:nil])];
    }
    return @{@"slots": names, @"points": points, @"picked": self.picked ?: @"", @"mirrored": @(_mirrored), @"anchor": NSStringFromPoint([self convertPoint:_anchor toView:nil])};
}
@end
