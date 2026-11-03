#import "CommandPalette.h"

extern DPPatch DPCommandPalette;

static NSWindow *DPBrowserWindowFor(NSWindow *window) {
    if (![window isKindOfClass:NSPanel.class] && DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaContentPane); })) return window;
    return window.parentWindow && DPPaletteIsOpen() ? window.parentWindow : nil;
}

// characters, not charactersIgnoringModifiers: with ⌘ held, layouts such as Hebrew give the Latin letter.
BOOL DPIsCommand(NSEvent *event, NSString *characters) {
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

// Sent through AppKit as a real key would be, past Dia's menus and the keyboard layout.
static void DPSendKey(NSString *characters, NSEventModifierFlags flags, unsigned short code) {
    [NSApp sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:NSApp.keyWindow.windowNumber
                                       context:nil characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:code]];
}

// With the developer tools on, a script can drive it: com.diapatches.dev.palette, object "open:" and the text to search,
// "type:" and text to type, "down", "up", "right", "left", "clear" (⌘⌫) or "close".
static void DPListenForScripts(void) {
    if (![[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] boolForKey:@"devTools"]) return;
    NSDictionary<NSString *, NSString *> *keys = @{@"down": @"moveDown:", @"up": @"moveUp:", @"right": @"moveRight:", @"left": @"moveLeft:"};
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:@"com.diapatches.dev.palette" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        NSString *command = [note.object isKindOfClass:NSString.class] ? note.object : @"";
        NSWindow *window = DPBrowserWindowFor(NSApp.mainWindow);
        if ([command hasPrefix:@"open:"] && window) {
            DPPaletteHide();
            DPPaletteOpen(window, [command substringFromIndex:5]);
        } else if ([command hasPrefix:@"type:"]) {
            NSString *text = [command substringFromIndex:5];
            [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *key, NSRange range, NSRange enclosing, BOOL *stop) { DPSendKey(key, 0, 0); }];
        } else if ([command isEqual:@"clear"]) DPSendKey(@"\x7f", NSEventModifierFlagCommand, 51);
        else if ([command isEqual:@"close"]) DPPaletteHide();
        else if (keys[command]) DPPalettePress(NSSelectorFromString(keys[command]));
    }];
}

static void DPInstallCommandPalette(void) {
    DPListenForScripts();
    DPOnLaunch(^{ [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { return DPHandleKey(event); }]; });
}

static void DPApplyCommandPalette(DPPatch *patch) {
    if (!patch->on) DPPaletteHide();
}

// Reserved names: the filter searches real history, where a visited address gets no typed row.
static NSString *DPCheckTypedAddress(void) {
    DPPaletteRow *site = DPPaletteMakeRow(DPPaletteKindTab, @"Known site", @"known-site.example", @"", nil);
    site.searchText = @"known-site.example/";
    if (DPPaletteFilter(@[site], @"known-site.exampl").firstObject != site) return @"part of a known address opened as its own";
    if (![DPPaletteFilter(@[site], @"new-site.example").firstObject.title isEqualToString:@"Open new-site.example"]) return @"a new address wasn't offered first";
    return nil;
}

static NSString *DPVerifyCommandPalette(DPPatch *patch) {
    NSString *problem = DPPaletteCheckMatching() ?: DPCheckTypedAddress() ?: DPPaletteCheckSuggestions() ?: DPWheelCheck();
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
    .detail = @"Open a search bar with ⌘T. Your tabs, history and Dia’s commands orbit it as you type, or roll past it on a wheel, and → shows what you can do with each one. History is read on your Mac and stays there; what you type goes to Google for search suggestions.",
    .symbol = @"command",
    .tint = @"systemPurpleColor",
    .section = @"Window",
    .choiceTitle = @"Style",
    .choices = DPClasses("Orbit", "Wheel"),
    .classes = DPClasses("DiaAppleScriptTab", DPDiaContentPane),
    .install = DPInstallCommandPalette,
    .apply = DPApplyCommandPalette,
    .verify = DPVerifyCommandPalette,
};
