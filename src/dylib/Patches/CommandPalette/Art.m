// Draws each result and action into an image once; Orbit.m only moves the images around.
#import "CommandPalette.h"

const CGFloat DPPaletteChipHeight = 44, DPPaletteChipMargin = 2, DPPaletteMoonHeight = 32;

static const CGFloat DPMoonKeyWidth = 28, DPTileSize = 36, DPTileInset = 4, DPMaxTitleWidth = 250, DPArrowWidth = 24, DPMoonPadding = 13;

typedef enum { DPTintFill, DPTintText, DPTintLine } DPTintRole;

// {fill, text, line} for each DPPaletteKind, as {light, dark}.
static const uint32_t DPTints[5][3][2] = {
    {{0xDDF3EA, 0x123F35}, {0x085041, 0x9FE1CB}, {0x7FD0B3, 0x2A8069}},
    {{0xE1EDFA, 0x143A60}, {0x0C447C, 0xB5D4F4}, {0x9CC4EC, 0x2E6BA6}},
    {{0xFBE7DE, 0x572714}, {0x8A3515, 0xF5C4B3}, {0xF0AC90, 0xA34E2C}},
    {{0xECE9FD, 0x332C73}, {0x3C3489, 0xCECBF6}, {0xBBB5EF, 0x6358C4}},
    {{0xFAEBCD, 0x4F3209}, {0x6A4006, 0xFAC775}, {0xEBC072, 0x96651A}},
};

static NSColor *DPColor(uint32_t light, uint32_t dark) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL isDark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
        uint32_t hex = isDark ? dark : light;
        return [NSColor colorWithSRGBRed:(hex >> 16) / 255.0 green:((hex >> 8) & 255) / 255.0 blue:(hex & 255) / 255.0 alpha:1];
    }];
}

static NSColor *DPTint(DPPaletteKind kind, DPTintRole role) { return DPColor(DPTints[kind][role][0], DPTints[kind][role][1]); }
NSColor *DPPaletteSurfaceColor(void) { return DPColor(0xFFFDFA, 0x2E2E33); }
NSColor *DPPaletteLineColor(void) { return DPColor(0xE8E5DC, 0x45454C); }
NSColor *DPPaletteFaintTextColor(void) { return DPColor(0xA5A29A, 0x75736D); }
static NSColor *DPTextColor(void) { return DPColor(0x2A2926, 0xECEAE4); }
static NSColor *DPSoftTextColor(void) { return DPColor(0x6F6C64, 0xB5B3AC); }
static NSColor *DPTileColor(void) { return DPColor(0xF1EEE7, 0x303036); }
static NSColor *DPMarkColor(void) { return DPColor(0xFAE3A8, 0x6B5417); }
static NSColor *DPActiveLineColor(void) { return DPColor(0xB8B4A8, 0x77777F); }

id DPImage(NSSize size, NSAppearance *appearance, CGFloat scale, void (^draw)(void)) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)ceil(size.width * scale) pixelsHigh:(NSInteger)ceil(size.height * scale)
                                                                    bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    bitmap.size = size;
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [appearance performAsCurrentDrawingAppearance:draw];
    [NSGraphicsContext restoreGraphicsState];
    return (__bridge id)bitmap.CGImage;
}

static NSAttributedString *DPText(NSString *text, NSFont *font, NSColor *color, NSString *match) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:text ?: @""
        attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style}];
    NSRange found = match.length ? [string.string rangeOfString:match options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch] : (NSRange){NSNotFound, 0};
    if (found.location != NSNotFound) [string addAttribute:NSBackgroundColorAttributeName value:DPMarkColor() range:found];
    return string;
}

static void DPDrawText(NSAttributedString *text, CGFloat x, CGFloat width, CGFloat height) {
    CGFloat lineHeight = ceil(text.size.height);
    [text drawInRect:NSMakeRect(x, floor((height - lineHeight) / 2), width, lineHeight)];
}

static void DPFillRound(NSRect rect, CGFloat radius, NSColor *fill, NSColor *line, CGFloat lineWidth) {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    [fill setFill];
    [path fill];
    if (!line) return;
    [line setStroke];
    path.lineWidth = lineWidth;
    [path stroke];
}

static void DPDrawSymbol(NSString *name, NSColor *color, NSRect tile) {
    NSImageSymbolConfiguration *size = [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightMedium];
    NSImageSymbolConfiguration *tint = [NSImageSymbolConfiguration configurationWithPaletteColors:@[color]];
    NSImage *image = [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] imageWithSymbolConfiguration:[size configurationByApplyingConfiguration:tint]];
    [image drawInRect:NSMakeRect(NSMidX(tile) - image.size.width / 2, NSMidY(tile) - image.size.height / 2, image.size.width, image.size.height)];
}

static void DPDrawChip(DPPaletteRow *row, NSString *query, CGFloat width, CGFloat titleWidth, CGFloat tagWidth, BOOL active) {
    const CGFloat height = DPPaletteChipHeight;
    NSColor *ink = active ? DPTextColor() : DPSoftTextColor();  // Only the tag carries colour.
    DPFillRound(NSInsetRect(NSMakeRect(0, 0, width, height), .5, .5), 15, DPPaletteSurfaceColor(), active ? DPActiveLineColor() : DPPaletteLineColor(), active ? 1.5 : 1);
    NSRect tile = NSMakeRect(DPTileInset, DPTileInset, DPTileSize, DPTileSize);
    DPFillRound(tile, 12, DPTileColor(), nil, 0);
    DPDrawSymbol(row.symbol, ink, tile);
    CGFloat x = NSMaxX(tile) + 11;
    NSFont *titleFont = [NSFont systemFontOfSize:14.5], *tagFont = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    DPDrawText(DPText(row.title, titleFont, ink, query), x, titleWidth, height);
    x += titleWidth + 17;
    DPFillRound(NSMakeRect(x, (height - 20) / 2, tagWidth, 20), 10, DPTint(row.kind, DPTintFill), nil, 0);
    DPDrawText(DPText(row.tag, tagFont, DPTint(row.kind, DPTintText), nil), x + 9, tagWidth - 18, height);
    if (!active || !row.moons.count) return;
    x += tagWidth + 13;
    DPFillRound(NSMakeRect(x, (height - 20) / 2, DPArrowWidth, 20), 6, DPTileColor(), DPPaletteLineColor(), 1);
    DPDrawText(DPText(@"→", [NSFont systemFontOfSize:11 weight:NSFontWeightMedium], ink, nil), x + 6, DPArrowWidth - 8, height);
}

void DPPaletteDrawRow(DPPaletteRow *row, NSString *query, NSAppearance *appearance, CGFloat scale) {
    NSFont *titleFont = [NSFont systemFontOfSize:14.5], *tagFont = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    CGFloat titleWidth = MIN(ceil([row.title sizeWithAttributes:@{NSFontAttributeName: titleFont}].width) + 1, DPMaxTitleWidth);
    CGFloat tagWidth = ceil([row.tag sizeWithAttributes:@{NSFontAttributeName: tagFont}].width) + 18;
    CGFloat width = DPTileInset + DPTileSize + 11 + titleWidth + 17 + tagWidth + 12;
    CGFloat activeWidth = width + (row.moons.count ? DPArrowWidth + 13 : 0), margin = DPPaletteChipMargin;
    row.imageSize = NSMakeSize(width, DPPaletteChipHeight);
    row.activeImageSize = NSMakeSize(activeWidth + margin * 2, DPPaletteChipHeight + margin * 2);
    row.image = DPImage(row.imageSize, appearance, scale, ^{ DPDrawChip(row, query, width, titleWidth, tagWidth, NO); });
    row.activeImage = DPImage(row.activeImageSize, appearance, scale, ^{
        NSAffineTransform *inset = [NSAffineTransform transform];
        [inset translateXBy:margin yBy:margin];
        [inset concat];
        DPDrawChip(row, query, activeWidth, titleWidth, tagWidth, YES);
    });
}

void DPPaletteDrawMoons(DPPaletteRow *row, NSAppearance *appearance, CGFloat scale) {
    NSFont *keyFont = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    [row.moons enumerateObjectsUsingBlock:^(DPPaletteRow *moon, NSUInteger index, BOOL *stop) {
        if (moon.image) return;
        NSString *key = [NSString stringWithFormat:@"⌘%lu", (unsigned long)index + 1];
        NSFont *font = [NSFont systemFontOfSize:13], *bold = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        NSSize size = NSMakeSize(ceil([moon.title sizeWithAttributes:@{NSFontAttributeName: bold}].width) + DPMoonPadding * 2 + DPMoonKeyWidth, DPPaletteMoonHeight);
        CGFloat textWidth = size.width - DPMoonPadding * 2 - DPMoonKeyWidth + 2, keyX = size.width - DPMoonPadding - DPMoonKeyWidth + 8;
        NSRect edge = NSInsetRect(NSMakeRect(0, 0, size.width, size.height), 1, 1);
        moon.imageSize = moon.activeImageSize = size;
        moon.image = DPImage(size, appearance, scale, ^{
            DPFillRound(edge, size.height / 2 - 1, DPPaletteSurfaceColor(), DPPaletteLineColor(), 1);
            DPDrawText(DPText(moon.title, font, DPTextColor(), nil), DPMoonPadding, textWidth, size.height);
            DPDrawText(DPText(key, keyFont, DPPaletteFaintTextColor(), nil), keyX, DPMoonKeyWidth, size.height);
        });
        moon.activeImage = DPImage(size, appearance, scale, ^{
            DPFillRound(edge, size.height / 2 - 1, DPTint(moon.kind, DPTintFill), DPTint(moon.kind, DPTintLine), 1.5);
            DPDrawText(DPText(moon.title, bold, DPTint(moon.kind, DPTintText), nil), DPMoonPadding, textWidth, size.height);
            DPDrawText(DPText(key, keyFont, DPTint(moon.kind, DPTintText), nil), keyX, DPMoonKeyWidth, size.height);
        });
    }];
}
