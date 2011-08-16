//
//  XTHistoryDataSource.m
//  Xit
//
//  Created by German Laullon on 26/07/11.
//

#import "XTHistoryDataSource.h"
#import "Xit.h"
#import "XTHistoryItem.h"
#import "PBGitHistoryGrapher.h"
#import "PBGitRevisionCell.h"

#import <ObjectiveGit/ObjectiveGit.h>

@implementation XTHistoryDataSource

@synthesize items;

- (id) init {
    self = [super init];
    if (self) {
        items = [NSMutableArray array];
        queue = dispatch_queue_create("com.xit.queue.history", nil);
        index = [NSMutableDictionary dictionary];
    }

    return self;
}

- (void) setRepo:(Xit *)newRepo {
    repo = newRepo;
    [repo addObserver:self forKeyPath:@"reload" options:NSKeyValueObservingOptionNew context:nil];
    [repo addObserver:self forKeyPath:@"selectedCommit" options:NSKeyValueObservingOptionNew context:nil];
    [self reload];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"reload"]) {
        NSArray *reload = [change objectForKey:NSKeyValueChangeNewKey];
        for (NSString *path in reload) {
            if ([path hasPrefix:@".git/logs/"]) {
                [self reload];
                break;
            }
        }
    } else if ([keyPath isEqualToString:@"selectedCommit"]) {
        NSString *newSelectedCommit = [change objectForKey:NSKeyValueChangeNewKey];
        XTHistoryItem *item = [index objectForKey:newSelectedCommit];
        if (item != nil) {
            [table selectRowIndexes:[NSIndexSet indexSetWithIndex:item.index] byExtendingSelection:NO];
            [table scrollRowToVisible:item.index];
        } else {
            NSLog(@"commit '%@' not found!!", newSelectedCommit);
        }
    }
}

- (void) reload {
    dispatch_async(queue, ^{
		NSMutableArray *newItems = [NSMutableArray array];
#if 1
		NSError *error = nil;
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		
		[formatter setDateStyle:NSDateFormatterShortStyle];
		[formatter setTimeStyle:NSDateFormatterShortStyle];
		[[repo repository] enumerateCommitsBeginningAtSha:nil sortOptions:GTEnumeratorOptionsTopologicalSort|GTEnumeratorOptionsReverse error:&error usingBlock:^(GTCommit *commit, BOOL *stop) {
			XTHistoryItem *item = [[XTHistoryItem alloc] init];
			item.sha = [commit sha];
			item.date = [formatter stringFromDate:[commit commitDate]];
			item.subject = [commit message];
			item.email = [[commit author] name];
			for (GTCommit *parent in [commit parents]) {
				XTHistoryItem *parentItem = [index objectForKey:parent.sha];
				if (parentItem != nil) {
					[item.parents addObject:parentItem];
				} else {
					NSLog (@"parent with sha:'%@' not found for commit with sha:'%@' idx=%lu", parent.sha, item.sha, item.index);
				}
			}
			[newItems insertObject:item atIndex:0];
			[index setObject:item forKey:item.sha];
		}];
#else
		void (^commitBlock)(NSString *) = ^(NSString *line) {
			NSArray *comps = [line componentsSeparatedByString:@"\n"];
//          NSLog(@"line: %@",[comps componentsJoinedByString:@" - "]);
			XTHistoryItem *item = [[XTHistoryItem alloc] init];
			if ([comps count] == 5) {
				item.sha = [comps objectAtIndex:0];
				NSString *parentsStr = [comps objectAtIndex:1];
				if (parentsStr.length > 0) {
					NSArray *parents = [parentsStr componentsSeparatedByString:@" "];
					[parents enumerateObjectsWithOptions:0 usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
						NSString *parentSha = (NSString *)obj;
						XTHistoryItem *parent = [index objectForKey:parentSha];
						if (parent != nil) {
							[item.parents addObject:parent];
						} else {
							NSLog (@"parent with sha:'%@' not found for commit with sha:'%@' idx=%lu", parentSha, item.sha, item.index);
						}
					}];
				}
				item.date = [comps objectAtIndex:2];
				item.email = [comps objectAtIndex:3];
				item.subject = [comps objectAtIndex:4];
				[newItems addObject:item];
				[index setObject:item forKey:item.sha];
			} else {
				[NSException raise:@"Invalid commint" format:@"Line ***\n%@\n*** is invalid", line];
			}
			
		};
		
		[repo    getCommitsWithArgs:[NSArray arrayWithObjects:@"--pretty=format:%H%n%P%n%ct%n%ce%n%s", @"--reverse", @"--tags", @"--all", @"--topo-order", nil]
		 enumerateCommitsUsingBlock:commitBlock
							  error:nil];
		
		// Reverse the order
		NSUInteger i = 0;
		NSUInteger j = [newItems count] - 1;
		while (i < j) {
			[newItems exchangeObjectAtIndex:i++ withObjectAtIndex:j--];
		}
#endif
		
		PBGitGrapher *grapher = [[PBGitGrapher alloc] init];
		[newItems enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			XTHistoryItem *item = (XTHistoryItem *)obj;
			[grapher decorateCommit:item];
			item.index = idx;
		}];
		
		NSLog (@"-> %lu", [newItems count]);
		items = newItems;
		[table reloadData];
	});
}

// only for unit test
- (void) waitUntilReloadEnd {
    dispatch_sync(queue, ^{ });
    [items enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL * stop) {
         XTHistoryItem *item = (XTHistoryItem *)obj;
         NSLog (@"numColumns=%lu - parents=%lu - %@", item.lineInfo.numColumns, item.parents.count, item.subject);
     }];
}

#pragma mark - NSTableViewDataSource

- (NSInteger) numberOfRowsInTableView:(NSTableView *)aTableView {
    table = aTableView;
    [table setDelegate:self];
    return [items count];
}

- (id) tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    XTHistoryItem *item = [items objectAtIndex:rowIndex];

    return [item valueForKey:aTableColumn.identifier];
}

#pragma mark - NSTableViewDelegate

- (void) tableViewSelectionDidChange:(NSNotification *)aNotification {
    NSLog(@"%@", aNotification);
    XTHistoryItem *item = [items objectAtIndex:table.selectedRow];
    repo.selectedCommit = item.sha;
}

- (void) tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    XTHistoryItem *item = [items objectAtIndex:rowIndex];

    ((PBGitRevisionCell *)aCell).objectValue = item;
}

@end
