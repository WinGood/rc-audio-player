#import "RCPlayer.h"
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define StringFromBOOL(b) ((b) ? @"YES" : @"NO")

@implementation RCPlayer

- (void)pluginInitialize
{
    // Playback audio in background mode
    audioSession = [AVAudioSession sharedInstance];
    BOOL ok;
    NSError *setCategoryError = nil;
    ok = [audioSession setCategory:AVAudioSessionCategoryPlayback error:&setCategoryError];
    if (!ok) {
        //        NSLog(@"RCPlayer setCategoryError: %s%@", __PRETTY_FUNCTION__, setCategoryError);
    }

    [audioSession setMode:AVAudioSessionModeDefault error:nil];
    [audioSession setActive:YES error:nil];

    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    //    NSNumber *shouldScrub = [NSNumber numberWithBool:YES];
    //    [[[MPRemoteCommandCenter sharedCommandCenter] changePlaybackPositionCommand]
    //     performSelector:@selector(setCanBeControlledByScrubbing:) withObject:shouldScrub];

    // Set controls
    [commandCenter.seekBackwardCommand setEnabled:YES];
    [commandCenter.previousTrackCommand setEnabled:YES];
    [commandCenter.nextTrackCommand setEnabled:YES];
    [commandCenter.skipBackwardCommand setEnabled:YES];
    [commandCenter.skipForwardCommand setEnabled:YES];

    // Listeners for events from NowPlaying widget
    [commandCenter.playCommand addTarget:self action:@selector(onPlay:)];
    [commandCenter.pauseCommand addTarget:self action:@selector(onPause:)];
    [commandCenter.nextTrackCommand addTarget:self action:@selector(onNextTrack:)];
    [commandCenter.previousTrackCommand addTarget:self action:@selector(onPreviousTrack:)];
    [commandCenter.changePlaybackPositionCommand addTarget:self action:@selector(onChangePlayback:)];

    // init variables
    queue = [[NSMutableArray alloc] init];
    needAddToQueueWhenItWillBeInited = [[NSMutableArray alloc] init];
    playerIsPlaying = false;
    playerShouldPlayWhenItWillBeReady = false;
    queueWasInited = false;
    queuePointer = 0;

    // init AVQueuePlayerPrevious
    player = [[AVQueuePlayerPrevious alloc] init];
    player.allowsExternalPlayback = false;
    player.actionAtItemEnd = AVPlayerActionAtItemEndPause;

    [player addObserver:self forKeyPath:@"actionAtItemEnd" options:NSKeyValueObservingOptionInitial context:nil];

    // Listener for event that fired when song has stopped playing
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:player.currentItem];

    // init MPNowPlayingInfoCenter
    center = [MPNowPlayingInfoCenter defaultCenter];

    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"10.0")) {
        player.automaticallyWaitsToMinimizeStalling = false;
    }

    // --- PLAYER LISTENERS ---

    // Rate, play/pause state
    [player addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:nil];

    // Listener for updating elapsed time
    __block RCPlayer *that = self;
    __block AVQueuePlayerPrevious *currentPlayer = player;
    CMTime interval = CMTimeMakeWithSeconds(1.0, NSEC_PER_SEC);

    currentTimeObserver = [player addPeriodicTimeObserverForInterval:interval queue:NULL usingBlock:^(CMTime time) {
        CMTime audioCurrentTime = currentPlayer.currentTime;
        int audioCurrentTimeSeconds = CMTimeGetSeconds(audioCurrentTime);
        NSString *elapsed = [[NSNumber numberWithInteger:audioCurrentTimeSeconds] stringValue];

        if (audioCurrentTimeSeconds < 0) {
            [that sendDataToJS:@{@"currentTime": @"0"}];
        } else {
            [that sendDataToJS:@{@"currentTime": elapsed}];
        }

        //        NSLog(@"RCPlayer: was update current time of song %@", elapsed);
    }];
}

# pragma mark - Player methods

- (void)initQueue:(CDVInvokedUrlCommand*)command
{
    [self reset:nil];
    NSDictionary *initSongDict = [command.arguments objectAtIndex:0];
    NSArray *initQueue = [initSongDict valueForKeyPath:@"queue"];

    // filling empty songs
    for (NSUInteger i = 0; i < [initQueue count]; i++) {
        [queue addObject:[RCPlayerSong alloc]];
    }

    if ([initQueue count] == 0) {
        queueWasInited = true;
        if ([needAddToQueueWhenItWillBeInited count]) {
            [self addSongsInQueue:needAddToQueueWhenItWillBeInited];
        }
        return;
    }
    int __block initedSongs = 0;
    __block RCPlayer *that = self;

    for (int i = 0; i < [initQueue count]; i++) {
        RCPlayerSong *song = [self getRCPlayerSongByInfo: initQueue[i]];
        AVURLAsset *audioAsset = [self getAudioAssetForSong:song];

        [audioAsset loadValuesAsynchronouslyForKeys:@[@"playable"] completionHandler:^()
         {
             dispatch_async(dispatch_get_main_queue(), ^
                            {
                                // add information about song in the queue
                                [queue replaceObjectAtIndex:i withObject:song];

                                AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:audioAsset];
                                NSInteger previousIndex = i - 1;

                                if (previousIndex != -1) {
                                    if ([player.itemsForPlayer count] > previousIndex) {
                                        AVPlayerItem *previousItem = [player.items objectAtIndex:previousIndex];
                                        [player insertItem:playerItem afterItem: previousItem];
                                    } else {
                                        [player insertItem:playerItem afterItem: nil];
                                    }
                                } else {
                                    if ([player.itemsForPlayer count] > 0) {
                                        AVPlayerItem *firstItem = [player.itemsForPlayer objectAtIndexedSubscript:0];
                                        [player insertItem:playerItem afterItem:firstItem];
                                        [player removeItem:firstItem];
                                        [player insertItem:firstItem afterItem:playerItem];
                                    } else {
                                        [player insertItem:playerItem afterItem: nil];
                                    }
                                }

                                playerItem.accessibilityValue = song.code;
                                [playerItem addObserver:that forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:nil];
                                [playerItem addObserver:that forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionInitial context:nil];

                                initedSongs++;

                                if (initedSongs == [initQueue count]) {
                                    //                                    NSLog(@"queueWasInited true");
                                    queueWasInited = true;
                                    if ([needAddToQueueWhenItWillBeInited count]) {
                                        [self addSongsInQueue:needAddToQueueWhenItWillBeInited];
                                    }
                                }
                            });
         }];
    }
}

- (void)add:(CDVInvokedUrlCommand*)command
{
    NSDictionary *initSongDict = [command.arguments objectAtIndex:0];
    NSArray *initQueue = [initSongDict valueForKeyPath:@"queue"];

    for (int i = 0; i < [initQueue count]; i++) {
        RCPlayerSong *song = [self getRCPlayerSongByInfo: initQueue[i]];
        [needAddToQueueWhenItWillBeInited addObject:song];
    }

    //    NSLog(@"indexInQueue indexInQueue - add");

    if (queueWasInited == true) {
        //        NSLog(@"indexInQueue indexInQueue - true");
        [self addSongsInQueue:needAddToQueueWhenItWillBeInited];
    } else {
        //        NSLog(@"indexInQueue indexInQueue - false");
    }
}

- (void)addSongsInQueue:(NSMutableArray<RCPlayerSong *>*)songs
{
    int startIndex = (int)[queue count];
    //    NSLog(@"indexInQueue songs: %lu", [songs count]);
    //    NSLog(@"indexInQueue startIndex: %d", startIndex);

    for (NSUInteger i = [queue count]; i < startIndex + [songs count]; i++) {
        //        NSLog(@"indexInQueue new item added");
        [queue addObject:[RCPlayerSong alloc]];
    }

    __block RCPlayer *that = self;

    for (int i = 0; i < [songs count]; i++) {
        int indexInQueue = startIndex + i;
        int previousIndex = indexInQueue - 1;

        RCPlayerSong *currentSong = songs[i];
        AVURLAsset *audioAsset = [self getAudioAssetForSong:currentSong];

        //        NSLog(@"indexInQueue: %d", indexInQueue);
        //        NSLog(@"indexInQueue currentSong url: %@", currentSong.url);

        [audioAsset loadValuesAsynchronouslyForKeys:@[@"playable"] completionHandler:^()
         {
             dispatch_async(dispatch_get_main_queue(), ^
                            {
                                AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:audioAsset];
                                [queue replaceObjectAtIndex:indexInQueue withObject:currentSong];

                                // TODO check this with multiple songs
                                if ([player.itemsForPlayer count] > previousIndex) {
                                    AVPlayerItem *previousItem = [player.itemsForPlayer objectAtIndex:previousIndex];
                                    [player insertItem:playerItem afterItem: previousItem];
                                } else {
                                    [player insertItem:playerItem afterItem: nil];
                                }

                                playerItem.accessibilityValue = currentSong.code;
                                [playerItem addObserver:that forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:nil];
                                [playerItem addObserver:that forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionInitial context:nil];

                                //                                NSLog(@"indexInQueue SONG WAS ADDED!!");
                            });
         }];
    }

    [needAddToQueueWhenItWillBeInited removeAllObjects];
}

- (void)removeTrack:(CDVInvokedUrlCommand*)command
{
    NSNumber *index = [command.arguments objectAtIndex:0];
    int removeByIndex = [index intValue];

    //    NSLog(@"removeTrack queue before count %lu", (unsigned long)[queue count]);

    for (int i = 0; i < [queue count]; i++) {
        if (i == removeByIndex) {
            [queue removeObjectAtIndex:i];
            //            NSLog(@"removeTrack was removed from queue");
        }
    }

    //    NSLog(@"removeTrack queue after count %lu", (unsigned long)[queue count]);
    //    NSLog(@"removeTrack removeByIndex %lu", (unsigned long)removeByIndex);
    //    NSLog(@"removeTrack count %lu", (unsigned long)[player.items count]);
    //    NSLog(@"removeTrack itemsForPlayer %lu", (unsigned long)[player.itemsForPlayer count]);

    for (int i = 0; i < [player.itemsForPlayer count]; i++) {
        if (i == removeByIndex) {
            AVPlayerItem *findedPlayerItem = player.itemsForPlayer[i];
            bool itIslastItem = [player.itemsForPlayer count] == 1;
            bool itIsCurrentItem = (player.currentItem.accessibilityValue == findedPlayerItem.accessibilityValue);

            if (itIsCurrentItem) {
                [player pause];
                [player.currentItem cancelPendingSeeks];
                [player.currentItem.asset cancelLoading];
                NSMutableDictionary *playInfo = [NSMutableDictionary dictionaryWithDictionary:[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo];
                [playInfo setObject:[NSNumber numberWithFloat:0.0f] forKey:MPNowPlayingInfoPropertyPlaybackRate];
                MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = playInfo;
            }

            if (itIslastItem == false) {
                [self removeObserversFromPlayerByItem:findedPlayerItem];
                [player removeItem:findedPlayerItem];
            } else {
                [self removeObserversFromPlayerItems];
                [player removeAllItems];
                MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = nil;
            }

            //            NSLog(@"removeTrack was removed from player");
        }
    }
}

- (void)replaceTrack:(CDVInvokedUrlCommand*)command
{
    //    NSLog(@"replaceTrack arguments - %@", command.arguments);
    NSNumber *index = [command.arguments objectAtIndex:0];
    NSDictionary *songInfo = [command.arguments objectAtIndex:1];
    RCPlayerSong *song = [self getRCPlayerSongByInfo:songInfo];

    int replaceByIndex = [index intValue];
    __block RCPlayer *that = self;

    // need to add in the end of queue
    if ([queue count] == replaceByIndex) {
        NSMutableArray *needToAdd = [[NSMutableArray alloc] initWithObjects:song, nil];
        [self addSongsInQueue:needToAdd];
    } else if ([queue count] > replaceByIndex && [player.itemsForPlayer count] > replaceByIndex) {
        AVURLAsset *audioAsset = [self getAudioAssetForSong:song];
        [audioAsset loadValuesAsynchronouslyForKeys:@[@"playable"] completionHandler:^()
         {
             dispatch_async(dispatch_get_main_queue(), ^
                            {
                                [queue insertObject:song atIndex:replaceByIndex];
                                AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:audioAsset];

                                if (replaceByIndex == 0) {
                                    if ([player.itemsForPlayer count] > 0) {
                                        AVPlayerItem *firstItem = [player.itemsForPlayer objectAtIndexedSubscript:0];

                                        [self removeObserversFromPlayerByItem:firstItem];

                                        [player insertItem:playerItem afterItem:firstItem];
                                        [player removeItem:firstItem];
                                        [player insertItem:firstItem afterItem:playerItem];
                                    } else {
                                        [player insertItem:playerItem afterItem: nil];
                                    }
                                } else {
                                    AVPlayerItem *previousItem = [player.itemsForPlayer objectAtIndexedSubscript:replaceByIndex - 1];
                                    [player insertItem:playerItem afterItem:previousItem];
                                }

                                playerItem.accessibilityValue = song.code;
                                [playerItem addObserver:that forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:nil];
                                [playerItem addObserver:that forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionInitial context:nil];
                            });
         }];
    }
}

- (void)playTrack:(CDVInvokedUrlCommand*)command
{
    NSString *shouldPlayCode = [command.arguments objectAtIndex:0];
    if ([queue count] == 0 || queueWasInited == false) {
        playerShouldPlayWhenItWillBeReady = true;
        shouldPlayWhenPlayerWillBeReady = shouldPlayCode;
        return;
    }
    [self play:shouldPlayCode];
}

- (void)play:(NSString*)shouldPlayCode
{
    //    NSLog(@"RCPlayer current queue: %@", queue);

    if (playerIsPlaying) {
        [player pause];
    }

    int findedIndex = [self getSongIndexInQueueByCode:shouldPlayCode];
    //    NSLog(@"RCPlayer findedIndex: %d", findedIndex);

    if (findedIndex != -1) {
        //        NSLog(@"RCPlayer playTrack: %@", queue);
        //        NSLog(@"RCPlayer playTrack index: %d", queuePointer);

        queuePointer = findedIndex;
        [self playAtIndex:queuePointer];
    } else {
        playerShouldPlayWhenItWillBeReady = true;
        shouldPlayWhenPlayerWillBeReady = shouldPlayCode;
    }
}

- (void)playAtIndex:(NSInteger)index
{
    int currentIndex = [player getIndex];

    if (currentIndex < index) {
        for (int i = currentIndex; i < index; i++) {
            [player advanceToNextItem];
        }
    } else if (currentIndex > index) {
        for (int i = currentIndex; i > index; i--) {
            [player playPreviousItem];
        }
    } else {
        [player play];
    }

    if (player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
        playerIsPlaying = true;
        playerShouldPlayWhenItWillBeReady = false;
        shouldPlayWhenPlayerWillBeReady = @"";
    } else {
        playerShouldPlayWhenItWillBeReady = true;
        shouldPlayWhenPlayerWillBeReady = player.currentItem.accessibilityValue;
    }

    [self sendDuration];
    [self sendBuffetingProgressForCurrentPlayerItem];
    [self updateMusicControls];
}

- (void)pauseTrack:(CDVInvokedUrlCommand*)command
{
    if ([queue count] > 0) {
        [player pause];
        [self updateMusicControls];
        // TODO for what it?
        [audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    }
}

- (int)getSongIndexInQueueByCode:(NSString*)code
{
    int index = -1;
    for (int i = 0; i < [queue count]; i++) {
        if (queue[i].code != nil && queue[i].code != NULL) {
            if ([queue[i].code isEqualToString:code]) {
                index = i;
            }
        }
    }
    return index;
}

- (void)sendBuffetingProgressForCurrentPlayerItem
{
    if (player.currentItem) {
        NSArray *loadedTimeRanges = [[player currentItem] loadedTimeRanges];
        if ([loadedTimeRanges count] > 0) {
            CMTimeRange timeRange = [[loadedTimeRanges objectAtIndex:0] CMTimeRangeValue];
            Float64 startSeconds = CMTimeGetSeconds(timeRange.start);
            Float64 durationSeconds = CMTimeGetSeconds(timeRange.duration);

            float percent = (startSeconds + durationSeconds) / CMTimeGetSeconds(player.currentItem.duration) * 100;
            NSString *percentString = [[NSNumber numberWithFloat:percent] stringValue];

            [self sendDataToJS:@{@"bufferProgress": percentString}];

            //            NSLog(@"RCPlayer song buffering progress %@", percentString);

            if (percent >= 100) {
                //                NSLog(@"RCPlayer: loadedTimeRanges remove listener");
                @try {
                    [player.currentItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
                } @catch (id anException) {}
            }
        }
    }
}

// TODO sometimes doesn't work correctly
- (void)setCurrentTimeForPlayer:(int)seconds {
    // seek time in player
    NSLog(@"RCPlayer setCurrentTimeForPlayer %d", seconds);
    CMTime seekTime = CMTimeMakeWithSeconds(seconds, 100000);
    int audioCurrentTimeSeconds = CMTimeGetSeconds(seekTime);
    NSString *currentTime = [[NSNumber numberWithInteger:audioCurrentTimeSeconds] stringValue];
    [player seekToTime:seekTime toleranceBefore:seekTime toleranceAfter:seekTime];
    [player seekToTime:seekTime completionHandler:^(BOOL finished) {
        [self sendDataToJS:@{@"currentTime": currentTime}];
        if (playerIsPlaying) {
            [player play];
        }

        // update playnow widget
        NSMutableDictionary *playInfo = [NSMutableDictionary dictionaryWithDictionary:[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo];
        [playInfo setObject:currentTime forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
        center.nowPlayingInfo = playInfo;
    }];
}

- (void)reset:(CDVInvokedUrlCommand*)command
{
    //    NSLog(@"RCPlayer reset");

    [player pause];
    [player.currentItem cancelPendingSeeks];
    [player.currentItem.asset cancelLoading];

    [self removeObserversFromPlayerItems];
    [player removeAllItems];

    queuePointer = 0;
    queueWasInited = false;
    playerShouldPlayWhenItWillBeReady = false;

    [queue removeAllObjects];
    [needAddToQueueWhenItWillBeInited removeAllObjects];

    center.nowPlayingInfo = nil;

    [self sendDataToJS:@{@"currentTime": @"0"}];
    [self sendDataToJS:@{@"bufferProgress": @"0"}];
}

- (void)removeObserversFromPlayerItems
{
    for (int i = 0; i < [player.itemsForPlayer count]; i++) {
        @try {
            AVPlayerItem *currentItem = [player.itemsForPlayer objectAtIndexedSubscript:i];
            [currentItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
            [currentItem removeObserver:self forKeyPath:@"status" context:nil];
        } @catch (id anException) {}
    }

    for (int i = 0; i < [player.items count]; i++) {
        @try {
            AVPlayerItem *currentItem = [player.items objectAtIndexedSubscript:i];
            [currentItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
            [currentItem removeObserver:self forKeyPath:@"status" context:nil];
        } @catch (id anException) {}
    }

    [self sendDataToJS:@{@"bufferProgress": @"0"}];
}

- (void)removeObserversFromPlayerByItem:(AVPlayerItem*)playerItem
{
    @try {
        [playerItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
        [playerItem removeObserver:self forKeyPath:@"status" context:nil];

        for (int i = 0; i < [player.items count]; i++) {
            if (player.items[i].accessibilityValue == playerItem.accessibilityValue) {
                [player.items[i] removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
                [player.items[i] removeObserver:self forKeyPath:@"status" context:nil];
            }
        }
    } @catch (id anException) {}
}

- (AVURLAsset*)getAudioAssetForSong:(RCPlayerSong*)song
{
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    [headers setObject:@"Your UA" forKey:@"User-Agent"];
    NSURL *soundUrl = [[NSURL alloc] initWithString:song.url];
    AVURLAsset *audioAsset = [AVURLAsset URLAssetWithURL:soundUrl options:@{@"AVURLAssetHTTPHeaderFieldsKey" : headers}];
    return audioAsset;
}

-(RCPlayerSong*)getRCPlayerSongByInfo:(NSDictionary*)songInfo
{
    RCPlayerSong *song = [[RCPlayerSong alloc] init];

    [song setCode:songInfo[@"code"]];
    [song setArtist:songInfo[@"artist"]];
    [song setTitle:songInfo[@"title"]];
    [song setAlbum:songInfo[@"album"]];
    [song setCover:songInfo[@"cover"]];
    [song setUrl:songInfo[@"url"]];

    return song;
}

# pragma mark - MPRemoteCommandCenter listeners

// TODO read something about it
- (MPRemoteCommandHandlerStatus)setCanBeControlledByScrubbing:(MPChangePlaybackPositionCommandEvent*)event {
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)onChangePlayback:(MPChangePlaybackPositionCommandEvent*)event {
    //    NSLog(@"RCPlayer: changedPlaybackPosition to %f", event.positionTime);

    // Songs are loading async, rewind will work only for current song
    CMTime seekTime = CMTimeMakeWithSeconds(event.positionTime, 100000);
    int audioCurrentTimeSeconds = CMTimeGetSeconds(seekTime);
    NSString *elapsed = [[NSNumber numberWithInteger:audioCurrentTimeSeconds] stringValue];

    // seek to in player
    [self setCurrentTimeForPlayer:audioCurrentTimeSeconds];

    // update playnow widget
    NSMutableDictionary *playInfo = [NSMutableDictionary dictionaryWithDictionary:[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo];
    [playInfo setObject:elapsed forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    center.nowPlayingInfo = playInfo;

    return MPRemoteCommandHandlerStatusSuccess;
}

- (void)onPlay:(MPRemoteCommandHandlerStatus*)event {
    [player play];
    playerIsPlaying = true;

    [self updateMusicControls];
    [self sendRemoteControlEventWithQueuePointer:@"play"];
}

- (void)onPause:(MPRemoteCommandHandlerStatus*)event {
    [player pause];
    playerIsPlaying = false;

    [self updateMusicControls];
    [self sendRemoteControlEventWithQueuePointer:@"pause"];
}

- (int)randomNumberBetween:(int)min maxNumber:(int)max
{
    return min + arc4random_uniform((uint32_t)(max - min + 1));
}

- (void)onNextTrack:(MPRemoteCommandHandlerStatus*)event {
    if (shuffling == 1) {
        if ([queue count] == 1) {
            queuePointer = 0;
            [self playAtIndex:queuePointer];
        } else {
            int newIndex = queuePointer;
            while(queuePointer == newIndex) {
                int count = (int)[queue count];
                newIndex = [self randomNumberBetween:0 maxNumber:count - 1];
            }
            queuePointer = newIndex;
            [self playAtIndex:queuePointer];
        }
    } else {
        if (queuePointer < ([queue count] - 1)) {
            queuePointer = queuePointer + 1;
            [self playAtIndex:queuePointer];
        } else if (queuePointer == [queue count] - 1) {
            queuePointer = 0;
            [self playAtIndex:queuePointer];
        }
    }

    //    NSLog(@"RCPlayer current index: %d", queuePointer);
    [self sendRemoteControlEventWithQueuePointer:@"nextTrack"];
}

- (void)onPreviousTrack:(MPRemoteCommandHandlerStatus*)event {
    if ([queue count] > 0) {
        CMTime audioCurrentTime = player.currentTime;
        int audioCurrentTimeSeconds = CMTimeGetSeconds(audioCurrentTime);

        if (audioCurrentTimeSeconds > 4) {
            // Restart to play current song
            [self setCurrentTimeForPlayer:0];
        } else {
            if (queuePointer == 0) {
                int count = (int)[queue count];
                queuePointer = count - 1;
                [self playAtIndex:queuePointer];
            } else {
                queuePointer = queuePointer - 1;
                [self playAtIndex:queuePointer];
            }
        }
    }

    NSLog(@"RCPlayer current index: %d", queuePointer);
    [self sendRemoteControlEventWithQueuePointer:@"previousTrack"];
}

# pragma mark - MPNowPlayingInfoCenter

- (void)updateMusicControls {
    if (queue[queuePointer] == nil) return;

    NSString *artist = [queue objectAtIndex:queuePointer].artist;
    NSString *title = [queue objectAtIndex:queuePointer].title;
    NSString *album = [queue objectAtIndex:queuePointer].album;
    NSString *cover = [queue objectAtIndex:queuePointer].cover;

    CMTime audioDuration = player.currentItem.asset.duration;
    CMTime audioCurrentTime = player.currentTime;

    int audioDurationSeconds = CMTimeGetSeconds(audioDuration);
    int audioCurrentTimeSeconds = CMTimeGetSeconds(audioCurrentTime);

    NSString *duration = [[NSNumber numberWithInteger:audioDurationSeconds] stringValue];
    NSString *elapsed = [[NSNumber numberWithInteger:audioCurrentTimeSeconds] stringValue];

    //    NSLog(@"RCPlayer updateMusicControls: duration %@", duration);
    //    NSLog(@"RCPlayer updateMusicControls: elapsed %@", elapsed);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        UIImage *image = nil;
        // check whether cover path is present
        if (![cover isEqual: @""]) {
            // cover is remote file
            if ([cover hasPrefix: @"http://"] || [cover hasPrefix: @"https://"]) {
                NSURL *imageURL = [NSURL URLWithString:cover];
                NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
                image = [UIImage imageWithData:imageData];
            }
            // cover is full path to local file
            else if ([cover hasPrefix: @"file://"]) {
                NSString *fullPath = [cover stringByReplacingOccurrencesOfString:@"file://" withString:@""];
                BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:fullPath];
                if (fileExists) {
                    image = [[UIImage alloc] initWithContentsOfFile:fullPath];
                }
            }
            // cover is relative path to local file
            else {
                NSString *basePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                NSString *fullPath = [NSString stringWithFormat:@"%@%@", basePath, cover];
                BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:fullPath];
                if (fileExists) {
                    image = [UIImage imageNamed:fullPath];
                }
            }
        }
        else {
            // default named "no-image"
            image = [UIImage imageNamed:@"no-image"];
        }

        // check whether image is loaded
        CGImageRef cgref = [image CGImage];
        CIImage *cim = [image CIImage];
        if (cim != nil || cgref != NULL) {
            //            NSLog(@"RCPlayer is playing status: %@", [[NSNumber numberWithBool:playerIsPlaying] stringValue]);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (NSClassFromString(@"MPNowPlayingInfoCenter")) {
                    MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithImage: image];
                    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                                                           artist, MPMediaItemPropertyArtist,
                                                                           title, MPMediaItemPropertyTitle,
                                                                           album, MPMediaItemPropertyAlbumTitle,
                                                                           artwork, MPMediaItemPropertyArtwork,
                                                                           duration, MPMediaItemPropertyPlaybackDuration,
                                                                           elapsed, MPNowPlayingInfoPropertyElapsedPlaybackTime,
                                                                           [NSNumber numberWithFloat:(playerIsPlaying ? 1.0f : 0.0f)], MPNowPlayingInfoPropertyPlaybackRate, nil];
                }
            });
        }
    });
}


#pragma mark - JS part

// these methods can be triggered from js code

- (void)setShuffling:(CDVInvokedUrlCommand*)command
{
    NSNumber *value = [command.arguments objectAtIndex:0];
    if ([value isKindOfClass:[NSNull class]]) return;
    shuffling = [value intValue];
    //    NSLog(@"shuffling - %d", shuffling);
}

- (void)setCurrentTimeJS:(CDVInvokedUrlCommand*)command
{
    NSNumber *selectedTime = [command.arguments objectAtIndex:0];
    if ([selectedTime isKindOfClass:[NSNull class]]) return;

    //    NSLog(@"RCPlayer setCurrentTimeJS, %@", selectedTime);
    [self setCurrentTimeForPlayer:[selectedTime intValue]];
}

// Get id for JS callback
// TODO check this method, I can't find mentions
- (void)setWatcherFromJS: (CDVInvokedUrlCommand*) command {
    subscribeCallbackID = command.callbackId;
}

- (void)sendRemoteControlEventWithQueuePointer:(NSString*)event
{
    NSString *pointer = [[NSNumber numberWithInteger:queuePointer] stringValue];
    [self sendDataToJS:@{@"event": @{@"name": event, @"index": pointer}}];
}

// Send any data back to JS env through subscribe callback
- (void) sendDataToJS: (NSDictionary*) dict {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options: 0 error: nil];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    CDVPluginResult *plresult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonString];
    [plresult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:plresult callbackId:subscribeCallbackID];
}

// Send duration to JS as soon as possible
- (void)sendDuration
{
    if (player.currentItem) {
        CMTime audioDuration = player.currentItem.asset.duration;
        int audioDurationSeconds = CMTimeGetSeconds(audioDuration);
        NSString *duration = [[NSNumber numberWithInteger:audioDurationSeconds] stringValue];
        [self sendDataToJS:@{@"duration": duration}];
    }
}

#pragma mark - AVPlayer events listeners

// TODO not working for iOS 11, in background
-(void)itemDidFinishPlaying:(NSNotification *)notification {
    [self pauseTrack:nil];
    [self setCurrentTimeForPlayer:0];
    [self sendDataToJS:@{@"itemDidFinish": @"true"}];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    //    NSLog(@"observeValueForKeyPath %@", keyPath);

    if ([keyPath isEqualToString:@"status"] && playerShouldPlayWhenItWillBeReady) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        if ([item.accessibilityValue isEqualToString:shouldPlayWhenPlayerWillBeReady]) {
            //            NSLog(@"observeValueForKeyPath AVPlayerItemStatusReadyToPlay");
            if (player.currentItem && shouldPlayWhenPlayerWillBeReady) {
                if ([player.currentItem.accessibilityValue isEqualToString:shouldPlayWhenPlayerWillBeReady]) {
                    [player play];
                    [self updateMusicControls];
                } else {
                    [self play:shouldPlayWhenPlayerWillBeReady];
                }
            }
        }
        //        NSLog(@"observeValueForKeyPath item code: %@", item.accessibilityValue);
    }

    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        AVPlayerItem *currentItem = player.currentItem;

        if ((item == currentItem) && (item.status == AVPlayerItemStatusReadyToPlay)) {
            [self sendDuration];
        }
    }

    // Progress of buffering audio
    if(object == player.currentItem && [keyPath isEqualToString:@"loadedTimeRanges"]) {
        NSArray *loadedTimeRanges = [[player currentItem] loadedTimeRanges];
        if ([loadedTimeRanges count] > 0) {
            CMTimeRange timeRange = [[loadedTimeRanges objectAtIndex:0] CMTimeRangeValue];
            Float64 startSeconds = CMTimeGetSeconds(timeRange.start);
            Float64 durationSeconds = CMTimeGetSeconds(timeRange.duration);

            float percent = (startSeconds + durationSeconds) / CMTimeGetSeconds(player.currentItem.duration) * 100;
            NSString *percentString = [[NSNumber numberWithFloat:percent] stringValue];

            [self sendDataToJS:@{@"bufferProgress": percentString}];

            //            NSLog(@"RCPlayer song buffering progress %@", percentString);

            if (percent >= 100) {
                //                NSLog(@"RCPlayer: loadedTimeRanges remove listener");
                @try {
                    [player.currentItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
                } @catch (id anException) {}
            }
        }
    }

    if ([keyPath isEqualToString:@"rate"]) {
        float rate = [change[NSKeyValueChangeNewKey] floatValue];
        //        NSLog(@"RCPlayer changed rate");
        if (rate == 0.0) {
            // Playback stopped
            playerIsPlaying = false;
        } else if (rate == 1.0) {
            // Normal playback
            playerIsPlaying = true;
        } else if (rate == -1.0) {
            // Reverse playback
            playerIsPlaying = false;
        }
    }
}

-(void)dealloc {
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"receivedEvent" object:nil];
}

@end