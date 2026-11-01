// What the notch shows: the front window's active tab and pinned tabs, from Dia's scripting objects, and Dia's own favicons.
#import "PinnedNotch.h"
#import "Patches/CommandPalette/CommandPalette.h"
#import "Commands/GroupTabs/GroupTabs.h"
#include <sqlite3.h>

static const NSUInteger DPMaxNameLength = 20;

@implementation DPNotchPin
@end

static id DPFrontWindow(void) {
    id app = NSApp.delegate;
    NSArray *windows = [app respondsToSelector:@selector(appleScriptWindows)] ? DPMsg(app, @selector(appleScriptWindows)) : nil;
    return [windows isKindOfClass:NSArray.class] ? windows.firstObject : nil;
}

static id DPActiveTab(void) {
    id window = DPFrontWindow();
    return [window respondsToSelector:@selector(activeTab)] ? DPMsg(window, @selector(activeTab)) : nil;
}

static NSString *DPTabText(id tab, SEL selector) {
    return [tab respondsToSelector:selector] ? DPText(DPMsg(tab, selector)) ?: @"" : @"";
}

NSString *DPNotchAddress(void) { return DPTabText(DPActiveTab(), @selector(URL)); }
NSString *DPNotchTitle(void) { return DPTabText(DPActiveTab(), @selector(title)); }

NSString *DPNotchDomain(NSString *address, NSString *title) {
    NSURLComponents *parts = [NSURLComponents componentsWithString:address];
    NSString *scheme = parts.scheme.lowercaseString, *host = parts.host;
    if (!host.length || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return title.length ? title : @"Dia";
    return [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
}

// The shortest part of the title that looks like the host: "Feed | LinkedIn" is LinkedIn. Otherwise, the host's longest word.
NSString *DPNotchPinName(NSString *title, NSString *host) {
    NSMutableArray<NSString *> *words = [[host.lowercaseString componentsSeparatedByString:@"."] mutableCopy];
    [words removeLastObject];
    NSString *best, *longest = @"";
    NSRegularExpression *separator = [NSRegularExpression regularExpressionWithPattern:@"\\s[-|–—·:]\\s" options:0 error:nil];
    NSString *parts = [separator stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@"\n"];
    for (NSString *word in words) if (word.length > longest.length) longest = word;
    for (NSString *raw in [parts componentsSeparatedByString:@"\n"]) {
        NSString *part = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet], *lower = part.lowercaseString;
        if (part.length < 3 || part.length > DPMaxNameLength || (best && part.length >= best.length)) continue;
        for (NSString *word in words)
            if (word.length >= 3 && ([lower containsString:word] || [word containsString:lower])) best = part;
    }
    return best ?: longest.capitalizedString;
}

NSArray<DPNotchPin *> *DPNotchPins(void) {
    NSMutableArray<DPNotchPin *> *pins = [NSMutableArray new];
    id window = DPFrontWindow();
    NSArray *tabs = [window respondsToSelector:@selector(appleScriptTabs)] ? DPMsg(window, @selector(appleScriptTabs)) : nil;
    if (![tabs isKindOfClass:NSArray.class]) return pins;
    for (id tab in tabs) {
        if (![[tab valueForKey:@"isPinned"] boolValue]) continue;
        NSString *address = DPTabText(tab, @selector(URL)), *title = DPTabText(tab, @selector(title));
        DPNotchPin *pin = [DPNotchPin new];
        pin.host = DPNotchDomain(address, nil);
        pin.name = DPNotchPinName(title, pin.host);
        pin.active = [[tab valueForKey:@"isFocused"] boolValue];
        pin.open = DPPaletteTabMoons(tab, title, [NSURL URLWithString:address]).firstObject.action;
        [pins addObject:pin];
    }
    return pins;
}

static NSData *DPFaviconIn(NSString *path, NSString *host) {
    NSString *uri = [[NSURL fileURLWithPath:path].absoluteString stringByAppendingString:@"?immutable=1"];
    NSString *pattern = [NSString stringWithFormat:@"%%://%%%@/%%", host];
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;
    NSData *data = nil;
    const char *sql = "SELECT b.image_data FROM favicon_bitmaps b JOIN icon_mapping m ON m.icon_id = b.icon_id "
                      "WHERE m.page_url LIKE ?1 AND length(b.image_data) > 0 ORDER BY b.width DESC LIMIT 1";
    if (sqlite3_open_v2(uri.UTF8String, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL) == SQLITE_OK
        && sqlite3_prepare_v2(database, sql, -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, pattern.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) == SQLITE_ROW) data = [NSData dataWithBytes:sqlite3_column_blob(statement, 0) length:sqlite3_column_bytes(statement, 0)];
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return data;
}

NSImage *DPNotchFavicon(NSString *host) {
    static NSMutableDictionary<NSString *, NSImage *> *cache;
    cache = cache ?: [NSMutableDictionary new];
    if (cache[host]) return cache[host];
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *data = [support stringByAppendingPathComponent:@"Dia/User Data"];
    for (NSString *profile in [NSFileManager.defaultManager contentsOfDirectoryAtPath:data error:nil]) {
        NSString *path = [[data stringByAppendingPathComponent:profile] stringByAppendingPathComponent:@"Favicons"];
        NSData *bytes = [NSFileManager.defaultManager fileExistsAtPath:path] ? DPFaviconIn(path, host) : nil;
        NSImage *image = bytes ? [[NSImage alloc] initWithData:bytes] : nil;
        if (image) return cache[host] = image;
    }
    return nil;
}

NSString *DPNotchCheckNames(void) {
    NSDictionary<NSString *, NSArray<NSString *> *> *cases = @{
        @"LinkedIn": @[@"Feed | LinkedIn", @"linkedin.com"],
        @"Gmail": @[@"Inbox (38) - someone@gmail.com - Gmail", @"mail.google.com"],
        @"ynet": @[@"ynet - חדשות, כלכלה, ספורט ובריאות - דיווחים שוטפים", @"ynet.co.il"],
        @"Munchala": @[@"Munchala", @"munchala.co"],
        @"Threads": @[@"A very long post that goes on and on (@someone) on Threads", @"threads.com"],
    };
    for (NSString *name in cases)
        if (![DPNotchPinName(cases[name][0], cases[name][1]) isEqualToString:name]) return [@"names " stringByAppendingString:name];
    if (![DPNotchDomain(@"https://www.reddit.com/r/macapps/comments/1", @"x") isEqualToString:@"reddit.com"]) return @"domain drops www and path";
    if (![DPNotchDomain(@"dia://new-tab", @"New Tab") isEqualToString:@"New Tab"]) return @"non-web pages show their title";
    return nil;
}
