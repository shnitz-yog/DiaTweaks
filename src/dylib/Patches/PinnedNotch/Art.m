// Draws the notch's domain and the pinned moons into images; NotchView.m only moves them.
#import "PinnedNotch.h"
#import "Patches/CommandPalette/CommandPalette.h"

const CGFloat DPNotchMoonHeight = 40;

static const CGFloat DPMaxTextWidth = 280, DPMoonIcon = 20, DPMoonPadding = 14, DPMoonGap = 8, DPTextSize = 14;

static NSDictionary *DPAttributes(NSFont *font, NSColor *color) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    return @{NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style};
}

id DPNotchDrawText(NSString *text, NSAppearance *appearance, CGFloat scale, NSSize *size) {
    NSDictionary *attributes = DPAttributes([NSFont systemFontOfSize:DPTextSize weight:NSFontWeightMedium], NSColor.labelColor);
    NSSize natural = [text sizeWithAttributes:attributes], drawn = NSMakeSize(MIN(ceil(natural.width), DPMaxTextWidth), ceil(natural.height));
    *size = drawn;
    return DPImage(drawn, appearance, scale, ^{ [text drawInRect:(NSRect){NSZeroPoint, drawn} withAttributes:attributes]; });
}

void DPNotchDrawSymbol(NSString *name, CGFloat points, NSColor *color, NSRect rect) {
    NSImageSymbolConfiguration *size = [NSImageSymbolConfiguration configurationWithPointSize:points weight:NSFontWeightMedium];
    NSImageSymbolConfiguration *tint = [NSImageSymbolConfiguration configurationWithPaletteColors:@[color]];
    NSImage *image = [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] imageWithSymbolConfiguration:[size configurationByApplyingConfiguration:tint]];
    [image drawInRect:NSMakeRect(NSMidX(rect) - image.size.width / 2, NSMidY(rect) - image.size.height / 2, image.size.width, image.size.height)];
}

void DPNotchDrawFavicon(NSImage *favicon, NSRect rect, CGFloat radius) {
    if (!favicon) return DPNotchDrawSymbol(@"globe", NSHeight(rect) - 3, NSColor.secondaryLabelColor, rect);
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] addClip];
    [favicon drawInRect:rect];
    [NSGraphicsContext restoreGraphicsState];
}

id DPNotchDrawIcon(NSString *host, NSAppearance *appearance, CGFloat scale, NSSize size) {
    NSImage *favicon = DPNotchFavicon(host);
    return DPImage(size, appearance, scale, ^{ DPNotchDrawFavicon(favicon, (NSRect){NSZeroPoint, size}, 3); });
}

static void DPDrawTool(DPNotchTool *tool, NSSize size, BOOL lit) {
    NSRect rect = {NSZeroPoint, size};
    if (lit && tool.enabled) {
        [[NSColor.labelColor colorWithAlphaComponent:.12] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:10 yRadius:10] fill];
    }
    NSColor *color = !tool.enabled ? NSColor.tertiaryLabelColor : lit ? NSColor.labelColor : NSColor.secondaryLabelColor;
    DPNotchDrawSymbol(tool.symbol, 15, color, rect);
}

void DPNotchDrawTool(DPNotchTool *tool, NSAppearance *appearance, CGFloat scale) {
    NSSize size = tool.rect.size;
    tool.image = DPImage(size, appearance, scale, ^{ DPDrawTool(tool, size, NO); });
    tool.litImage = DPImage(size, appearance, scale, ^{ DPDrawTool(tool, size, YES); });
}

static void DPDrawMoon(DPNotchPin *pin, NSImage *favicon, NSSize size, BOOL strong) {
    NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect((NSRect){NSZeroPoint, size}, 1, 1) xRadius:size.height / 2 - 1 yRadius:size.height / 2 - 1];
    [DPPaletteSurfaceColor() setFill];
    [edge fill];
    [strong ? NSColor.secondaryLabelColor : DPPaletteLineColor() setStroke];
    edge.lineWidth = strong ? 1.5 : 1;
    [edge stroke];
    NSFont *font = pin.active ? [NSFont systemFontOfSize:DPTextSize weight:NSFontWeightSemibold] : [NSFont systemFontOfSize:DPTextSize];
    NSDictionary *attributes = DPAttributes(font, strong ? NSColor.labelColor : NSColor.secondaryLabelColor);
    NSSize text = [pin.name sizeWithAttributes:attributes];
    // Centred: the width is the bold name's, so a moon doesn't change size when its tab becomes active.
    CGFloat left = round((size.width - DPMoonIcon - DPMoonGap - ceil(text.width)) / 2), textLeft = left + DPMoonIcon + DPMoonGap;
    DPNotchDrawFavicon(favicon, NSMakeRect(left, (size.height - DPMoonIcon) / 2, DPMoonIcon, DPMoonIcon), 5);
    [pin.name drawInRect:NSMakeRect(textLeft, floor((size.height - ceil(text.height)) / 2), ceil(text.width) + 1, ceil(text.height)) withAttributes:attributes];
}

void DPNotchDrawPin(DPNotchPin *pin, NSAppearance *appearance, CGFloat scale) {
    NSFont *bold = [NSFont systemFontOfSize:DPTextSize weight:NSFontWeightSemibold];
    NSSize size = NSMakeSize(DPMoonPadding * 2 + DPMoonIcon + DPMoonGap + ceil([pin.name sizeWithAttributes:@{NSFontAttributeName: bold}].width), DPNotchMoonHeight);
    NSImage *favicon = DPNotchFavicon(pin.host);
    pin.size = size;
    pin.image = DPImage(size, appearance, scale, ^{ DPDrawMoon(pin, favicon, size, pin.active); });
    pin.litImage = DPImage(size, appearance, scale, ^{ DPDrawMoon(pin, favicon, size, YES); });
}
