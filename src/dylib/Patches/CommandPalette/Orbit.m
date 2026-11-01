// Places the results on their curve and the moons beside the active one. Everything here is a layer, moved each frame.
#import "CommandPalette.h"

enum { DPSlots = 5, DPMaxMoons = 4 };  // DPSlots: results drawn either side of the active one.

const NSInteger DPOrbitLoopsFrom = 4;  // Fewer results than this don't repeat.

static const CGFloat DPContentWidth = 770, DPHubOffset = 76, DPRadius = 372, DPStepDegrees = 8.4, DPTilt = .4, DPPivotX = 22;
static const CGFloat DPMaxShift = 250, DPMinChipLeft = 80;
static const CGFloat DPMoonRadius = 170, DPMoonFocusGap = 20, DPMoonSpacing = 48, DPMoonTilt = .25, DPBackgroundBlur = 4.5;

static CGFloat DPClamp(CGFloat value, CGFloat low, CGFloat high) { return MAX(low, MIN(high, value)); }
static NSInteger DPWrap(NSInteger value, NSInteger count) { return ((value % count) + count) % count; }

DPOrbitFit DPOrbitFitIn(NSSize size) {
    CGFloat left = MAX(16, floor((size.width - DPContentWidth) / 2)), chipLeft = left - DPHubOffset + DPRadius - DPPivotX;
    return (DPOrbitFit){left, left - DPHubOffset, floor(size.height / 2), MIN(DPMaxShift, MAX(0, chipLeft - DPMinChipLeft)), chipLeft};
}

void DPSetContents(CALayer *layer, id image, NSSize size, CGFloat scale) {
    layer.contents = image;
    layer.contentsScale = scale;
    layer.bounds = (CGRect){CGPointZero, size};
}

void DPSetShadowShape(CALayer *layer, NSSize size, CGFloat radius) {
    CGPathRef shape = CGPathCreateWithRoundedRect((CGRect){CGPointZero, size}, radius, radius, NULL);
    layer.shadowPath = shape;
    CGPathRelease(shape);
}

void DPAddShadow(CALayer *layer, CGFloat radius) {
    layer.shadowColor = NSColor.blackColor.CGColor;
    layer.shadowOpacity = .22;
    layer.shadowRadius = radius;
    layer.shadowOffset = CGSizeMake(0, -6);
}

static void DPSetBlur(CALayer *layer, CGFloat radius, CGFloat scale) {
    if (radius < .05) {
        if (layer.filters) layer.filters = nil;
        return;
    }
    if (!layer.filters) {
        CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
        blur.name = @"blur";
        layer.filters = @[blur];
    }
    [layer setValue:@(radius * scale) forKeyPath:@"filters.blur.inputRadius"];
}

@implementation DPOrbit {
    NSView *_view;
    CALayer *_root, *_scrim, *_stage;
    NSMutableArray<CALayer *> *_chips, *_actives, *_moons;
    NSInteger _shown[DPSlots * 2 + 1];
    CGFloat _offsets[DPSlots * 2 + 1];
}

- (instancetype)init {
    self = [super init];
    _root = [CALayer layer];
    _scrim = [CALayer layer];
    _stage = [CALayer layer];
    [_root addSublayer:_scrim];
    [_root addSublayer:_stage];
    _view = [NSView new];
    _view.layer = _root;
    _view.wantsLayer = YES;
    _view.layerUsesCoreImageFilters = YES;
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _chips = [NSMutableArray new];
    _actives = [NSMutableArray new];
    _moons = [NSMutableArray new];
    for (int i = 0; i < DPSlots * 2 + 1; i++) {
        CALayer *chip = [CALayer layer], *active = [CALayer layer];
        DPAddShadow(chip, 7);
        chip.opacity = 0;
        [chip addSublayer:active];
        [_stage addSublayer:chip];
        [_chips addObject:chip];
        [_actives addObject:active];
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

- (void)setScrimColor:(NSColor *)color appearance:(NSAppearance *)appearance {
    [appearance performAsCurrentDrawingAppearance:^{ self->_scrim.backgroundColor = color.CGColor; }];
}

- (void)setRows:(NSArray<DPPaletteRow *> *)rows {
    _rows = [rows copy];
    for (int i = 0; i < DPSlots * 2 + 1; i++) _shown[i] = -1;
}

- (void)place:(CALayer *)chip active:(CALayer *)active row:(DPPaletteRow *)row {
    DPSetContents(chip, row.image, row.imageSize, _scale);
    chip.anchorPoint = CGPointMake(DPPivotX / row.imageSize.width, .5);
    DPSetShadowShape(chip, row.imageSize, 15);
    DPSetContents(active, row.activeImage, row.activeImageSize, _scale);
    active.anchorPoint = CGPointZero;
    active.position = CGPointMake(-DPPaletteChipMargin, -DPPaletteChipMargin);
}

- (void)layoutChipsIn:(NSSize)size fit:(DPOrbitFit)fit motion:(DPOrbitMotion)motion {
    NSInteger count = _rows.count, base = lround(motion.position);
    BOOL loops = count >= DPOrbitLoopsFrom;
    CGFloat fraction = motion.position - base;
    for (NSInteger slot = -DPSlots; slot <= DPSlots; slot++) {
        NSInteger i = slot + DPSlots, raw = base + slot;
        CALayer *chip = _chips[i], *active = _actives[i];
        if (!count || (!loops && (raw < 0 || raw >= count))) {
            chip.opacity = 0;
            _shown[i] = -1;
            continue;
        }
        NSInteger index = loops ? DPWrap(raw, count) : raw;
        if (_shown[i] != index) [self place:chip active:active row:_rows[index]];
        _shown[i] = index;
        CGFloat offset = slot - fraction, away = fabs(offset), emphasis = MAX(0, 1 - away * 1.6);
        CGFloat reveal = DPClamp(motion.reveal * 1.5 - labs(slot) * .1, 0, 1), degrees = offset * DPStepDegrees * reveal, angle = degrees * M_PI / 180;
        CGFloat scale = (1 - MIN(away, DPSlots) * .018) * (.9 + .1 * reveal) + .03 * emphasis;
        CGFloat background = away > .5 ? motion.focus : 0;
        CATransform3D transform = CATransform3DMakeRotation(-degrees * DPTilt * M_PI / 180, 0, 0, 1);
        chip.position = CGPointMake(fit.hubX + DPRadius * cos(angle), size.height - (fit.hubY + DPRadius * sin(angle)));
        chip.transform = CATransform3DScale(transform, scale, scale, 1);
        chip.opacity = MAX(0, (1 - pow(MIN(away, DPSlots) / DPSlots, 1.4)) * (reveal * 1.2 - .2) * (1 - .72 * background));
        chip.zPosition = 20 - away * 2;
        active.opacity = emphasis;
        DPSetBlur(chip, MAX(0, away - 2.2) * .7 + DPBackgroundBlur * background, _scale);
        _offsets[i] = offset;
    }
}

- (void)layoutMoonsIn:(NSSize)size fit:(DPOrbitFit)fit motion:(DPOrbitMotion)motion {
    NSArray<DPPaletteRow *> *moons = _moonRow.moons;
    NSInteger count = MIN((NSInteger)moons.count, DPMaxMoons);
    CGFloat chipEnd = fit.chipLeft + _moonRow.activeImageSize.width - DPPaletteChipMargin * 2;
    CGFloat center = DPClamp(chipEnd, fit.left + 504, fit.left + 704) + 40 + DPMoonFocusGap * motion.focus - DPMoonRadius;
    CGFloat radius = DPMoonRadius * (.55 + .45 * motion.moonReveal);
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
        // A tighter curve than the results': a few moons on the results' own curve would look like a straight line.
        CGFloat angle = (i - (count - 1) / 2.0) * DPMoonSpacing / DPMoonRadius * motion.moonReveal, scale = 1 + .14 * motion.focus;
        layer.position = CGPointMake(center + radius * cos(angle) - 10, size.height - (fit.hubY + radius * sin(angle)));
        layer.transform = CATransform3DScale(CATransform3DMakeRotation(-angle * DPMoonTilt, 0, 0, 1), scale, scale, 1);
        layer.opacity = DPClamp(motion.moonReveal * 1.6 - i * .14, 0, 1);
        layer.zPosition = 30;
    }
}

- (void)layoutInSize:(NSSize)size motion:(DPOrbitMotion)motion {
    DPOrbitFit fit = DPOrbitFitIn(size);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scrim.frame = _root.bounds;
    _scrim.opacity = motion.reveal;
    // bounds and position, not frame: setting a frame under a transform quietly undoes the transform.
    _stage.bounds = _root.bounds;
    _stage.position = CGPointMake(NSMidX(_root.bounds), NSMidY(_root.bounds));
    _stage.transform = CATransform3DMakeTranslation(-fit.shift * motion.focus, 0, 0);
    [self layoutChipsIn:size fit:fit motion:motion];
    [self layoutMoonsIn:size fit:fit motion:motion];
    [CATransaction commit];
}

- (CALayer *)layerAt:(NSPoint)point among:(NSArray<CALayer *> *)layers {
    for (CALayer *hit = [_root hitTest:point]; hit; hit = hit.superlayer)
        if ([layers containsObject:hit]) return hit.opacity > .1 ? hit : nil;
    return nil;
}

- (NSInteger)stepsToResultAt:(NSPoint)point {
    CALayer *chip = [self layerAt:point among:_chips];
    return chip ? lround(_offsets[[_chips indexOfObject:chip]]) : NSNotFound;
}

- (NSInteger)moonAt:(NSPoint)point {
    CALayer *moon = [self layerAt:point among:_moons];
    return moon ? (NSInteger)[_moons indexOfObject:moon] : -1;
}
@end
