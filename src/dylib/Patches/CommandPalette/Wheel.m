// The wheel: results roll past the search bar on a drum. The active one is in the bar itself, the rest tilt away above
// and below it, and its actions line up under the bar. Like the orbit, everything is a layer, moved each frame.
#import "CommandPalette.h"

enum { DPSlots = 5, DPMaxMoons = 4 };  // DPSlots: results drawn either side of the active one.

static const CGFloat DPBarHeight = 60, DPBarMaxWidth = 760, DPBarMargin = 40, DPInset = 18, DPLabelWidth = 124, DPLabelGap = 12, DPTextRight = 44;
static const CGFloat DPRowSpacing = 52, DPStepDegrees = 16, DPMaxDegrees = 80, DPTiltDegrees = 10, DPPerspective = 900;
static const CGFloat DPMoonDrop = 14, DPMoonGap = 8, DPBackgroundBlur = 4.5;

static CGFloat DPClamp(CGFloat value, CGFloat low, CGFloat high) { return MAX(low, MIN(high, value)); }

// A result `offset` steps from the active one: where it is round the drum, how far below the bar's middle that puts it,
// and how far it tilts. The tilt is gentler than the drum's turn, so the text stays easy to read.
static CGFloat DPRowAngle(CGFloat offset) { return DPClamp(offset * DPStepDegrees, -DPMaxDegrees, DPMaxDegrees) * M_PI / 180; }
static CGFloat DPRowY(CGFloat offset) { return DPRowSpacing / sin(DPStepDegrees * M_PI / 180) * sin(DPRowAngle(offset)); }
static CGFloat DPRowTilt(CGFloat offset) { return DPClamp(offset * DPTiltDegrees, -60, 60) * M_PI / 180; }

// The active result is already in the bar, so its line fades out as it rolls in. The next one each way stays solid.
static CGFloat DPRowOpacity(CGFloat offset) {
    CGFloat away = fabs(offset);
    return DPClamp(away * 2.5 - .25, 0, 1) * DPClamp(1.22 - .22 * away, 0, 1) * DPClamp(DPSlots - away, 0, 1);
}

NSString *DPWheelCheck(void) {
    if (DPRowOpacity(0) > 0) return @"the active result shows twice";
    for (CGFloat offset = -DPSlots; offset < DPSlots; offset += .25)
        if (DPRowY(offset + .25) <= DPRowY(offset)) return @"results out of order";
    if (DPRowY(1) - 14 < DPBarHeight / 2) return @"the next result overlaps the bar";
    if (DPRowOpacity(1) < 1 || DPRowOpacity(-1) < 1) return @"the results beside the bar are faded";
    return nil;
}

@implementation DPWheel {
    NSView *_view;
    CALayer *_root, *_scrim, *_stage;
    CAGradientLayer *_glow;
    NSMutableArray<CALayer *> *_lines, *_moons;
    NSInteger _shown[DPSlots * 2 + 1];
    CGFloat _offsets[DPSlots * 2 + 1];
}
@synthesize view = _view, rows = _rows, moonRow = _moonRow, scale = _scale;

- (instancetype)init {
    self = [super init];
    _root = [CALayer layer];
    _scrim = [CALayer layer];
    _glow = [CAGradientLayer layer];
    _glow.type = kCAGradientLayerRadial;
    _glow.startPoint = CGPointMake(.5, .5);
    _glow.endPoint = CGPointMake(1, 1);
    _stage = [CALayer layer];
    CATransform3D perspective = CATransform3DIdentity;
    perspective.m34 = -1 / DPPerspective;
    _stage.sublayerTransform = perspective;
    for (CALayer *layer in @[_scrim, _glow, _stage]) [_root addSublayer:layer];
    _view = [NSView new];
    _view.layer = _root;
    _view.wantsLayer = YES;
    _view.layerUsesCoreImageFilters = YES;
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _lines = [NSMutableArray new];
    _moons = [NSMutableArray new];
    for (int i = 0; i < DPSlots * 2 + 1; i++) {
        CALayer *line = [CALayer layer];
        line.anchorPoint = CGPointMake(0, .5);
        line.opacity = 0;
        [_stage addSublayer:line];
        [_lines addObject:line];
        _shown[i] = -1;
    }
    for (int i = 0; i < DPMaxMoons; i++) {
        CALayer *moon = [CALayer layer];
        DPAddShadow(moon, 7);
        moon.anchorPoint = CGPointMake(0, .5);
        moon.opacity = 0;
        [_stage addSublayer:moon];
        [_moons addObject:moon];
    }
    return self;
}

- (NSInteger)loopsFrom { return NSIntegerMax; }  // A list that starts again at the top would read as a mistake.
// The keys are listed above the drum's top, clear of the results.
- (DPPaletteBarStyle)barStyle {
    return (DPPaletteBarStyle){DPBarHeight, 18, 24, DPInset + DPLabelWidth + DPLabelGap, DPTextRight, DPLabelWidth, DPRowY(DPSlots) + 20, YES};
}

- (void)drawRow:(DPPaletteRow *)row query:(NSString *)query appearance:(NSAppearance *)appearance {
    DPPaletteDrawLine(row, appearance, _scale);
}

- (NSRect)barIn:(NSSize)size results:(BOOL)results inMoons:(BOOL)inMoons {
    CGFloat width = MIN(DPBarMaxWidth, size.width - DPBarMargin * 2);
    return NSMakeRect(floor((size.width - width) / 2), floor(size.height * .46 - DPBarHeight / 2), width, DPBarHeight);
}

- (void)setScrimColor:(NSColor *)color appearance:(NSAppearance *)appearance {
    BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    NSColor *glow = [NSColor colorWithSRGBRed:.43 green:.36 blue:1 alpha:dark ? .2 : .12];
    [appearance performAsCurrentDrawingAppearance:^{ self->_scrim.backgroundColor = color.CGColor; }];
    _glow.colors = @[(id)glow.CGColor, (id)[glow colorWithAlphaComponent:0].CGColor];
}

- (void)setRows:(NSArray<DPPaletteRow *> *)rows {
    _rows = [rows copy];
    for (int i = 0; i < DPSlots * 2 + 1; i++) _shown[i] = -1;
}

- (void)layoutLinesIn:(NSSize)size bar:(NSRect)bar motion:(DPOrbitMotion)motion {
    NSInteger count = _rows.count, base = lround(motion.position);
    // Lined up with the text in the bar: its left end, or its right end for Hebrew and Arabic.
    CGFloat fraction = motion.position - base, middle = NSMidY(bar);
    CGFloat edge = motion.rightToLeft ? NSMaxX(bar) - DPTextRight - 2 : NSMinX(bar) + self.barStyle.textLeft + 2;
    CGFloat drop = motion.moonReveal * (DPPaletteMoonHeight + DPMoonDrop);  // Results below make room for the actions.
    for (NSInteger slot = -DPSlots; slot <= DPSlots; slot++) {
        NSInteger i = slot + DPSlots, index = base + slot;
        CALayer *line = _lines[i];
        if (index < 0 || index >= count) {
            line.opacity = 0;
            _shown[i] = -1;
            continue;
        }
        DPPaletteRow *row = _rows[index];
        if (_shown[i] != index) DPSetContents(line, row.image, row.imageSize, _scale);
        _shown[i] = index;
        CGFloat offset = slot - fraction, away = fabs(offset), scale = 1 - .05 * MIN(away, DPSlots);
        line.anchorPoint = CGPointMake(motion.rightToLeft, .5);
        line.position = CGPointMake(edge, size.height - (middle + DPRowY(offset) + (offset > 0 ? drop : 0)));
        line.transform = CATransform3DScale(CATransform3DMakeRotation(DPRowTilt(offset), 1, 0, 0), scale, scale, 1);
        line.opacity = DPRowOpacity(offset) * motion.reveal * (1 - .7 * motion.focus);
        DPSetBlur(line, MAX(0, away - 2) * 1.1 + DPBackgroundBlur * motion.focus, _scale);
        _offsets[i] = offset;
    }
}

- (void)layoutMoonsIn:(NSSize)size bar:(NSRect)bar motion:(DPOrbitMotion)motion {
    NSArray<DPPaletteRow *> *moons = _moonRow.moons;
    NSInteger count = MIN((NSInteger)moons.count, DPMaxMoons);
    CGFloat step = motion.rightToLeft ? -1 : 1, x = motion.rightToLeft ? NSMaxX(bar) - DPTextRight : NSMinX(bar) + self.barStyle.textLeft, y = NSMaxY(bar) + DPMoonDrop + DPPaletteMoonHeight / 2 - 8 * (1 - motion.moonReveal);
    for (NSInteger i = 0; i < DPMaxMoons; i++) {
        CALayer *layer = _moons[i];
        if (i >= count) {
            layer.opacity = 0;
            continue;
        }
        DPPaletteRow *moon = moons[i];
        id image = i == motion.moonFocus ? moon.activeImage : moon.image;
        if (layer.contents != image) {
            DPSetContents(layer, image, moon.imageSize, _scale);
            DPSetShadowShape(layer, moon.imageSize, DPPaletteMoonHeight / 2);
        }
        layer.anchorPoint = CGPointMake(motion.rightToLeft, .5);
        layer.position = CGPointMake(x, size.height - y);
        layer.opacity = DPClamp(motion.moonReveal * 1.6 - i * .14, 0, 1);
        x += step * (moon.imageSize.width + DPMoonGap);
    }
}

- (void)layoutInSize:(NSSize)size motion:(DPOrbitMotion)motion {
    NSRect bar = [self barIn:size results:YES inMoons:NO];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scrim.frame = _root.bounds;
    _scrim.opacity = motion.reveal;
    _glow.bounds = CGRectMake(0, 0, NSWidth(bar) * 1.2, 260);
    _glow.position = CGPointMake(NSMidX(bar), size.height - NSMidY(bar));
    // bounds and position, not frame: setting a frame under a transform quietly undoes the transform.
    _stage.bounds = _root.bounds;
    _stage.position = CGPointMake(NSMidX(_root.bounds), NSMidY(_root.bounds));
    [self layoutLinesIn:size bar:bar motion:motion];
    [self layoutMoonsIn:size bar:bar motion:motion];
    [CATransaction commit];
}

- (CALayer *)layerAt:(NSPoint)point among:(NSArray<CALayer *> *)layers {
    for (CALayer *hit = [_root hitTest:point]; hit; hit = hit.superlayer)
        if ([layers containsObject:hit]) return hit.opacity > .1 ? hit : nil;
    return nil;
}

- (NSInteger)stepsToResultAt:(NSPoint)point {
    CALayer *line = [self layerAt:point among:_lines];
    return line ? lround(_offsets[[_lines indexOfObject:line]]) : NSNotFound;
}

- (NSInteger)moonAt:(NSPoint)point {
    CALayer *moon = [self layerAt:point among:_moons];
    return moon ? (NSInteger)[_moons indexOfObject:moon] : -1;
}
@end
