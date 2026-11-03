// Google's guesses for what's being typed, fetched as it's typed, like Google's own search box.
#import "CommandPalette.h"

static const NSUInteger DPMaxSuggestions = 3;
static const NSTimeInterval DPSuggestTimeout = 3;

NSArray<NSString *> *DPPaletteParseSuggestions(NSData *data, NSString *query) {
    id reply = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    // ["query", ["guess", …], …] from the network, so every part is checked.
    if (![reply isKindOfClass:NSArray.class] || [reply count] < 2 || ![reply[1] isKindOfClass:NSArray.class]) return @[];
    NSString *typed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *guesses = [NSMutableArray new];
    for (id guess in reply[1]) {
        if (guesses.count == DPMaxSuggestions) break;
        if ([guess isKindOfClass:NSString.class] && [guess length] && [guess caseInsensitiveCompare:typed] != NSOrderedSame && ![guesses containsObject:guess])
            [guesses addObject:guess];
    }
    return guesses;
}

void DPPaletteFetchSuggestions(NSString *query, void (^done)(NSArray<NSString *> *suggestions)) {
    static NSURLSession *session;
    static NSURLSessionDataTask *task;
    if (!session) {
        // Ephemeral: it sends no cookies, so it isn't signed in to Google.
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = DPSuggestTimeout;
        session = [NSURLSession sessionWithConfiguration:configuration delegate:nil delegateQueue:NSOperationQueue.mainQueue];
    }
    [task cancel];
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://suggestqueries.google.com/complete/search"];
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"client" value:@"firefox"], [NSURLQueryItem queryItemWithName:@"ie" value:@"utf-8"],
                              [NSURLQueryItem queryItemWithName:@"oe" value:@"utf-8"], [NSURLQueryItem queryItemWithName:@"q" value:query]];
    components.percentEncodedQuery = [components.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];  // Or "c++" reads as "c  ".
    task = [session dataTaskWithURL:components.URL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error.code == NSURLErrorCancelled) return;
        done(DPPaletteParseSuggestions(error ? nil : data, query));
    }];
    [task resume];
}

NSArray<DPPaletteRow *> *DPPaletteAddSuggestions(NSArray<DPPaletteRow *> *shown, NSArray<NSString *> *suggestions) {
    NSUInteger google = [shown indexOfObjectPassingTest:^BOOL(DPPaletteRow *row, NSUInteger i, BOOL *stop) { return row.kind == DPPaletteKindGoogle; }];
    if (google == NSNotFound || !suggestions.count) return shown;
    NSMutableArray<DPPaletteRow *> *rows = [shown mutableCopy];
    [suggestions enumerateObjectsUsingBlock:^(NSString *guess, NSUInteger i, BOOL *stop) {
        DPPaletteRow *row = DPPaletteGoogleRow(guess);
        row.title = guess;
        [rows insertObject:row atIndex:google + 1 + i];
    }];
    return rows;
}

NSString *DPPaletteCheckSuggestions(void) {
    NSData *reply = [@"[\"wea\",[\"weather\",\"Wea\",\"weather\",3,\"weather tomorrow\",\"wear\",\"weak\"],[],{}]" dataUsingEncoding:NSUTF8StringEncoding];
    NSArray<NSString *> *guesses = DPPaletteParseSuggestions(reply, @"wea ");
    if (![guesses isEqualToArray:@[@"weather", @"weather tomorrow", @"wear"]]) return @"Google's suggestions read wrong";
    if (DPPaletteParseSuggestions([@"{\"wea\":[]}" dataUsingEncoding:NSUTF8StringEncoding], @"wea").count || DPPaletteParseSuggestions(nil, @"wea").count)
        return @"a broken reply gave suggestions";
    NSArray<DPPaletteRow *> *rows = DPPaletteAddSuggestions(@[DPPaletteGoogleRow(@"wea"), DPPaletteClaudeRow(@"wea")], guesses);
    if (rows.count != 5 || ![rows[1].title isEqualToString:@"weather"] || rows[1].kind != DPPaletteKindGoogle || rows[4].kind != DPPaletteKindClaude)
        return @"suggestions aren't right after Search Google";
    return nil;
}
