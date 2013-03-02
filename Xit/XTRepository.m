//
//  XTRepository.m
//  Xit
//

#import "XTRepository.h"
#import "NSMutableDictionary+MultiObjectForKey.h"
#import <ObjectiveGit/ObjectiveGit.h>

NSString *XTRepositoryChangedNotification = @"xtrepochanged";
NSString *XTErrorOutputKey = @"output";
NSString *XTErrorArgsKey = @"args";
NSString *XTPathsKey = @"paths";

@implementation XTRepository

@synthesize selectedCommit;
@synthesize refsIndex;
@synthesize queue;
@synthesize activeTasks;
@synthesize repoURL;
@synthesize objgitRepo;

+ (NSString *)gitPath {
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


- (id)initWithURL:(NSURL *)url {
    self = [super init];
    if (self != nil) {
        NSError *error;

        objgitRepo = [GTRepository repositoryWithURL:url error:&error];
        if (objgitRepo == nil)
          return nil;
        gitCMD = [XTRepository gitPath];
        repoURL = url;
        NSMutableString *qName = [NSMutableString stringWithString:@"com.xit.queue."];
        [qName appendString:[url path]];
        queue = dispatch_queue_create([qName cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_SERIAL);
        activeTasks = [NSMutableArray array];
    }

    return self;
}

- (void)executeOffMainThread:(void (^)())block {
    if ([NSThread isMainThread])
        dispatch_async(queue, block);
    else
        block();
}

- (void)addTask:(NSTask *)task {
    [self willChangeValueForKey:@"activeTasks"];
    [activeTasks addObject:task];
    [self didChangeValueForKey:@"activeTasks"];
}

- (void)removeTask:(NSTask *)task {
    if ([activeTasks count] != 0) {
        [self willChangeValueForKey:@"activeTasks"];
        [activeTasks removeObject:task];
        [self didChangeValueForKey:@"activeTasks"];
    }
}

- (void)waitForQueue {
    // Some queued tasks need to also perform tasks on the main thread, so
    // simply waiting on the queue could cause a deadlock.
    const CFRunLoopRef loop = CFRunLoopGetCurrent();
    __block BOOL keepLooping = YES;

    // Loop because something else might quit the run loop.
    do {
        CFRunLoopPerformBlock(
                loop,
                kCFRunLoopCommonModes,
                ^{
                    dispatch_async(queue, ^{
                        CFRunLoopStop(loop);
                        keepLooping = NO;
                    });
                });
        CFRunLoopRun();
    } while (keepLooping);
}

// Manually sort the commits because the libgit2 revwalker doesn't always put
// newer branches at the top
- (NSArray*)sortedCommits {
    GTEnumerator *enumerator = self.objgitRepo.enumerator;
    GTCommit *commit = nil;
    NSError *error = nil;

    [enumerator reset];
    enumerator.options = GTEnumeratorOptionsNone;
    [enumerator pushAllRefsWithError:&error];
    if (error != nil) {
        // handle error
        return nil;
    }

    NSMutableArray *sourceList = [NSMutableArray array];

    while ((commit = [enumerator nextObjectWithError:&error]) != nil) {
        [sourceList addObject:commit];
    }
    if (error != nil) {
        // handle error
        return nil;
    }

    NSArray *refs = [self.objgitRepo referenceNamesWithError:&error];

    if (error != nil) {
        // handle error
        return nil;
    }
    // sort refs by date
    for (NSString *ref in refs) {
        GTObject *object = [self.objgitRepo lookupObjectByRefspec:ref error:&error];

        if (error != nil) {
            // handle error
            return nil;
        }
        if (![object isKindOfClass:[GTCommit class]])
            continue;

        GTCommit *commit = (GTCommit *)object;
        NSMutableArray *mergeList = [NSMutableArray array];

        while (commit != nil) {
            // add object to the list
            // if it has multiple parents, add the others to the merge list
            if ([commit.parents count] > 0) {
                if ([commit.parents count] > 1)
                commit = [commit.parents objectAtIndex:0];
            }
            else
                break;
        }
        for (commit in mergeList)
    }
}

- (void)getCommitsWithArgs:(NSArray *)logArgs enumerateCommitsUsingBlock:(void (^)(NSString *))block error:(NSError **)error {
    if (repoURL == nil) {
        if (error != NULL)
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:fnfErr userInfo:nil];
        return;
    }
    if (![self parseReference:@"HEAD"])
        return;  // There are no commits.

    NSMutableArray *args = [NSMutableArray arrayWithArray:logArgs];

    [args insertObject:@"log" atIndex:0];
    [args insertObject:@"-z" atIndex:1];
    NSData *zero = [NSData dataWithBytes:"" length:1];

    NSLog(@"****command = git %@", [args componentsJoinedByString:@" "]);
    NSTask *task = [[NSTask alloc] init];
    [self addTask:task];
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
                                     userInfo:[NSDictionary dictionaryWithObject:string forKey:XTErrorOutputKey]];
        }
    }
    [self removeTask:task];
}

- (NSData *)executeGitWithArgs:(NSArray *)args error:(NSError **)error {
    return [self executeGitWithArgs:args withStdIn:nil error:error];
}

- (NSData *)executeGitWithArgs:(NSArray *)args withStdIn:(NSString *)stdIn error:(NSError **)error {
    if (repoURL == nil)
        return nil;
    NSLog(@"****command = git %@", [args componentsJoinedByString:@" "]);
    NSTask *task = [[NSTask alloc] init];
    [self addTask:task];
    [task setCurrentDirectoryPath:[repoURL path]];
    [task setLaunchPath:gitCMD];
    [task setArguments:args];

    if (stdIn != nil) {
#if 0
        NSLog(@"**** stdin = %lu", stdIn.length);
#else
        NSLog(@"**** stdin = %lu\n%@", stdIn.length, stdIn);
#endif
        NSPipe *stdInPipe = [NSPipe pipe];
        [[stdInPipe fileHandleForWriting] writeData:[stdIn dataUsingEncoding:NSUTF8StringEncoding]];
        [[stdInPipe fileHandleForWriting] closeFile];
        [task setStandardInput:stdInPipe];
    }

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    NSLog(@"task.currentDirectoryPath=%@", task.currentDirectoryPath);
    [task  launch];
    NSData *output = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];

    int status = [task terminationStatus];
    NSLog(@"**** status = %d", status);

    if (status != 0) {
        NSString *string = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
        NSLog(@"**** output = %@", string);
        if (error != NULL) {
            NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                    string, XTErrorOutputKey,
                    [args componentsJoinedByString:@" "], XTErrorArgsKey,
                    nil];

            *error = [NSError errorWithDomain:@"git"
                                         code:status
                                     userInfo:info];
        }
        output = nil;
    }
    [self removeTask:task];
    return output;
}

- (NSString *)parseReference:(NSString *)reference {
    NSError *error = nil;
    NSArray *args = [NSArray arrayWithObjects:@"rev-parse", @"--verify", reference, nil];
    NSData *output = [self executeGitWithArgs:args error:&error];

    if (output == nil)
        return nil;
    return [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
}

- (NSString *)parseSymbolicReference:(NSString *)reference {
    NSError *error = nil;
    NSData *output = [self executeGitWithArgs:[NSArray arrayWithObjects:@"symbolic-ref", @"-q", reference, nil] error:&error];

    if (output == nil)
        return nil;

    NSString *ref = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    if ([ref hasPrefix:@"refs/"])
        return [ref stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    return nil;
}

// Returns kEmptyTreeHash if the repository is empty, otherwise "HEAD"
- (NSString *)parentTree {
    NSString *parentTree = @"HEAD";

    if ([self parseReference:parentTree] == nil)
        parentTree = kEmptyTreeHash;
    return parentTree;
}

- (NSString *)shaForRef:(NSString *)ref {
    if (ref == nil)
        return nil;

    for (NSString *sha in [refsIndex allKeys])
        for (NSString *shaRef in [refsIndex objectsForKey:sha])
            if ([shaRef isEqual:ref])
                return sha;

    NSArray *args = [NSArray arrayWithObjects:@"rev-list", @"-1", ref, nil];
    NSError *error = nil;
    NSData *output = [self executeGitWithArgs:args error:&error];

    if ((error != nil) || ([output length] == 0))
        return nil;

    NSString *outputString = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];

    return [outputString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)headRef {
    if (cachedHeadRef == nil) {
        NSString *head = [self parseSymbolicReference:@"HEAD"];

        if ([head hasPrefix:@"refs/heads/"])
            cachedHeadRef = head;
        else
            cachedHeadRef = @"HEAD";

        cachedHeadSHA = [self shaForRef:cachedHeadRef];
    }
    return cachedHeadRef;
}

- (NSString *)headSHA {
    return [self shaForRef:[self headRef]];
}

// XXX tmp
- (void)start {
    [self initializeEventStream];
}

- (void)stop {
    FSEventStreamStop(stream);
    FSEventStreamInvalidate(stream);
}

#pragma mark - monitor file system
- (void)initializeEventStream {
    if (repoURL == nil)
        return;
    NSString *myPath = [[repoURL URLByAppendingPathComponent:@".git"] path];
    NSArray *pathsToWatch = [NSArray arrayWithObject:myPath];
    void *repoPointer = (__bridge void *)self;
    FSEventStreamContext context = { 0, repoPointer, NULL, NULL, NULL };
    NSTimeInterval latency = 3.0;

    stream = FSEventStreamCreate(kCFAllocatorDefault,
                                 &fsevents_callback,
                                 &context,
                                 (__bridge CFArrayRef)pathsToWatch,
                                 kFSEventStreamEventIdSinceNow,
                                 (CFAbsoluteTime)latency,
                                 kFSEventStreamCreateFlagUseCFTypes
                                 );

    FSEventStreamScheduleWithRunLoop(stream,
                                     CFRunLoopGetCurrent(),
                                     kCFRunLoopDefaultMode);
    FSEventStreamStart(stream);
}

- (void)reloadPaths:(NSArray *)paths {
    for (NSString *path in paths)
        if ([path hasPrefix:@".git/"]) {
            cachedBranch = nil;
            break;
        }

    NSDictionary *info = [NSDictionary dictionaryWithObject:paths forKey:XTPathsKey];

    [[NSNotificationCenter defaultCenter] postNotificationName:XTRepositoryChangedNotification object:self userInfo:info];
}

// A convenience method for adding to the default notification center.
- (void)addReloadObserver:(id)observer selector:(SEL)selector {
    [[NSNotificationCenter defaultCenter] addObserver:observer selector:selector name:XTRepositoryChangedNotification object:self];
}

int event = 0;

void fsevents_callback(ConstFSEventStreamRef streamRef,
                       void *userData,
                       size_t numEvents,
                       void *eventPaths,
                       const FSEventStreamEventFlags eventFlags[],
                       const FSEventStreamEventId eventIds[]){
    XTRepository *repo = (__bridge XTRepository *)userData;

    ++event;

    NSMutableArray *paths = [NSMutableArray arrayWithCapacity:numEvents];
    for (size_t i = 0; i < numEvents; i++) {
        NSString *path = [(__bridge NSArray *) eventPaths objectAtIndex:i];
        NSRange r = [path rangeOfString:@".git" options:NSBackwardsSearch];

        path = [path substringFromIndex:r.location];
        [paths addObject:path];
        NSLog(@"fsevent #%d\t%@", event, path);
    }

    [repo reloadPaths:paths];
}

@end
