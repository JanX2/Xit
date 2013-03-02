//
//  XTAppDelegate.m
//  Xit
//
//  Created by David Catmull on 10/13/11.
//

#import "XTAppDelegate.h"
#import "XTDocument.h"
#include <git2.h>

@implementation XTAppDelegate

- (id)init {
    self = [super init];
    if (self) {
        git_threads_init();
    }

    return self;
}

- (void)openDocument:(id)sender {
    if (openPanel != nil) {
        [openPanel makeKeyAndOrderFront:self];
        return;
    }

    openPanel = [NSOpenPanel openPanel];

    [openPanel setCanChooseFiles:NO];
    [openPanel setCanChooseDirectories:YES];
    [openPanel setDelegate:self];
    [openPanel beginWithCompletionHandler:^(NSInteger result) {
        if (result == NSFileHandlingPanelOKButton) {
            for (NSURL *url in [openPanel URLs]) {
                [[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES completionHandler:NULL];
            }
        }
        openPanel = nil;
    }];
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)app {
    [self openDocument:nil];
    // Returning YES prevents the app from opening an untitled document on its own.
    return YES;
}

- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError {
    NSURL *repoURL = [url URLByAppendingPathComponent:@".git" isDirectory:YES];

    if ([[NSFileManager defaultManager] fileExistsAtPath:[repoURL path]])
        return YES;
    else {
        NSAlert *alert = [NSAlert alertWithMessageText:@"That folder does not contain a Git repository." defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];

        [alert beginSheetModalForWindow:[sender window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
        return NO;
    }
}

@end
