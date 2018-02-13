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
    // TODO check this event
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:player.currentItem];
    
    playerIsPlaying = false;
    playerShouldPlayWhenItWillBeReady = false;
//    playerIsReadyToPlay = false;
    queuePointer = 0;
    
    // init AVQueuePlayerPrevious
    player = [[AVQueuePlayerPrevious alloc] init];
    player.allowsExternalPlayback = false;
    player.volume = 0.1f;
    
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
    
    // init MPNowPlayingInfoCenter
    center = [MPNowPlayingInfoCenter defaultCenter];
    
    // TODO for testing period
//    needLoopSong = [[NSNumber alloc] initWithInt:1];
}

# pragma mark - Player methods

// TODO buffering for songs doesnt' work

- (void)initQueue:(CDVInvokedUrlCommand*)command
{
    [self reset:nil];
    
    NSDictionary *initSongDict = [command.arguments objectAtIndex:0];
    NSArray *initQueue = [initSongDict valueForKeyPath:@"queue"];
    
    // recreate AVQueuePlayerPrevious
//    player = [[AVQueuePlayerPrevious alloc] init];
//    player.allowsExternalPlayback = false;
//
//    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"10.0")) {
//        player.automaticallyWaitsToMinimizeStalling = false;
//    }
//
//    // remove observers if they exist
//    @try {
////        [player removeObserver:self forKeyPath:@"status" context:nil];
//        [player removeObserver:self forKeyPath:@"rate" context:nil];
//        [player removeTimeObserver:currentTimeObserver];
//    } @catch(id anException) {
//
//    }
    
    // --- PLAYER LISTENERS ---
//    // Ready to play status
////    [player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
//
//    // Rate, play/pause state
//    [player addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:nil];
    
//    // Listener for updating elapsed time
//    __block RCPlayer *that = self;
//    __block AVQueuePlayerPrevious *currentPlayer = player;
//    CMTime interval = CMTimeMakeWithSeconds(1.0, NSEC_PER_SEC);
//
//    currentTimeObserver = [player addPeriodicTimeObserverForInterval:interval queue:NULL usingBlock:^(CMTime time) {
//        CMTime audioCurrentTime = currentPlayer.currentTime;
//        int audioCurrentTimeSeconds = CMTimeGetSeconds(audioCurrentTime);
//        NSString *elapsed = [[NSNumber numberWithInteger:audioCurrentTimeSeconds] stringValue];
//
//        [that sendDataToJS:@{@"currentTime": elapsed}];
//        NSLog(@"RCPlayer: was update current time of song - %@", elapsed);
//    }];
    
    queuePointer = 0;
    playerShouldPlayWhenItWillBeReady = false;
//    playerIsReadyToPlay = false;
    queue = [[NSMutableArray alloc] init];
    playerItems = [[NSMutableArray alloc] init];
    
    // TODO figure out how I can avoid it
    NSURL *emptySoundUrl = [[NSURL alloc] initWithString:@""];
    AVURLAsset *emptyAsset = [AVURLAsset URLAssetWithURL:emptySoundUrl options:nil];
    AVPlayerItem *playerItemEmpty = [[AVPlayerItem alloc] initWithAsset:emptyAsset];

    for (NSUInteger i = 0; i < [initQueue count]; i++) {
        [playerItems addObject:playerItemEmpty];
    }
    
    for (int i = 0; i < [initQueue count]; i++) {
        // shaping queue
        NSDictionary *songInfo = initQueue[i];
        RCPlayerSong *song = [[RCPlayerSong alloc] init];
        
        [song setCode:songInfo[@"code"]];
        [song setArtist:songInfo[@"artist"]];
        [song setTitle:songInfo[@"title"]];
        [song setAlbum:songInfo[@"album"]];
        [song setCover:songInfo[@"cover"]];
        [song setUrl:songInfo[@"url"]];
        
        // add information about song in the queue
        [queue addObject:song];
        
        NSMutableDictionary *headers = [NSMutableDictionary dictionary];
        [headers setObject:@"Your UA" forKey:@"User-Agent"];
        
        NSURL *soundUrl = [[NSURL alloc] initWithString:song.url];
        AVURLAsset *audioAsset = [AVURLAsset URLAssetWithURL:soundUrl options:@{@"AVURLAssetHTTPHeaderFieldsKey" : headers}];
        
        [audioAsset loadValuesAsynchronouslyForKeys:@[@"playable"] completionHandler:^()
        {
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                               NSInteger previousIndex = i - 1;
                               AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:audioAsset];
                               [playerItems replaceObjectAtIndex:i withObject:playerItem];
                               [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
                               
                               NSLog(@"Index: %d", i);
                               
                               if (previousIndex != -1) {
                                   // TODO wtf, how does it work?
                                   [player insertItem:playerItem afterItem: nil];
                               } else {
                                   if ([player.items count] > 0) {
                                       AVPlayerItem *firstItem = [player.items objectAtIndexedSubscript:0];
                                       NSLog(@"firstItem %@", firstItem);
                                       [player insertItem:playerItem afterItem:firstItem];
                                       [player removeItem:firstItem];
                                       [player insertItem:firstItem afterItem:playerItem];
                                   } else {
                                       [player insertItem:playerItem afterItem: nil];
                                   }
                               }
                               
                               if (i == 0) {
                                   // Listener for buffering progress
//                                   [playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
                               }
                               
                               if (audioAsset.URL.absoluteString == [initQueue objectAtIndex:queuePointer][@"url"]) {
                                   [self sendDuration];
                               }
                           });

        }];
    }
}

- (void)add:(CDVInvokedUrlCommand*)command
{
    // buffering progress
    // status
}

- (void)remove:(CDVInvokedUrlCommand*)command
{
    
}

- (void)playTrack:(CDVInvokedUrlCommand*)command
{
    NSString *shouldPlayCode = [command.arguments objectAtIndex:0];
    
    if ([queue count] == 0) return;
    int findedIndex = [self getSongIndexInQueueByCode:shouldPlayCode];
    if (findedIndex != -1) {
        if ([playerItems count] > findedIndex) {
            NSLog(@"findedIndex: %d", findedIndex);
            AVPlayerItem *findedItem = [playerItems objectAtIndexedSubscript:findedIndex];
            NSLog(@"findedItem %@", findedItem);
            bool itemWasFoundInPlayer = false;
            
            for (int i = 0; i < [player.items count]; i++) {
                if ([player.items containsObject:findedItem]) {
                    itemWasFoundInPlayer = true;
                }
            }
            
            if (findedItem.status != AVPlayerItemStatusReadyToPlay && itemWasFoundInPlayer == true) {
                NSLog(@"shouldPlayWhenPlayerWillBeReady");
                playerShouldPlayWhenItWillBeReady = true;
                shouldPlayWhenPlayerWillBeReady = shouldPlayCode;
            } else {
                [self play:shouldPlayCode];
            }
        } else {
            playerShouldPlayWhenItWillBeReady = true;
            shouldPlayWhenPlayerWillBeReady = shouldPlayCode;
        }
    }
    
    // TODO check if queue/player will be empty
    
//    [self play:shouldPlayCode];
}

- (void)play:(NSString*)shouldPlayCode
{
    NSString *currentPlayingSongCode = [queue objectAtIndex:queuePointer] ? [queue objectAtIndex:queuePointer].code : @"";
    
    playerShouldPlayWhenItWillBeReady = false;
    shouldPlayWhenPlayerWillBeReady = @"";
    
    NSLog(@"RCPlayer playTrack codes: %@, %@", currentPlayingSongCode, shouldPlayCode);
    NSLog(@"RCPlayer current queue: %@", queue);
    
    if (playerIsPlaying == false && currentPlayingSongCode == shouldPlayCode) {
        NSLog(@"RCPlayer: continue playing");
        playerIsPlaying = true;
        [player play];
        [self updateMusicControls];
    } else if (currentPlayingSongCode != shouldPlayCode) {
        int findedIndex = [self getSongIndexInQueueByCode:shouldPlayCode];
        NSLog(@"RCPlayer findedIndex: %d", findedIndex);
        
        if (findedIndex != -1) {
            NSLog(@"RCPlayer playTrack: %@", queue);
            NSLog(@"RCPlayer playTrack index: %d", queuePointer);
            
            queuePointer = findedIndex;
            [self playAtIndex:queuePointer];
        }
    } else {
        NSLog(@"RCPlayer: The same song");
    }
}

- (void)playAtIndex:(NSInteger)index
{
    [self removeObserversFromPlayerItems];
    
//    if ([player.items count] > index) {
//        NSArray<AVPlayerItem *> *copiedItems = [player.items copy];
//        int startIndex = (int)index;
//        [player removeAllItems];
//        for (int i = startIndex; i < copiedItems.count; i ++) {
//            AVPlayerItem *obj = [copiedItems objectAtIndexedSubscript:i];
//            if ([obj isKindOfClass:[AVPlayerItem class]]) {
////                if (obj.status == AVPlayerItemStatusReadyToPlay) {
//                    if ([player canInsertItem:obj afterItem:nil]) {
//                        [obj seekToTime:kCMTimeZero];
//                        [player insertItem:obj afterItem:nil];
//                        [player seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
//                            playerIsPlaying = true;
//                            [player play];
//                            [self sendDuration];
//                            [self updateMusicControls];
//                        }];
//                    }
////                }
//            }
//        }
//    }
    
    
    if ([playerItems count] > index) {
        [player removeAllItems];
        AVPlayerItem *obj = [playerItems objectAtIndexedSubscript:index];
        if ([obj isKindOfClass:[AVPlayerItem class]]) {
//            @try {
            NSURL *currentURL = [self urlOfPlayerItem:obj];
                if (currentURL.absoluteString != [[NSString alloc] initWithString:@""]) {
                    if ([player canInsertItem:obj afterItem:nil]) {
                        [player insertItem:obj afterItem:nil];
                        [player seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
                            playerIsPlaying = true;
                            [player play];
                            //            [player.currentItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
                            [self sendDuration];
                            [self updateMusicControls];
                        }];
                    }
                }
//            } @catch(id anException) {
            
//            }
        }
    }
}

-(NSURL *)urlOfPlayerItem:(AVPlayerItem *)item{
    if (![item.asset isKindOfClass:AVURLAsset.class]) return nil;
    return [(AVURLAsset *)item.asset URL];
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
        if (queue[i].code == code) {
            index = i;
        }
    }
    return index;
}

- (void)setCurrentTimeForPlayer:(int)seconds {
    // seek time in player
    NSLog(@"RCPlayer setCurrentTimeForPlayer %d", seconds);
    CMTime seekTime = CMTimeMakeWithSeconds(seconds, 100000);
    int audioCurrentTimeSeconds = CMTimeGetSeconds(seekTime);
    NSString *currentTime = [[NSNumber numberWithInteger:audioCurrentTimeSeconds] stringValue];
    
    [player seekToTime:seekTime];
    [self sendDataToJS:@{@"currentTime": currentTime}];
    
    // update playnow widget
    NSMutableDictionary *playInfo = [NSMutableDictionary dictionaryWithDictionary:[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo];
    [playInfo setObject:currentTime forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    center.nowPlayingInfo = playInfo;
}

- (void)reset:(CDVInvokedUrlCommand*)command
{
    NSLog(@"RCPlayer reset");
    
    [player pause];
    [player.currentItem cancelPendingSeeks];
    [player.currentItem.asset cancelLoading];
    
    [self removeObserversFromPlayerItems];
    [player removeItem:player.currentItem];
    
//    [player.currentItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
    
    needLoopSong = [NSNumber numberWithInteger:0];
    queuePointer = 0;
    
    queue = [[NSMutableArray alloc] init];
    playerItems = [[NSMutableArray alloc] init];
    
    center.nowPlayingInfo = nil;
    
    [self sendDataToJS:@{@"currentTime": @"0"}];
    [self sendDataToJS:@{@"bufferProgress": @"0"}];
    [self sendDataToJS:@{@"loop": needLoopSong}];
}

- (void)removeObserversFromPlayerItems
{
    for (int i = 0; i < [playerItems count]; i++) {
        @try {
            AVPlayerItem *currentItem = [playerItems objectAtIndexedSubscript:i];
            //            [currentItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
            [currentItem removeObserver:self forKeyPath:@"status" context:nil];
        } @catch(id anException) {
            
        }
    }
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
        int findedIndex = [self getSongIndexInQueueByCode:shouldPlayWhenPlayerWillBeReady];
        NSLog(@"observeValueForKeyPath findedIndex %d", findedIndex);
        if (findedIndex != -1) {
            if ([playerItems count] > findedIndex) {
                AVPlayerItem *findedItem = [playerItems objectAtIndexedSubscript:findedIndex];
                NSLog(@"observeValueForKeyPath findedItem %@", findedItem);
                
                if ([object containsObject:findedItem]) {
                    NSLog(@"observeValueForKeyPath should play");
                    if (findedItem.status == AVPlayerStatusReadyToPlay) {
                        if (playerShouldPlayWhenItWillBeReady) {
                            [self play:shouldPlayWhenPlayerWillBeReady];
                        }
                        NSLog(@"observeValueForKeyPath Ready to play");
                    } else if (findedItem.status == AVPlayerStatusFailed) {
                        // something went wrong. player.error should contain some information
                        NSLog(@"observeValueForKeyPath AVPlayerStatusFailed");
                    }
                }
            }
        }
    }
    
    // Progress of buffering audio
    if(object == player.currentItem && [keyPath isEqualToString:@"loadedTimeRanges"]) {
        NSArray *loadedTimeRanges = [[player currentItem] loadedTimeRanges];
        CMTimeRange timeRange = [[loadedTimeRanges objectAtIndex:0] CMTimeRangeValue];
        Float64 startSeconds = CMTimeGetSeconds(timeRange.start);
        Float64 durationSeconds = CMTimeGetSeconds(timeRange.duration);
        
        float percent = (startSeconds + durationSeconds) / CMTimeGetSeconds(player.currentItem.duration) * 100;
        NSString *percentString = [[NSNumber numberWithFloat:percent] stringValue];
        
        [self sendDataToJS:@{@"bufferProgress": percentString}];
        
        NSLog(@"RCPlayer song buffering progress %@", percentString);
        
        if (percent >= 100) {
            NSLog(@"RCPlayer: loadedTimeRanges remove listener");
            [player.currentItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
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
