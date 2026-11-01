// The notch is a real hole in the page's mask, so Dia's window shows through it in any theme, with no colour to match.
#import "PinnedNotch.h"

static const CGFloat DPShoulder = 14, DPCorner = 20, DPArc = .5523;  // DPArc: the Bézier handle of a quarter circle.
static const CGFloat DPFar = 12000, DPBelow = 60;  // DPFar: past any window, so a resize can't outrun the mask.

// Points up from the page's bottom edge, centred on `center`. Masks don't get geometry flipped for them, hence topDown.
CGPathRef DPNotchCreateHole(CGFloat center, CGFloat width, CGFloat height, CGFloat pageHeight, BOOL topDown) {
    const CGFloat left = center - width / 2, right = center + width / 2, s = DPShoulder, r = DPCorner, k = s * DPArc, c = r * DPArc;
    CGAffineTransform t = topDown ? CGAffineTransformMake(1, 0, 0, -1, 0, pageHeight) : CGAffineTransformIdentity;
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, &t, CGRectMake(-DPFar, -DPFar, DPFar * 2, DPFar * 2));
    CGPathMoveToPoint(path, &t, left - s, -DPBelow);
    CGPathAddLineToPoint(path, &t, left - s, 0);
    CGPathAddCurveToPoint(path, &t, left - s + k, 0, left, s - k, left, s);
    CGPathAddLineToPoint(path, &t, left, height - r);
    CGPathAddCurveToPoint(path, &t, left, height - r + c, left + r - c, height, left + r, height);
    CGPathAddLineToPoint(path, &t, right - r, height);
    CGPathAddCurveToPoint(path, &t, right - r + c, height, right, height - r + c, right, height - r);
    CGPathAddLineToPoint(path, &t, right, s);
    CGPathAddCurveToPoint(path, &t, right, s - k, right + s - k, 0, right + s, 0);
    CGPathAddLineToPoint(path, &t, right + s, -DPBelow);
    CGPathCloseSubpath(path);
    return path;
}

// The page's left edge and bottom edge both curve into the hole, so the sidebar's colour flows into it.
CGPathRef DPNotchCreateCornerHole(CGFloat width, CGFloat height, CGFloat pageHeight, BOOL topDown) {
    const CGFloat s = DPShoulder, r = DPCorner, k = s * DPArc, c = r * DPArc;
    CGAffineTransform t = topDown ? CGAffineTransformMake(1, 0, 0, -1, 0, pageHeight) : CGAffineTransformIdentity;
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, &t, CGRectMake(-DPFar, -DPFar, DPFar * 2, DPFar * 2));
    CGPathMoveToPoint(path, &t, -DPBelow, -DPBelow);
    CGPathAddLineToPoint(path, &t, width + s, -DPBelow);
    CGPathAddLineToPoint(path, &t, width + s, 0);
    CGPathAddCurveToPoint(path, &t, width + s - k, 0, width, s - k, width, s);
    CGPathAddLineToPoint(path, &t, width, height - r);
    CGPathAddCurveToPoint(path, &t, width, height - r + c, width - r + c, height, width - r, height);
    CGPathAddLineToPoint(path, &t, s, height);
    CGPathAddCurveToPoint(path, &t, s - k, height, 0, height + s - k, 0, height + s);
    CGPathAddLineToPoint(path, &t, -DPBelow, height + s);
    CGPathCloseSubpath(path);
    return path;
}

void DPNotchSpring(CALayer *layer, NSString *keyPath, id from, id to, CFTimeInterval delay) {
    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) return;
    CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:keyPath];
    spring.stiffness = 300;
    spring.damping = 24;
    spring.fromValue = from;
    spring.toValue = to;
    spring.duration = spring.settlingDuration;
    spring.fillMode = kCAFillModeBackwards;
    if (delay) spring.beginTime = CACurrentMediaTime() + delay;
    [layer addAnimation:spring forKey:keyPath];
}
