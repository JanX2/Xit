//
//  Xit.m
//  Xit
//
//  Created by glaullon on 7/15/11.
//

#import "Xit.h"
#import "XTHistoryView.h"

@implementation Xit

@synthesize selectedCommit;
@synthesize refsIndex;

+ (NSString *) gitPath {
    NSArray *paths = [NSArray arrayWithObjects:
                      @"/usr/bin/git",
                      @"/usr/local/git/bin/git",
                      nil];

    for (NSString *path in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
            return path;
    }
    return nil;
}

- (id) init {
    self = [super init];
    if (self) {
        gitCMD = [Xit gitPath];
        repoURL = [NSURL URLWithString:@"/Users/administrator/xcode/Xit"];         // Default only for test.
    }
    return self;
}

- (id) initWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError {
    self = [super initWithContentsOfURL:absoluteURL ofType:typeName error:outError];
    if (self) {
        absoluteURL = [absoluteURL URLByDeletingPathExtension];
        repoURL = absoluteURL;
    }
    return self;
}

- (NSURL *) repoURL {
    return repoURL;
}

// XXX tmp
- (void) start {
    [self initializeEventStream];
}

- (void) stop {
    FSEventStreamStop(stream);
    FSEventStreamInvalidate(stream);
}

- (NSString *) windowNibName {
    return @"Xit";
}

- (void) windowControllerDidLoadNib:(NSWindowController *)aController {
    [super windowControllerDidLoadNib:aController];

    [historyView loadView];
    NSTabViewItem *tabViewHistory = [tabs tabViewItemAtIndex:0];
    [[historyView view] setFrame:NSMakeRect(0, 0, [[historyView view] frame].size.width, [[historyView view] frame].size.height)];
    [tabViewHistory setView:[historyView view]];
    [historyView setRepo:self];

    [stageView loadView];
    NSTabViewItem *tabViewStage = [tabs tabViewItemAtIndex:1];
    [[stageView view] setFrame:NSMakeRect(0, 0, [[stageView view] frame].size.width, [[stageView view] frame].size.height)];
    [tabViewStage setView:[stageView view]];
    [stageView setRepo:self];

    [self start];
}

- (BOOL) readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError {
    return true; // XXX
}

#pragma mark - git commands

- (void) getCommitsWithArgs:(NSArray *)logArgs enumerateCommitsUsingBlock:(void (^)(NSString *))block error:(NSError **)error {
    if (repoURL == nil) {
        if (error != NULL)
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:fnfErr userInfo:nil];
        return;
    }
    NSMutableArray *args = [NSMutableArray arrayWithArray:logArgs];

    [args insertObject:@"log" atIndex:0];
    [args insertObject:@"-z" atIndex:1];
    NSData *zero = [NSData dataWithBytes:"" length:1];

    NSLog(@"****command = git %@", [args componentsJoinedByString:@" "]);
    NSTask *task = [[NSTask alloc] init];
    [task setCurrentDirectoryPath:[repoURL path]];
    [task setLaunchPath:gitCMD];
    [task setArguments:args];

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    [task  launch];
    NSMutableData *output = [NSMutableData data];

    BOOL end = NO;
    while (!end) {
        NSData *availableData = [[pipe fileHandleForReading] availableData];
        [output appendData:availableData];

        end = (([availableData length] == 0) && ![task isRunning]);
        if (end)
            [output appendData:zero];

        NSRange searchRange = NSMakeRange(0, [output length]);
        NSRange zeroRange = [output rangeOfData:zero options:0 range:searchRange];
        while (zeroRange.location != NSNotFound) {
            NSRange commitRange = NSMakeRange(searchRange.location, (zeroRange.location - searchRange.location));
            NSData *commit = [output subdataWithRange:commitRange];
            NSString *str = [[NSString alloc] initWithData:commit encoding:NSUTF8StringEncoding];
            if (str != nil)
                block(str);
            searchRange = NSMakeRange(zeroRange.location + 1, [output length] - (zeroRange.location + 1));
            zeroRange = [output rangeOfData:zero options:0 range:searchRange];
        }
        output = [NSMutableData dataWithData:[output subdataWithRange:searchRange]];
    }

    int status = [task terminationStatus];
    NSLog(@"**** status = %d", status);

    if (status != 0) {
        NSString *string = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"git"
                                         code:status
                                     userInfo:[NSDictionary dictionaryWithObject:string forKey:@"output"]];
        }
    }
}

- (NSData *) exectuteGitWithArgs:(NSArray *)args error:(NSError **)error {
    return [self exectuteGitWithArgs:args withStdIn:nil error:error];
}

- (NSData *) exectuteGitWithArgs:(NSArray *)args withStdIn:(NSString *)stdIn error:(NSError **)error {
    if (repoURL == nil)
        return nil;
    NSLog(@"****command = git %@", [args componentsJoinedByString:@" "]);
    NSTask *task = [[NSTask alloc] init];
    [task setCurrentDirectoryPath:[repoURL path]];
    [task setLaunchPath:gitCMD];
    [task setArguments:args];

    if (stdIn != nil) {
//        NSLog(@"**** stdin = %lu", stdIn.length);
        NSLog(@"**** stdin = %lu\n%@", stdIn.length, stdIn);
        NSPipe *stdInPipe = [NSPipe pipe];
        [[stdInPipe fileHandleForWriting] writeData:[stdIn dataUsingEncoding:NSUTF8StringEncoding]];
        [[stdInPipe fileHandleForWriting] closeFile];
        [task setStandardInput:stdInPipe];
    }

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    [task  launch];
    NSData *output = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];

    int status = [task terminationStatus];
    NSLog(@"**** status = %d", status);

    if (status != 0) {
        NSString *string = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
        NSLog(@"**** output = %@", string);
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"git"
                                         code:status
                                     userInfo:[NSDictionary dictionaryWithObject:string forKey:@"output"]];
        }
        output = nil;
    }

    return output;
}

#pragma mark - monitor file system
- (void) initializeEventStream {
    if (repoURL == nil)
        return;
    NSString *myPath = [[repoURL URLByAppendingPathComponent:@".git"] absoluteString];
    NSArray *pathsToWatch = [NSArray arrayWithObject:myPath];
    void *appPointer = (void *)self;
    FSEventStreamContext context = { 0, appPointer, NULL, NULL, NULL };
    NSTimeInterval latency = 3.0;

    stream = FSEventStreamCreate(NULL,
                                 &fsevents_callback,
                                 &context,
                                 (CFArrayRef)pathsToWatch,
                                 kFSEventStreamEventIdSinceNow,
                                 (CFAbsoluteTime)latency,
                                 kFSEventStreamCreateFlagUseCFTypes
                                 );

    FSEventStreamScheduleWithRunLoop(stream,
                                     CFRunLoopGetCurrent(),
                                     kCFRunLoopDefaultMode);
    FSEventStreamStart(stream);
}

int event = 0;

void fsevents_callback(ConstFSEventStreamRef streamRef,
                       void *userData,
                       size_t numEvents,
                       void *eventPaths,
                       const FSEventStreamEventFlags eventFlags[],
                       const FSEventStreamEventId eventIds[]){
    Xit *xit = (Xit *)userData;

    event++;

    NSMutableArray *reload = [NSMutableArray arrayWithCapacity:numEvents];
    for (size_t i = 0; i < numEvents; i++) {
        NSString *path = [(NSArray *) eventPaths objectAtIndex:i];
        NSRange r = [path rangeOfString:@".git" options:NSBackwardsSearch];
        path = [path substringFromIndex:r.location];
        [reload addObject:path];
        NSLog(@"%d\t%@", event, path);
    }

    [xit setValue:reload forKey:@"reload"];
}

#pragma mark - temp
- (IBAction) reload:(id)sender {
    NSLog(@"########## reload ##########");
    [self setValue:[NSArray arrayWithObjects:@".git/refs/", @".git/logs/", nil] forKey:@"reload"];
}
@end
