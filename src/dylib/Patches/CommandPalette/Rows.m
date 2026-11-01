#import "CommandPalette.h"
#import "Commands/GroupTabs/GroupTabs.h"

static const NSUInteger DPMaxMatches = 6;  // Google and Claude follow them.
static const NSInteger DPTabBonus = 50;

@implementation DPPaletteRow
@end

static NSString *DPTag(DPPaletteKind kind) {
    switch (kind) {
        case DPPaletteKindTab: return @"Open tab";
        case DPPaletteKindSite: return @"History";
        case DPPaletteKindGoogle: return @"Google";
        case DPPaletteKindClaude: return @"Claude";
        case DPPaletteKindCommand: return @"Command";
    }
}

DPPaletteRow *DPPaletteMakeRow(DPPaletteKind kind, NSString *title, NSString *detail, NSString *symbol, void (^action)(void)) {
    DPPaletteRow *row = [DPPaletteRow new];
    row.kind = kind;
    row.title = title;
    row.detail = detail;
    row.symbol = symbol;
    row.tag = DPTag(kind);
    row.action = action;
    return row;
}

void DPPaletteUseMoons(DPPaletteRow *row, NSArray<DPPaletteRow *> *moons) {
    row.moons = moons;
    row.action = moons.firstObject.action;
}

NSString *DPPaletteBareURL(NSString *url) {
    NSRange scheme = [url rangeOfString:@"://"];
    NSString *bare = scheme.location == NSNotFound ? url : [url substringFromIndex:NSMaxRange(scheme)];
    return [bare hasPrefix:@"www."] ? [bare substringFromIndex:4] : bare;
}

NSArray<DPPaletteRow *> *DPPaletteTabRows(void) {
    NSMutableArray<DPPaletteRow *> *rows = [NSMutableArray new];
    id app = NSApp.delegate;
    if (![app respondsToSelector:@selector(appleScriptWindows)]) return rows;
    NSArray *windows = DPMsg(app, @selector(appleScriptWindows));
    if (![windows isKindOfClass:NSArray.class]) return rows;
    for (id window in windows) {
        NSArray *tabs = [window respondsToSelector:@selector(appleScriptTabs)] ? DPMsg(window, @selector(appleScriptTabs)) : nil;
        if (![tabs isKindOfClass:NSArray.class]) continue;
        for (id tab in tabs) {
            NSString *address = [tab respondsToSelector:@selector(URL)] ? DPText(DPMsg(tab, @selector(URL))) : nil;
            NSString *title = [tab respondsToSelector:@selector(title)] ? DPText(DPMsg(tab, @selector(title))) : nil;
            NSURL *url = address ? [NSURL URLWithString:address] : nil;
            NSString *name = title.length ? title : address ?: @"Tab";
            DPPaletteRow *row = DPPaletteMakeRow(DPPaletteKindTab, name, url.host ?: address ?: @"", @"square.on.square", nil);
            row.searchText = DPPaletteBareURL(address);
            row.bonus = DPTabBonus;
            DPPaletteUseMoons(row, DPPaletteTabMoons(tab, name, url));
            [rows addObject:row];
        }
    }
    return rows;
}

static void DPCollectCommands(NSMenu *menu, NSString *path, NSMutableArray<DPPaletteRow *> *rows) {
    if (menu == NSApp.servicesMenu) return;
    // Dia fills some menus just before they open.
    if ([menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [menu.delegate menuNeedsUpdate:menu];
    [menu update];
    for (NSMenuItem *item in menu.itemArray) {
        if (item.isSeparatorItem || item.isHidden || item.isAlternate || !item.title.length) continue;
        NSString *place = path.length ? [NSString stringWithFormat:@"%@ › %@", path, item.title] : item.title;
        if (item.hasSubmenu) DPCollectCommands(item.submenu, place, rows);
        else if (item.isEnabled)
            [rows addObject:DPPaletteMakeRow(DPPaletteKindCommand, item.title, path, @"command", ^{
                NSInteger index = [item.menu indexOfItem:item];
                if (index >= 0) [item.menu performActionForItemAtIndex:index];
            })];
    }
}

static NSMenuItem *DPFindItem(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title isEqualToString:title] && !item.hasSubmenu) return item;
        NSMenuItem *found = item.hasSubmenu ? DPFindItem(item.submenu, title) : nil;
        if (found) return found;
    }
    return nil;
}

NSMenuItem *DPPaletteMenuItem(NSString *title) { return DPFindItem(NSApp.mainMenu, title); }

void DPPaletteRunMenuItem(NSString *title) {
    NSMenuItem *item = DPPaletteMenuItem(title);
    if (item) [item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]];
}

static void DPCollectTweaks(NSMutableArray<DPPaletteRow *> *rows) {
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i], *required = DPRequired(patch);
        // Not this patch itself: nothing here could turn it back on.
        if (patch->unavailable || (required && !required->on) || [patch->key isEqualToString:@"commandPalette"]) continue;
        NSString *title = [NSString stringWithFormat:@"%@: %@", patch->on ? @"Turn off" : @"Turn on", patch->title];
        DPPaletteRow *row = DPPaletteMakeRow(DPPaletteKindCommand, title, @"Tweak", patch->symbol, ^{
            DPSetPatch(patch, !patch->on, YES);
            [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        });
        row.tag = @"Tweak";
        [rows addObject:row];
    }
}

NSArray<DPPaletteRow *> *DPPaletteSnapshot(void) {
    NSMutableArray<DPPaletteRow *> *rows = [NSMutableArray arrayWithArray:DPPaletteTabRows()];
    DPCollectCommands(NSApp.mainMenu, @"", rows);
    DPCollectTweaks(rows);
    return rows;
}

NSArray<DPPaletteRow *> *DPPaletteFilter(NSArray<DPPaletteRow *> *rows, NSString *query) {
    query = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<DPPaletteRow *> *shown = [NSMutableArray new];
    if (!query.length) return shown;
    NSMutableArray<DPPaletteRow *> *candidates = [NSMutableArray arrayWithArray:rows];
    NSMutableSet<NSString *> *seen = [NSMutableSet new];
    for (DPPaletteRow *row in rows) if (row.searchText) [seen addObject:row.searchText];
    // An open tab already covers its own history, and two profiles can share a page.
    for (DPPaletteRow *row in DPPaletteHistoryRows(query))
        if (![seen containsObject:row.searchText]) {
            [seen addObject:row.searchText];
            [candidates addObject:row];
        }
    // A typed address that's already open or in history is that row, so it switches to the tab rather than opening it twice.
    NSURL *url = DPPaletteURL(query);
    NSString *address = url ? DPPaletteBareURL(url.absoluteString) : nil;
    DPPaletteRow *typed = nil;
    if (address && ![seen containsObject:address] && ![seen containsObject:[address stringByAppendingString:@"/"]]) {
        typed = DPPaletteMakeRow(DPPaletteKindSite, [@"Open " stringByAppendingString:query], url.host ?: @"", @"globe", nil);
        typed.searchText = address;
        DPPaletteUseMoons(typed, DPPaletteSiteMoons(url, query));
    }
    NSMutableArray<DPPaletteRow *> *matches = [NSMutableArray new];
    for (DPPaletteRow *row in candidates) {
        NSInteger score = MAX(MAX(DPPaletteScore(query, row.title), DPPaletteScore(query, row.searchText)), DPPaletteScore(query, row.detail) / 2);
        row.score = score + row.bonus;
        if (score) [matches addObject:row];
    }
    [matches sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(DPPaletteRow *a, DPPaletteRow *b) {
        return a.score == b.score ? NSOrderedSame : a.score > b.score ? NSOrderedAscending : NSOrderedDescending;
    }];
    // github.co on the way to github.com looks like an address, but the site it starts is what's wanted.
    BOOL partial = typed && [matches.firstObject.searchText.lowercaseString hasPrefix:address.lowercaseString];
    if (typed && !partial) [shown addObject:typed];
    [shown addObjectsFromArray:[matches subarrayWithRange:NSMakeRange(0, MIN(matches.count, DPMaxMatches - shown.count))]];
    if (partial) [shown addObject:typed];
    [shown addObject:DPPaletteGoogleRow(query)];
    [shown addObject:DPPaletteClaudeRow(query)];
    return shown;
}
