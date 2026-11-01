// The toolbar's jobs, for once it's hidden. Each runs Dia's own menu item, so it can do just what Dia allows on this page.
#import "PinnedNotch.h"
#import "Patches/CommandPalette/CommandPalette.h"

@implementation DPNotchTool
@end

static DPNotchTool *DPTool(NSString *symbol, NSString *title, BOOL isMenu) {
    DPNotchTool *tool = [DPNotchTool new];
    tool.symbol = symbol;
    tool.title = title;
    tool.isMenu = isMenu;
    return tool;
}

NSArray<DPNotchTool *> *DPNotchMakeTools(void) {
    return @[
        DPTool(@"chevron.left", @"Go Back", NO),
        DPTool(@"chevron.right", @"Go Forward", NO),
        DPTool(@"arrow.clockwise", @"Refresh", NO),
        DPTool(@"puzzlepiece.extension", @"Extensions", YES),
        DPTool(@"bookmark", @"Add to Bookmarks…", NO),
        DPTool(@"square.and.arrow.up", @"Share…", NO),
    ];
}

void DPNotchRefreshTools(NSArray<DPNotchTool *> *tools) {
    for (DPNotchTool *tool in tools) {
        NSMenuItem *item = tool.isMenu ? [NSApp.mainMenu itemWithTitle:tool.title] : DPPaletteMenuItem(tool.title);
        // Dia fills some menus just before they open.
        if ([item.menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [item.menu.delegate menuNeedsUpdate:item.menu];
        [item.menu update];
        tool.enabled = item.isEnabled;
    }
}

void DPNotchRunTool(DPNotchTool *tool) { DPPaletteRunMenuItem(tool.title); }
