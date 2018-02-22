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
        NSLog(@"RCPlayer setCategoryError: %s%@", __PRETTY_FUNCTION__, setCategoryError);
    }
    
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    NSNumber *shouldScrub = [NSNumber numberWithBool:YES];
    [[[MPRemoteCommandCenter sharedCommandCenter] changePlaybackPositionCommand]
     performSelector:@selector(setCanBeControlledByScrubbing:) withObject:shouldScrub];
    
    // Listeners for events from NowPlaying widget
    [commandCenter.changePlaybackPositionCommand addTarget:self action:@selector(onChangePlayback:)];
    [commandCenter.playCommand addTarget:self action:@selector(onPlay:)];
    [commandCenter.pauseCommand addTarget:self action:@selector(onPause:)];
    [commandCenter.nextTrackCommand addTarget:self action:@selector(onNextTrack:)];
    [commandCenter.previousTrackCommand addTarget:self action:@selector(onPreviousTrack:)];
    
    // Listener for event that fired when song has stopped playing
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:player.currentItem];
    
    // init variables
    queue = [[NSMutableArray alloc] init];
    needAddToQueueWhenItWillBeInited = [[NSMutableArray alloc] init];
    needRemoveFromQueueWhenItWillBeInited = [[NSMutableArray alloc] init];
    playerIsPlaying = false;
    playerShouldPlayWhenItWillBeReady = false;
    queueWasInited = false;
    queuePointer = 0;
    
    // init AVQueuePlayerPrevious
    player = [[AVQueuePlayerPrevious alloc] init];
    player.allowsExternalPlayback = false;
    
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
        
        NSLog(@"RCPlayer: was update current time of song - %@", elapsed);
    }];
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

# pragma mark - Player methods

- (void)initQueue:(CDVInvokedUrlCommand*)command
{
    [self reset:nil];
    // TODO for testing period
    //    needLoopSong = [[NSNumber alloc] initWithInt:1];
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
                                    if ([player.items count] > previousIndex) {
                                        AVPlayerItem *previousItem = [player.items objectAtIndex:previousIndex];
                                        [player insertItem:playerItem afterItem: previousItem];
                                    } else {
                                        [player insertItem:playerItem afterItem: nil];
                                    }
                                } else {
                                    if ([player.items count] > 0) {
                                        AVPlayerItem *firstItem = [player.items objectAtIndexedSubscript:0];
                                        [player insertItem:playerItem afterItem:firstItem];
                                        [player removeItem:firstItem];
                                        [player insertItem:firstItem afterItem:playerItem];
                                    } else {
                                        [player insertItem:playerItem afterItem: nil];
                                    }
                                }
                                
                                playerItem.accessibilityValue = song.code;
                                [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:nil];
                                [playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionInitial context:nil];
                                
                                if (audioAsset.URL.absoluteString == [initQueue objectAtIndex:queuePointer][@"url"]) {
                                    [self sendDuration];
                                }
                                
                                initedSongs++;
                                
                                if (initedSongs == [initQueue count]) {
                                    NSLog(@"queueWasInited true");
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
    
    NSLog(@"indexInQueue indexInQueue - add");
    
    if (queueWasInited == true) {
        NSLog(@"indexInQueue indexInQueue - true");
        [self addSongsInQueue:needAddToQueueWhenItWillBeInited];
    } else {
        NSLog(@"indexInQueue indexInQueue - false");
    }
}

- (void)addSongsInQueue:(NSMutableArray<RCPlayerSong *>*)songs
{
    NSUInteger startIndex = [queue count];
    NSLog(@"indexInQueue songs: %lu", [songs count]);
    NSLog(@"indexInQueue startIndex: %lu", (unsigned long)startIndex);
    
    for (NSUInteger i = [queue count]; i < startIndex + [songs count]; i++) {
        NSLog(@"indexInQueue new item added");
        [queue addObject:[RCPlayerSong alloc]];
    }
    
    for (int i = 0; i < [songs count]; i++) {
        int indexInQueue = startIndex + i;
        int previousIndex = indexInQueue - 1;
        
        RCPlayerSong *currentSong = songs[i];
        AVURLAsset *audioAsset = [self getAudioAssetForSong:currentSong];
        
        NSLog(@"indexInQueue: %d", indexInQueue);
        NSLog(@"indexInQueue currentSong url: %@", currentSong.url);
        
        [audioAsset loadValuesAsynchronouslyForKeys:@[@"playable"] completionHandler:^()
         {
             dispatch_async(dispatch_get_main_queue(), ^
                            {
                                AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:audioAsset];
                                [queue replaceObjectAtIndex:indexInQueue withObject:currentSong];
                                
                                // TODO check this with multiple songs
                                if ([player.items count] > previousIndex) {
                                    AVPlayerItem *previousItem = [player.items objectAtIndex:previousIndex];
                                    [player insertItem:playerItem afterItem: previousItem];
                                } else {
                                    [player insertItem:playerItem afterItem: nil];
                                }
                                
                                playerItem.accessibilityValue = currentSong.code;
                                [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:nil];
                                [playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionInitial context:nil];
                                
                                NSLog(@"indexInQueue SONG WAS ADDED!!");
                            });
             
         }];
    }
    
    [needAddToQueueWhenItWillBeInited removeAllObjects];
}

// replaceSongQueue
- (void)removeTrack:(CDVInvokedUrlCommand*)command
{
    
}

// replaceSongQueue
- (void)replaceTrack:(CDVInvokedUrlCommand*)command
{
    NSLog(@"remove arguments - %@", command.arguments);
    NSNumber *startNumber = [command.arguments objectAtIndex:0];
    NSNumber *endNumber = [command.arguments objectAtIndex:1];
    NSDictionary *songInfo = [command.arguments objectAtIndex:2];
    int start = [startNumber intValue];
    int end = [endNumber intValue];
    RCPlayerSong *song = [[RCPlayerSong alloc] init];
    [song setCode:songInfo[@"code"]];
    [song setArtist:songInfo[@"artist"]];
    [song setTitle:songInfo[@"title"]];
    [song setAlbum:songInfo[@"album"]];
    [song setCover:songInfo[@"cover"]];
    [song setUrl:songInfo[@"url"]];
    
    __block RCPlayer *that = self;
    
    NSLog(@"remove songInfo %@", songInfo);
    NSLog(@"remove start %d", start);
    NSLog(@"remove end %d",  end);
    
    if (start >= 0) {
        if (([player.items count] > start) && ([queue count] > start)) {
            for (int i = 0; i < [player.items count]; i++) {
                if (i == start) {
                    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
                    [headers setObject:@"Your UA" forKey:@"User-Agent"];
                    NSURL *soundUrl = [[NSURL alloc] initWithString:song.url];
                    AVURLAsset *audioAsset = [AVURLAsset URLAssetWithURL:soundUrl options:@{@"AVURLAssetHTTPHeaderFieldsKey" : headers}];
                    AVPlayerItem *needToReplaceItem = [player.items objectAtIndexedSubscript:i];
                    
                    @try {
                        [needToReplaceItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
                        [needToReplaceItem removeObserver:self forKeyPath:@"status" context:nil];
                    } @catch (id anException) {}
                    
                    [audioAsset loadValuesAsynchronouslyForKeys:@[@"playable"] completionHandler:^()
                     {
                         dispatch_async(dispatch_get_main_queue(), ^
                                        {
                                            AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:audioAsset];
                                            [queue replaceObjectAtIndex:i withObject:song];
                                            
                                            [player insertItem:playerItem afterItem:needToReplaceItem];
                                            [player removeItem:needToReplaceItem];
                                            
                                            playerItem.accessibilityValue = song.code;
                                            [playerItem addObserver:that forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:nil];
                                            [playerItem addObserver:that forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionInitial context:nil];
                                            
                                            NSLog(@"SONG WAS REPLACED by index %d", i);
                                        });
                         
                     }];
                }
            }
        } else {
            [self addSongsInQueue:[[NSMutableArray alloc] initWithObjects:song, nil]];
        }
    }
}

- (void)playTrack:(CDVInvokedUrlCommand*)command
{
    NSString *shouldPlayCode = [command.arguments objectAtIndex:0];
    if ([queue count] == 0) return;
    [self play:shouldPlayCode];
}

- (void)play:(NSString*)shouldPlayCode
{
    NSLog(@"RCPlayer current queue: %@", queue);
    
    int findedIndex = [self getSongIndexInQueueByCode:shouldPlayCode];
    NSLog(@"RCPlayer findedIndex: %d", findedIndex);
    
    if (findedIndex != -1) {
        NSLog(@"RCPlayer playTrack: %@", queue);
        NSLog(@"RCPlayer playTrack index: %d", queuePointer);
        
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
            if ([queue[i].code containsString:code]) {
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
            
            NSLog(@"RCPlayer song buffering progress %@", percentString);
            
            if (percent >= 100) {
                NSLog(@"RCPlayer: loadedTimeRanges remove listener");
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
    NSLog(@"RCPlayer reset");
    
    [player pause];
    [player.currentItem cancelPendingSeeks];
    [player.currentItem.asset cancelLoading];
    
    [self removeObserversFromPlayerItems];
    
    for (int i = 0; i < [player.items count]; i++) {
        [player removeItem:player.items[i]];
    }
    
    needLoopSong = [NSNumber numberWithInteger:0];
    queuePointer = 0;
    queueWasInited = false;
    playerShouldPlayWhenItWillBeReady = false;
    
    [queue removeAllObjects];
    [needAddToQueueWhenItWillBeInited removeAllObjects];
    [needRemoveFromQueueWhenItWillBeInited removeAllObjects];
    
    center.nowPlayingInfo = nil;
    
    [self sendDataToJS:@{@"currentTime": @"0"}];
    [self sendDataToJS:@{@"bufferProgress": @"0"}];
    [self sendDataToJS:@{@"loop": needLoopSong}];
}

- (void)removeObserversFromPlayerItems
{
    for (int i = 0; i < [player.items count]; i++) {
        @try {
            AVPlayerItem *currentItem = [player.items objectAtIndexedSubscript:i];
            [currentItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
            [currentItem removeObserver:self forKeyPath:@"status" context:nil];
        } @catch (id anException) {}
    }
    
    [self sendDataToJS:@{@"bufferProgress": @"0"}];
}

# pragma mark - MPRemoteCommandCenter listeners

// TODO read something about it
- (MPRemoteCommandHandlerStatus)setCanBeControlledByScrubbing:(MPChangePlaybackPositionCommandEvent*)event {
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)onChangePlayback:(MPChangePlaybackPositionCommandEvent*)event {
    NSLog(@"RCPlayer: changedPlaybackPosition to %f", event.positionTime);
    
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
    [self sendRemoteControlEvent:@"play"];
}

- (void)onPause:(MPRemoteCommandHandlerStatus*)event {
    [player pause];
    playerIsPlaying = false;
    
    [self updateMusicControls];
    [self sendRemoteControlEvent:@"pause"];
}

- (void)onNextTrack:(MPRemoteCommandHandlerStatus*)event {
    if (queuePointer < ([queue count] - 1)) {
        queuePointer = queuePointer + 1;
        [self playAtIndex:queuePointer];
    }
    
    NSLog(@"RCPlayer current index: %d", queuePointer);
    [self sendRemoteControlEvent:@"nextTrack"];
}

- (void)onPreviousTrack:(MPRemoteCommandHandlerStatus*)event {
    if (queuePointer != 0) {
        queuePointer = queuePointer - 1;
        [self playAtIndex:queuePointer];
    }
    
    NSLog(@"RCPlayer current index: %d", queuePointer);
    [self sendRemoteControlEvent:@"previousTrack"];
}

# pragma mark - MPNowPlayingInfoCenter

- (void)updateMusicControls {
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
    
    NSLog(@"RCPlayer updateMusicControls: duration %@", duration);
    NSLog(@"RCPlayer updateMusicControls: elapsed %@", elapsed);
    
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
            NSLog(@"RCPlayer is playing status: %@", [[NSNumber numberWithBool:playerIsPlaying] stringValue]);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (NSClassFromString(@"MPNowPlayingInfoCenter")) {
                    MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithImage: image];
                    center.nowPlayingInfo = [NSDictionary dictionaryWithObjectsAndKeys:
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

- (void)setLoopJS:(CDVInvokedUrlCommand*)command
{
    needLoopSong = [command.arguments objectAtIndex:0];
    NSLog(@"RCPlayer setLoopJS: %@", needLoopSong);
    //    [self sendDataToJS:@{@"loop": needLoopSong}];
}

- (void)setCurrentTimeJS:(CDVInvokedUrlCommand*)command
{
    NSNumber *selectedTime = [command.arguments objectAtIndex:0];
    if ([selectedTime isKindOfClass:[NSNull class]]) return;
    
    NSLog(@"RCPlayer setCurrentTimeJS, %@", selectedTime);
    [self setCurrentTimeForPlayer:[selectedTime intValue]];
}

// Get id for JS callback
// TODO check this method, I can't find mentions
- (void) setWatcherFromJS: (CDVInvokedUrlCommand*) command {
    subscribeCallbackID = command.callbackId;
}

- (void)sendRemoteControlEvent:(NSString*)event
{
    NSLog(@"RCPlayer: Remote control event, %@", event);
    // Send event in JS env
    [self sendDataToJS:@{@"event": event}];
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
    CMTime audioDuration = player.currentItem.asset.duration;
    int audioDurationSeconds = CMTimeGetSeconds(audioDuration);
    NSString *duration = [[NSNumber numberWithInteger:audioDurationSeconds] stringValue];
    [self sendDataToJS:@{@"duration": duration}];
}

#pragma mark - AVPlayer events listeners

// TODO check this method
-(void)itemDidFinishPlaying:(NSNotification *) notification {
    [player pause];
    NSLog(@"RCPlayer song has stopped, is loop %@", needLoopSong);
    // If need loop current song
    if ([needLoopSong isEqualToNumber:[NSNumber numberWithInt:1]]) {
        [self setCurrentTimeForPlayer:0];
        [self playAtIndex:queuePointer];
    } else {
        [self sendDataToJS:@{@"currentTime": @"0"}];
        [self sendRemoteControlEvent:@"nextTrack"];
        if (queuePointer < ([queue count] - 1)) {
            queuePointer = queuePointer + 1;
            [self playAtIndex:queuePointer];
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    NSLog(@"observeValueForKeyPath %@", keyPath);
    
    if ([keyPath isEqualToString:@"status"] && playerShouldPlayWhenItWillBeReady) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        if ([item.accessibilityValue containsString:shouldPlayWhenPlayerWillBeReady]) {
            NSLog(@"observeValueForKeyPath AVPlayerItemStatusReadyToPlay");
            if ([player.currentItem.accessibilityValue containsString:shouldPlayWhenPlayerWillBeReady]) {
                [player play];
            } else {
                [self play:shouldPlayWhenPlayerWillBeReady];
            }
        }
        NSLog(@"observeValueForKeyPath item code: %@", item.accessibilityValue);
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
            
            NSLog(@"RCPlayer song buffering progress %@", percentString);
            
            if (percent >= 100) {
                NSLog(@"RCPlayer: loadedTimeRanges remove listener");
                @try {
                    [player.currentItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
                } @catch (id anException) {}
            }
        }
    }
    
    if ([keyPath isEqualToString:@"rate"]) {
        float rate = [change[NSKeyValueChangeNewKey] floatValue];
        NSLog(@"RCPlayer changed rate");
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

