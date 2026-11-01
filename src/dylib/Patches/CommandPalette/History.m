// Searches Dia's Chromium History database, read-only. Nothing from it leaves the palette.
#import "CommandPalette.h"
#include <sqlite3.h>

static const int DPHistoryLimit = 100, DPMostVisitsBonus = 20;

static NSString *DPColumn(sqlite3_stmt *statement, int column) {
    const unsigned char *text = sqlite3_column_text(statement, column);
    return text ? @((const char *)text) : nil;
}

static NSString *DPLikePattern(NSString *query) {
    NSMutableArray<NSString *> *words = [NSMutableArray new];
    for (NSString *word in [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (!word.length) continue;
        NSString *escaped = [word stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"%" withString:@"\\%"];
        [words addObject:[escaped stringByReplacingOccurrencesOfString:@"_" withString:@"\\_"]];
    }
    return [NSString stringWithFormat:@"%%%@%%", [words componentsJoinedByString:@"%"]];
}

static DPPaletteRow *DPHistoryRow(NSString *address, NSString *title, int visits) {
    NSURLComponents *components = [NSURLComponents componentsWithString:address];
    NSString *scheme = components.scheme.lowercaseString;
    NSURL *url = components.URL;
    if (!url || !components.host.length || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return nil;
    NSString *name = title.length ? title : components.host;
    DPPaletteRow *row = DPPaletteMakeRow(DPPaletteKindSite, name, components.host, @"clock", nil);
    row.searchText = DPPaletteBareURL(address);
    row.bonus = MIN(visits, DPMostVisitsBonus);
    DPPaletteUseMoons(row, DPPaletteSiteMoons(url, name));
    return row;
}

// nil if the file can't be read as a History database.
// shortcut: immutable=1 reads past the lock Dia holds without seeing a write in progress, so a row can lag by a moment.
NSArray<DPPaletteRow *> *DPPaletteHistoryRowsIn(NSString *path, NSString *query) {
    NSString *uri = [[NSURL fileURLWithPath:path].absoluteString stringByAppendingString:@"?immutable=1"];
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;
    NSMutableArray<DPPaletteRow *> *rows = nil;
    const char *sql = "SELECT url, title, visit_count FROM urls WHERE hidden = 0 AND (url LIKE ?1 ESCAPE '\\' OR title LIKE ?1 ESCAPE '\\') "
                      "ORDER BY typed_count DESC, visit_count DESC, last_visit_time DESC LIMIT ?2";
    if (sqlite3_open_v2(uri.UTF8String, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, NULL) == SQLITE_OK
        && sqlite3_prepare_v2(database, sql, -1, &statement, NULL) == SQLITE_OK) {
        rows = [NSMutableArray new];
        sqlite3_bind_text(statement, 1, DPLikePattern(query).UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(statement, 2, DPHistoryLimit);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            DPPaletteRow *row = DPHistoryRow(DPColumn(statement, 0), DPColumn(statement, 1), sqlite3_column_int(statement, 2));
            if (row) [rows addObject:row];
        }
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return rows;
}

NSArray<DPPaletteRow *> *DPPaletteHistoryRows(NSString *query) {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *data = [support stringByAppendingPathComponent:@"Dia/User Data"];
    NSMutableArray<DPPaletteRow *> *rows = nil;
    for (NSString *profile in [NSFileManager.defaultManager contentsOfDirectoryAtPath:data error:nil]) {
        NSString *path = [[data stringByAppendingPathComponent:profile] stringByAppendingPathComponent:@"History"];
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        NSArray<DPPaletteRow *> *found = DPPaletteHistoryRowsIn(path, query);
        if (found) [rows ?: (rows = [NSMutableArray new]) addObjectsFromArray:found];
    }
    return rows;
}
