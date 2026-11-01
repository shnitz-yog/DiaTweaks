#import "CommandPalette.h"

static NSString *DPFold(NSString *text) {
    return [text stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil];
}

static BOOL DPStartsWord(NSString *text, NSUInteger index) {
    return index == 0 || ![NSCharacterSet.alphanumericCharacterSet characterIsMember:[text characterAtIndex:index - 1]];
}

// shortcut: takes the first place each letter fits, not the best one; score every alignment if ranking feels off.
static NSInteger DPSubsequenceScore(NSString *query, NSString *text) {
    NSInteger score = 1;
    NSUInteger at = 0, first = NSNotFound, previous = NSNotFound;
    BOOL acronym = YES;
    for (NSUInteger i = 0; i < query.length; i++) {
        unichar letter = [query characterAtIndex:i];
        while (at < text.length && [text characterAtIndex:at] != letter) at++;
        if (at == text.length) return 0;
        score += 1 + (DPStartsWord(text, at) ? 8 : 0) + (previous != NSNotFound && at == previous + 1 ? 4 : 0);
        if (first == NSNotFound) first = at;
        acronym &= DPStartsWord(text, at);
        previous = at++;
    }
    // Letters scattered across a long title match almost anything, so only initials may spread out.
    return acronym || previous - first < query.length * 2 ? score : 0;
}

NSInteger DPPaletteScore(NSString *query, NSString *text) {
    query = [[DPFold(query) componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""];
    text = DPFold(text ?: @"");
    if (!query.length || !text.length) return 0;
    NSString *compact = [text stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSRange found = [compact rangeOfString:query];
    if (found.location != NSNotFound) {
        // Text left over counts against it, so "Close Tab" beats "Close Tabs to the Right" for "close tab".
        NSInteger leftover = MIN(compact.length - query.length, 100);
        NSInteger start = found.location == 0 ? 500 : DPStartsWord(compact, found.location) ? 300 : 0;
        return 1000 + start - MIN(found.location, 100) - leftover;
    }
    return DPSubsequenceScore(query, text);
}

NSURL *DPPaletteURL(NSString *query) {
    query = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURLComponents *components = [NSURLComponents componentsWithString:query];
    BOOL web = [components.scheme.lowercaseString isEqualToString:@"http"] || [components.scheme.lowercaseString isEqualToString:@"https"];
    if (web) return components.host.length ? components.URL : nil;
    if ([query rangeOfString:@"^localhost(:\\d+)?(/\\S*)?$" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound)
        return [NSURL URLWithString:[@"http://" stringByAppendingString:query]];
    if ([query rangeOfString:@"^[^\\s/:@]+\\.[a-z]{2,}(:\\d+)?(/\\S*)?$" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound)
        return [NSURL URLWithString:[@"https://" stringByAppendingString:query]];
    return nil;
}

NSString *DPPaletteCheckMatching(void) {
    if (DPPaletteScore(@"", @"Close Tab") != 0) return @"an empty search matched";
    if (DPPaletteScore(@"xyz", @"Close Tab") != 0) return @"a wrong search matched";
    if (DPPaletteScore(@"close tab", @"Close Tab") <= DPPaletteScore(@"close tab", @"Close Tabs to the Right")) return @"the closest title lost";
    if (DPPaletteScore(@"tab", @"Tab Groups") <= DPPaletteScore(@"tab", @"Close Tab")) return @"a later match won";
    if (DPPaletteScore(@"ct", @"Close Tab") <= DPPaletteScore(@"ct", @"Duplicate")) return @"word starts didn't count";
    if (!DPPaletteScore(@"CAFE", @"Café")) return @"case or accents mattered";
    if (DPPaletteScore(@"pint", @"Slow play: a pace setting that doubles every board time")) return @"scattered letters matched";
    if (DPPaletteScore(@"pinte", @"pinterest.com/") <= DPPaletteScore(@"pinte", @"pinterest.com/pin/1")) return @"a deep page beat the site";
    if (DPPaletteScore(@"pinte", @"il.pinterest.com/") <= 1000) return @"a subdomain hid the site";
    if (![DPPaletteURL(@"example.com/a").absoluteString isEqualToString:@"https://example.com/a"]) return @"a bare domain wasn't a URL";
    if (![DPPaletteURL(@"localhost:3000").absoluteString isEqualToString:@"http://localhost:3000"]) return @"localhost wasn't a URL";
    if (DPPaletteURL(@"javascript:alert(1)") || DPPaletteURL(@"file:///etc/passwd")) return @"a non-web address counted as a URL";
    if (DPPaletteURL(@"group tabs by domain")) return @"a phrase counted as a URL";
    return nil;
}
