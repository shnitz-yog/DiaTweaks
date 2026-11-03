// Command palette: ⌘T opens a search bar. Typing fans the results out beside it on a loop, and resting on one for two
// seconds, or pressing →, shows its actions. Rows are a snapshot taken on opening, except history and Google's suggestions, fetched as you type.
#import "StdPatch/StdPatch.h"

typedef NS_ENUM(NSInteger, DPPaletteKind) { DPPaletteKindTab, DPPaletteKindSite, DPPaletteKindGoogle, DPPaletteKindClaude, DPPaletteKindCommand };

@interface DPPaletteRow : NSObject
@property (nonatomic, copy) NSString *title, *detail, *symbol, *tag, *searchText;  // searchText: the address without its scheme, if it has one.
@property (nonatomic, copy) void (^action)(void);
@property (nonatomic) DPPaletteKind kind;
@property (nonatomic) NSInteger score, bonus;  // bonus lifts a row among matches; it never makes one.
@property (nonatomic, copy) NSArray<DPPaletteRow *> *moons;  // Its actions, or nil. The first is what Enter runs.
@property (nonatomic, strong) id image, activeImage;  // Art.m draws them.
@property (nonatomic) NSSize imageSize, activeImageSize;
@end

// Match.m
NSInteger DPPaletteScore(NSString *query, NSString *text);  // 0 if it doesn't match; higher is better.
NSURL *DPPaletteURL(NSString *query);                       // The web address typed, or nil.
NSString *DPPaletteCheckMatching(void);                     // nil, or which check failed.

BOOL DPIsCommand(NSEvent *event, NSString *characters);  // CommandPalette.m

// Rows.m
DPPaletteRow *DPPaletteMakeRow(DPPaletteKind kind, NSString *title, NSString *detail, NSString *symbol, void (^action)(void));
void DPPaletteUseMoons(DPPaletteRow *row, NSArray<DPPaletteRow *> *moons);  // Enter then runs the first.
NSArray<DPPaletteRow *> *DPPaletteTabRows(void);
NSArray<DPPaletteRow *> *DPPaletteSnapshot(void);  // Tabs, then commands, then tweaks.
NSArray<DPPaletteRow *> *DPPaletteFilter(NSArray<DPPaletteRow *> *rows, NSString *query);
NSMenuItem *DPPaletteMenuItem(NSString *title);
void DPPaletteRunMenuItem(NSString *title);
NSString *DPPaletteBareURL(NSString *url);

// Actions.m
void DPPaletteOpenURL(NSURL *url);
NSArray<DPPaletteRow *> *DPPaletteTabMoons(id tab, NSString *title, NSURL *url);
NSArray<DPPaletteRow *> *DPPaletteSiteMoons(NSURL *url, NSString *title);
DPPaletteRow *DPPaletteGoogleRow(NSString *query);
DPPaletteRow *DPPaletteClaudeRow(NSString *query);

// Suggest.m
NSArray<NSString *> *DPPaletteParseSuggestions(NSData *data, NSString *query);  // Google's guesses for query, or none.
void DPPaletteFetchSuggestions(NSString *query, void (^done)(NSArray<NSString *> *suggestions));  // On the main queue; a newer fetch cancels it.
NSArray<DPPaletteRow *> *DPPaletteAddSuggestions(NSArray<DPPaletteRow *> *shown, NSArray<NSString *> *suggestions);  // Right after Search Google.
NSString *DPPaletteCheckSuggestions(void);  // nil, or which check failed.

// History.m
NSArray<DPPaletteRow *> *DPPaletteHistoryRowsIn(NSString *path, NSString *query);
NSArray<DPPaletteRow *> *DPPaletteHistoryRows(NSString *query);  // nil if no profile's history could be read.

// Art.m
extern const CGFloat DPPaletteChipHeight, DPPaletteChipMargin, DPPaletteMoonHeight;
id DPImage(NSSize size, NSAppearance *appearance, CGFloat scale, void (^draw)(void));
NSColor *DPPaletteSurfaceColor(void);
NSColor *DPPaletteLineColor(void);
NSColor *DPPaletteFaintTextColor(void);
void DPPaletteDrawRow(DPPaletteRow *row, NSString *query, NSAppearance *appearance, CGFloat scale);
void DPPaletteDrawMoons(DPPaletteRow *row, NSAppearance *appearance, CGFloat scale);

// Orbit.m
void DPSetContents(CALayer *layer, id image, NSSize size, CGFloat scale);
void DPSetShadowShape(CALayer *layer, NSSize size, CGFloat radius);
void DPAddShadow(CALayer *layer, CGFloat radius);
typedef struct {
    double position;  // Which result faces the search bar; fractions mid-spin. It keeps counting past the last one.
    CGFloat reveal, moonReveal, focus;  // Each 0 to 1. focus: how far into the moons, with the rest blurred and shifted away.
    NSInteger moonFocus;  // The moon picked, or -1.
} DPOrbitMotion;
typedef struct { CGFloat left, hubX, hubY, shift, chipLeft; } DPOrbitFit;  // Points from the top left.
DPOrbitFit DPOrbitFitIn(NSSize size);

@interface DPOrbit : NSObject
@property (nonatomic, readonly) NSView *view;
@property (nonatomic, copy) NSArray<DPPaletteRow *> *rows;
@property (nonatomic, strong) DPPaletteRow *moonRow;  // The active row, once Art.m has drawn its moons.
@property (nonatomic) CGFloat scale;
- (void)setScrimColor:(NSColor *)color appearance:(NSAppearance *)appearance;
- (void)layoutInSize:(NSSize)size motion:(DPOrbitMotion)motion;
- (NSInteger)stepsToResultAt:(NSPoint)point;  // How far it is from the active result, or NSNotFound.
- (NSInteger)moonAt:(NSPoint)point;           // Or -1.
@end

// Panel.m
void DPPaletteToggle(NSWindow *parent);
void DPPaletteOpen(NSWindow *parent, NSString *text);  // Opens with `text` selected, ready to edit or replace.
void DPPaletteHide(void);
BOOL DPPaletteIsOpen(void);
void DPPaletteRunMoon(NSInteger index);  // Runs that action of the active result, if it has one.
NSDictionary *DPPaletteDebugState(void);
