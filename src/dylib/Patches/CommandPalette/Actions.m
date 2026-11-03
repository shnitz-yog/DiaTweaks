// What each result can do: its moons, the first of which Enter runs.
#import "CommandPalette.h"
#import "Commands/GroupTabs/GroupTabs.h"

static const NSUInteger DPMaxTabsText = 1500;
static const NSTimeInterval DPNewWindowDelay = .3;

// The way a link from another app opens: a new tab in the front window.
void DPPaletteOpenURL(NSURL *url) {
    [NSWorkspace.sharedWorkspace openURLs:@[url] withApplicationAtURL:NSBundle.mainBundle.bundleURL
                            configuration:NSWorkspaceOpenConfiguration.configuration completionHandler:nil];
}

static NSURL *DPWebURL(NSString *address, NSString *name, NSString *value, NSString *extraName, NSString *extraValue) {
    NSURLComponents *components = [NSURLComponents componentsWithString:address];
    NSMutableArray *items = [NSMutableArray arrayWithObject:[NSURLQueryItem queryItemWithName:name value:value]];
    if (extraName) [items addObject:[NSURLQueryItem queryItemWithName:extraName value:extraValue]];
    components.queryItems = items;
    components.percentEncodedQuery = [components.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];  // Or "c++" reads as "c  ".
    return components.URL;
}

static void DPAskClaude(NSString *text) { DPPaletteOpenURL(DPWebURL(@"https://claude.ai/new", @"q", text, nil, nil)); }

static DPPaletteRow *DPMoon(DPPaletteKind kind, NSString *title, void (^action)(void)) {
    return DPPaletteMakeRow(kind, title, @"", @"", action);
}

// Runs a command from Dia's scripting dictionary, with the command object its method expects.
static void DPScript(id tab, NSString *name, FourCharCode suite, FourCharCode code) {
    NSScriptCommandDescription *description = [NSScriptSuiteRegistry.sharedScriptSuiteRegistry commandDescriptionWithAppleEventClass:suite andAppleEventCode:code];
    NSScriptCommand *command = description.createCommandInstance;
    SEL selector = NSSelectorFromString(name);
    if (!command || ![tab respondsToSelector:selector]) return;
    void (*send)(id, SEL, id) = (void *)[tab methodForSelector:selector];
    send(tab, selector, command);
}

static void DPCopy(NSString *text) {
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:text forType:NSPasteboardTypeString];
}

static NSString *DPAboutPage(NSString *title, NSURL *url) {
    return [NSString stringWithFormat:@"%@\n%@", title, url.absoluteString ?: @""];
}

static DPPaletteRow *DPCopyMoon(DPPaletteKind kind, NSURL *url) {
    return DPMoon(kind, @"Copy link", ^{ DPCopy(url.absoluteString); });
}

static DPPaletteRow *DPAskMoon(DPPaletteKind kind, NSString *title, NSURL *url) {
    return DPMoon(kind, @"Ask Claude", ^{ DPAskClaude(DPAboutPage(title, url)); });
}

NSArray<DPPaletteRow *> *DPPaletteTabMoons(id tab, NSString *title, NSURL *url) {
    NSMutableArray *moons = [NSMutableArray arrayWithObjects:
        DPMoon(DPPaletteKindTab, @"Switch to tab", ^{ DPScript(tab, @"focus:", 'DiaT', 'abFc'); }),
        DPMoon(DPPaletteKindTab, @"Close tab", ^{ DPScript(tab, @"close:", 'core', 'clos'); }), nil];
    if (url) [moons addObjectsFromArray:@[DPCopyMoon(DPPaletteKindTab, url), DPAskMoon(DPPaletteKindTab, title, url)]];
    return moons;
}

NSArray<DPPaletteRow *> *DPPaletteSiteMoons(NSURL *url, NSString *title) {
    return @[
        DPMoon(DPPaletteKindSite, @"Open", ^{ DPPaletteOpenURL(url); }),
        DPMoon(DPPaletteKindSite, @"Open in new window", ^{
            DPPaletteRunMenuItem(@"New Window");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(DPNewWindowDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DPPaletteOpenURL(url); });
        }),
        DPCopyMoon(DPPaletteKindSite, url),
        DPAskMoon(DPPaletteKindSite, title, url),
    ];
}

DPPaletteRow *DPPaletteGoogleRow(NSString *query) {
    NSURL *web = DPWebURL(@"https://www.google.com/search", @"q", query, nil, nil);
    NSURL *images = DPWebURL(@"https://www.google.com/search", @"q", query, @"udm", @"2");
    NSURL *news = DPWebURL(@"https://www.google.com/search", @"q", query, @"tbm", @"nws");
    NSURL *maps = DPWebURL(@"https://www.google.com/maps/search/", @"api", @"1", @"query", query);
    DPPaletteRow *row = DPPaletteMakeRow(DPPaletteKindGoogle, [NSString stringWithFormat:@"Search Google for “%@”", query], @"", @"magnifyingglass", nil);
    DPPaletteUseMoons(row, @[
        DPMoon(DPPaletteKindGoogle, @"Search", ^{ DPPaletteOpenURL(web); }),
        DPMoon(DPPaletteKindGoogle, @"Images", ^{ DPPaletteOpenURL(images); }),
        DPMoon(DPPaletteKindGoogle, @"News", ^{ DPPaletteOpenURL(news); }),
        DPMoon(DPPaletteKindGoogle, @"Maps", ^{ DPPaletteOpenURL(maps); }),
    ]);
    return row;
}

static NSString *DPActivePage(void) {
    id app = NSApp.delegate;
    NSArray *windows = [app respondsToSelector:@selector(appleScriptWindows)] ? DPMsg(app, @selector(appleScriptWindows)) : nil;
    id window = [windows isKindOfClass:NSArray.class] ? windows.firstObject : nil;
    id tab = [window respondsToSelector:@selector(activeTab)] ? DPMsg(window, @selector(activeTab)) : nil;
    NSString *address = [tab respondsToSelector:@selector(URL)] ? DPText(DPMsg(tab, @selector(URL))) : nil;
    NSString *title = [tab respondsToSelector:@selector(title)] ? DPText(DPMsg(tab, @selector(title))) : nil;
    return address ? [NSString stringWithFormat:@"%@\n%@", title ?: @"", address] : @"";
}

// shortcut: a query string only holds so much, so long tab lists are cut off; send them another way if that gets in the way.
static NSString *DPOpenTabs(void) {
    NSMutableString *text = [NSMutableString new];
    for (DPPaletteRow *row in DPPaletteTabRows()) {
        if (text.length > DPMaxTabsText) break;
        [text appendFormat:@"%@ (%@)\n", row.title, row.detail];
    }
    return text;
}

DPPaletteRow *DPPaletteClaudeRow(NSString *query) {
    DPPaletteRow *row = DPPaletteMakeRow(DPPaletteKindClaude, [NSString stringWithFormat:@"Ask Claude about “%@”", query], @"", @"sparkle", nil);
    DPPaletteUseMoons(row, @[
        DPMoon(DPPaletteKindClaude, @"Ask", ^{ DPAskClaude(query); }),
        DPMoon(DPPaletteKindClaude, @"About this page", ^{ DPAskClaude([NSString stringWithFormat:@"%@\n\n%@", query, DPActivePage()]); }),
        DPMoon(DPPaletteKindClaude, @"About my tabs", ^{ DPAskClaude([NSString stringWithFormat:@"%@\n\n%@", query, DPOpenTabs()]); }),
    ]);
    return row;
}
