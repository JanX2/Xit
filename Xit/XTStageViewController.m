//
//  XTStageViewController.m
//  Xit
//
//  Created by German Laullon on 10/08/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "XTStageViewController.h"
#import "XTFileIndexInfo.h"
#import "Xit.h"
#import "XTHTML.h"
#import "XTFileIndexCell.h"

@implementation XTStageViewController

+ (id) viewController {
    return [[[self alloc] initWithNibName:NSStringFromClass([self class]) bundle:nil] autorelease];
}

- (void) loadView {
    [super loadView];
    [self viewDidLoad];
}

- (void) viewDidLoad {
    NSLog(@"viewDidLoad");
}

- (void) setRepo:(Xit *)newRepo {
    repo = newRepo;
    [stageDS setRepo:repo];
    [unstageDS setRepo:repo];
}

- (void) reload {
    [stageDS reload];
    [unstageDS reload];
    [stageTable reloadData];
    [unstageTable reloadData];
}

#pragma mark -

- (void) showUnstageFile:(XTFileIndexInfo *)file {
    NSData *output = [repo exectuteGitWithArgs:[NSArray arrayWithObjects:@"diff-files", @"--patch", @"--", file.name, nil] error:nil];

    actualDiff = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    stagedFile = NO;

    NSString *diffHTML = [XTHTML parseDiff:actualDiff];
    [self showDiff:diffHTML];
}

- (void) showStageFile:(XTFileIndexInfo *)file {
    NSData *output = [repo exectuteGitWithArgs:[NSArray arrayWithObjects:@"diff-index",  @"--patch", @"--cached", @"HEAD", @"--", file.name, nil] error:nil];

    actualDiff = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    stagedFile = YES;

    NSString *diffHTML = [XTHTML parseDiff:actualDiff];
    [self showDiff:diffHTML];
}

- (void) showDiff:(NSString *)diff {
    NSString *html = [NSString stringWithFormat:@"<html><head><link rel='stylesheet' type='text/css' href='diff.css'/></head><body><div id='diffs'>%@</div></body></html>", diff];

    NSBundle *bundle = [NSBundle mainBundle];
    NSBundle *theme = [NSBundle bundleWithURL:[bundle URLForResource:@"html.theme.default" withExtension:@"bundle"]];
    NSURL *themeURL = [[theme bundleURL] URLByAppendingPathComponent:@"Contents/Resources"];

    [[web mainFrame] loadHTMLString:html baseURL:themeURL];
}

#pragma mark -

- (void) unstageChunk:(NSInteger)idx {
    [repo exectuteGitWithArgs:[NSArray arrayWithObjects:@"apply",  @"--cached", @"--reverse", nil]
                    withStdIn:[self preparePatch:idx]
                        error:nil];
    [self reload];
}

- (void) stageChunk:(NSInteger)idx {
    [repo exectuteGitWithArgs:[NSArray arrayWithObjects:@"apply",  @"--cached", nil]
                    withStdIn:[self preparePatch:idx]
                        error:nil];
    [self reload];
}

- (void) discardChunk:(NSInteger)idx {

}

#pragma mark -

- (NSString *) preparePatch:(NSInteger)idx {
    NSArray *comps = [actualDiff componentsSeparatedByString:@"\n@@"];
    NSMutableString *patch = [NSMutableString stringWithString:[comps objectAtIndex:0]]; // Header

    [patch appendString:@"\n@@"];
    [patch appendString:[comps objectAtIndex:(idx + 1)]];
    [patch appendString:@"\n"];
    return patch;
}


#pragma mark - WebFrameLoadDelegate

- (void) webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    DOMDocument *dom = [[web mainFrame] DOMDocument];
    DOMNodeList *headres = [dom getElementsByClassName:@"header"]; // TODO: change class names

    for (int n = 0; n < headres.length; n++) {
        DOMHTMLElement *header = (DOMHTMLElement *)[headres item:n];
        if (stagedFile) {
            [[[header children] item:0] appendChild:[self createButtonWithIndex:n title:@"Unstage" fromDOM:dom]];
        } else {
            [[[header children] item:0] appendChild:[self createButtonWithIndex:n title:@"Stage" fromDOM:dom]];
            [[[header children] item:0] appendChild:[self createButtonWithIndex:n title:@"Discard" fromDOM:dom]];
        }
    }
}

- (DOMHTMLElement *) createButtonWithIndex:(int)index title:(NSString *)title fromDOM:(DOMDocument *)dom {
    DOMHTMLInputElement *bt = (DOMHTMLInputElement *)[dom createElement:@"input"];

    bt.type = @"button";
    bt.value = title;
    bt.name = [NSString stringWithFormat:@"%d", index];
    [bt addEventListener:@"click" listener:self useCapture:YES];
    return bt;
}

#pragma mark - DOMEventListener

- (void) handleEvent:(DOMEvent *)evt {
    DOMHTMLInputElement *bt = (DOMHTMLInputElement *)evt.target;

    NSLog(@"handleEvent: %@ - %@", bt.value, bt.name);
    if ([bt.value isEqualToString:@"Unstage"]) {
        [self unstageChunk:[bt.name intValue]];
    } else if ([bt.value isEqualToString:@"Stage"]) {
        [self stageChunk:[bt.name intValue]];
    } else if ([bt.value isEqualToString:@"Discard"]) {
        [self discardChunk:[bt.name intValue]];
    }
}

#pragma mark - NSTableViewDelegate

- (void) tableViewSelectionDidChange:(NSNotification *)aNotification {
    NSTableView *table = (NSTableView *)aNotification.object;

    if (table.numberOfSelectedRows > 0) {
        if ([table isEqualTo:stageTable]) {
            [unstageTable deselectAll:nil];
            XTFileIndexInfo *item = [[stageDS items] objectAtIndex:table.selectedRow];
            [self showStageFile:item];
        } else if ([table isEqualTo:unstageTable]) {
            [stageTable deselectAll:nil];
            XTFileIndexInfo *item = [[unstageDS items] objectAtIndex:table.selectedRow];
            [self showUnstageFile:item];
        }
    }
}

- (void) tableView:(NSTableView *)table willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    XTFileIndexInfo *item;

    if ([table isEqualTo:stageTable]) {
        item = [[stageDS items] objectAtIndex:rowIndex];
    } else if ([table isEqualTo:unstageTable]) {
        item = [[unstageDS items] objectAtIndex:rowIndex];
    }

    NSString *path = [[[repo repoURL] path] stringByAppendingPathComponent:item.name];
    NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
    if (icon == nil) {
        NSString *type = (NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)[path pathExtension], NULL);
        icon = [[NSWorkspace sharedWorkspace] iconForFileType:type];
    }

    NSLog(@"-- aCell: %@ -- icon: %@", aCell, icon);
    ((XTFileIndexCell *)aCell).fileInfo = item;
    ((XTFileIndexCell *)aCell).icon = icon;
}
@end
