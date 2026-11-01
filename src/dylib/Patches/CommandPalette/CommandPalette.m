#import "CommandPalette.h"

extern DPPatch DPCommandPalette;

static NSWindow *DPBrowserWindowFor(NSWindow *window) {
    if (![window isKindOfClass:NSPanel.class] && DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaContentPane); })) return window;
    return window.parentWindow && DPPaletteIsOpen() ? window.parentWindow : nil;
}

// characters, not charactersIgnoringModifiers: with ⌘ held, layouts such as Hebrew give the Latin letter.
static BOOL DPIsCommand(NSEvent *event, NSString *characters) {
    NSEventModifierFlags flags = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl);
    return flags == NSEventModifierFlagCommand && [event.characters.lowercaseString isEqualToString:characters];
}

// A key monitor, not Dia's New Tab menu item: Dia rebuilds its menus, and a page never sees ⌘T first.
static NSEvent *DPHandleKey(NSEvent *event) {
    // Caught here so Dia's own ⌘1 to ⌘4 don't switch tabs behind the palette.
    for (int i = 0; i < 4 && DPPaletteIsOpen(); i++)
        if (DPIsCommand(event, [NSString stringWithFormat:@"%d", i + 1])) {
            if (!event.isARepeat) DPPaletteRunMoon(i);
            return nil;
        }
    if (!DPCommandPalette.on || !DPIsCommand(event, @"t") || NSApp.modalWindow) return event;
    NSWindow *parent = DPBrowserWindowFor(NSApp.keyWindow);
    if (!parent || !DPPaletteMenuItem(@"New Tab")) return event;
    if (!event.isARepeat) DPPaletteToggle(parent);
    return nil;
}

static void DPInstallCommandPalette(void) {
    DPOnLaunch(^{ [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { return DPHandleKey(event); }]; });
}

static void DPApplyCommandPalette(DPPatch *patch) {
    if (!patch->on) DPPaletteHide();
}

static NSString *DPVerifyCommandPalette(DPPatch *patch) {
    NSString *problem = DPPaletteCheckMatching();
    if (problem) return problem;
    if (!DPPaletteTabRows().count) return @"can't read tabs";
    if (!DPPaletteMenuItem(@"New Tab")) return @"no New Tab menu item";
    if (!DPPaletteHistoryRows(@"a")) return @"can't read history";
    if (!patch->on && DPPaletteIsOpen()) return @"open while off";
    return nil;
}

DP_PATCH(DPCommandPalette) {
    .key = @"commandPalette",
    .defaultOn = YES,
    .order = 100,
    .title = @"Command palette",
    .detail = @"Open a search bar with ⌘T. Your tabs, history and Dia’s commands orbit it as you type, and → shows what you can do with each one. History is read on your Mac and stays there.",
    .symbol = @"command",
    .tint = @"systemPurpleColor",
    .section = @"Window",
    .classes = DPClasses("DiaAppleScriptTab", DPDiaContentPane),
    .install = DPInstallCommandPalette,
    .apply = DPApplyCommandPalette,
    .verify = DPVerifyCommandPalette,
};
