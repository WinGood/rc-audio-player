#import "RCPlayer.h"
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

@implementation RCPlayer

static NSString *_artist;
static NSString *_title;
static NSString *_album;
static NSString *_cover;
static NSNumber *_isLoop;
static bool audioListenersApplied = false;
static bool songIsLoaded = false;
static bool songIsStopped = false;

static bool readyToPlay = false;
static bool readyToPlayFired = false;
static AVURLAsset *readyToPlayAsset;
static bool needPlaySong = false;
static bool passOneUpdateTick = false;

- (void)pluginInitialize
{
    // Playback audio in background mode
    audioSession = [AVAudioSession sharedInstance];
    BOOL ok;
    NSError *setCategoryError = nil;
    ok = [audioSession setCategory:AVAudioSessionCategoryPlayback error:&setCategoryError];
    if (!ok) {
        NSLog(@"%s setCategoryError=%@", __PRETTY_FUNCTION__, setCategoryError);
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.audioItem];
}

- (void)initSong:(CDVInvokedUrlCommand*)command
{
    // remove current audio if it's exist
    [self stop:nil];
    
    initCallbackID = command.callbackId;
    center = [MPNowPlayingInfoCenter defaultCenter];
    NSDictionary *initSongDict = [command.arguments objectAtIndex:0];

    // Queue
//    NSArray *initQueue = [initSongDict valueForKeyPath:@"queue"];
//
//    NSLog(@"Test %@", initQueue);
//
//    NSMutableArray *queue = [[NSMutableArray alloc] init];
//    for (int i = 0; i < [initQueue count]; i++) {
//        NSLog(@"Dict [%d]:%@", i, initQueue[i]);
//        [queue addObject:initQueue[i]];
//    }
//
//    AVQueuePlayer *player = [[AVQueuePlayer alloc] initWithItems:queue];
//
//    return;

    // Data from JS env
    _artist = initSongDict[@"artist"];
    _title = initSongDict[@"title"];
    _album = initSongDict[@"album"];
    _cover = initSongDict[@"cover"];

    NSURL *soundUrl = [[NSURL alloc] initWithString:initSongDict[@"url"]];
    AVURLAsset* audioAsset = [AVURLAsset URLAssetWithURL:soundUrl options:nil];

    songIsLoaded = false;
    readyToPlay = false;
    readyToPlayFired = false;
    needPlaySong = false;
    songIsStopped = false;
    passOneUpdateTick = false;
    
    
    [audioAsset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
        [self unregisterAudioListeners];
        
        self.audioItem = [AVPlayerItem playerItemWithAsset:audioAsset];
        self.audioPlayer = [[AVPlayer alloc] initWithPlayerItem:self.audioItem];
        self.audioPlayer.allowsExternalPlayback = false;
        
        if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"10.0")) {
            self.audioPlayer.automaticallyWaitsToMinimizeStalling = false;
        }
        
        [self sendDuration];
        [self registerAudioListeners];
        
        NSLog(@"Song title %@", _title);
    }];
}

- (void) setCurrentTimeFromJS: (CDVInvokedUrlCommand*) command {
    NSNumber *value = [command.arguments objectAtIndex:0];
    NSLog(@"setCurrentTimeFromJS, %@", value);
    [self setCurrentTime:[value intValue]];
}

- (void) setLoopFromJS: (CDVInvokedUrlCommand*) command {
    _isLoop = [command.arguments objectAtIndex:0];
    NSLog(@"%@", _isLoop);
    [self sendDataToJS:@{@"loop": _isLoop}];
}

- (void) setCurrentTime: (int) seconds {
    // seek time in player
    NSLog(@"seek time %d", seconds);
    CMTime seekTime = CMTimeMakeWithSeconds(seconds, 100000);
    int audioCurrentTimeSeconds = CMTimeGetSeconds(seekTime);
    NSString *currentTime = [[NSNumber numberWithInteger:audioCurrentTimeSeconds] stringValue];
    passOneUpdateTick = true;
    
    [self sendDataToJS:@{@"currentTime": currentTime}];
    [self.audioPlayer seekToTime:seekTime];
    
    // update playnow widget
    NSMutableDictionary *playInfo = [NSMutableDictionary dictionaryWithDictionary:[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo];
    [playInfo setObject:currentTime forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    center.nowPlayingInfo = playInfo;
}

// Get id for JS callback
- (void) setWatcherFromJS: (CDVInvokedUrlCommand*) command {
    subscribeCallbackID = command.callbackId;
}

// Send any data back to JS env through subscribe callback
- (void) sendDataToJS: (NSDictionary*) dict {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options: 0 error: nil];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    plresult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonString];
    [plresult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:plresult callbackId:subscribeCallbackID];
}

// Send duration to JS as soon as possible
- (void)sendDuration
{
    CMTime audioDuration = self.audioPlayer.currentItem.asset.duration;
    int audioDurationSeconds = CMTimeGetSeconds(audioDuration);
    NSString *duration = [[NSNumber numberWithInteger:audioDurationSeconds] stringValue];

    [self sendDataToJS:@{@"duration": duration}];

    NSLog(@"duration, %@", duration);
}

- (void)unregisterAudioListeners
{
    if (audioListenersApplied == true) {
        [self.audioItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
        [self.audioItem removeObserver:self forKeyPath:@"status"];
        [self.audioPlayer removeTimeObserver:self.timeObserver];
        audioListenersApplied = false;
    }
}

- (void)registerAudioListeners
{
    if (audioListenersApplied == false) {
        // Listener for updating elapsed time
        __block RCPlayer *that = self;
        CMTime interval = CMTimeMakeWithSeconds(1.0, NSEC_PER_SEC);

        self.timeObserver = [self.audioPlayer addPeriodicTimeObserverForInterval:interval queue:NULL usingBlock:^(CMTime time) {
            if (passOneUpdateTick == true) {
                passOneUpdateTick = false;
            } else {
                CMTime audioCurrentTime = that.audioPlayer.currentTime;
                int audioCurrentTimeSeconds = CMTimeGetSeconds(audioCurrentTime);
                NSString *elapsed = [[NSNumber numberWithInteger:audioCurrentTimeSeconds] stringValue];
                
                [that sendDataToJS:@{@"currentTime": elapsed}];
                NSLog(@"update time - %@", elapsed);
            }
        }];

        // Listener for buffering progress
        [self.audioItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];

        // Ready to play
        [self.audioItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];

        audioListenersApplied = true;
    }
}

- (void)play:(CDVInvokedUrlCommand*)command
{
    AVURLAsset *currentSong = (AVURLAsset *)[self.audioPlayer.currentItem asset];
 
    // Songs are loading async, start playing only if song ready to play.
    if ((readyToPlay == true) && ([currentSong.URL isEqual: readyToPlayAsset.URL])) {
        NSLog(@"play, %@", _title);
        [self.audioPlayer play];
        [self updateMusicControls:false];
    } else {
        needPlaySong = true;
    }
}

- (void)pause:(CDVInvokedUrlCommand*)command
{
    NSLog(@"pause");
    [self.audioPlayer pause];
    [self updateMusicControls:true];
    [audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)stop:(CDVInvokedUrlCommand*)command
{
    NSLog(@"stop");
    
    _isLoop = [NSNumber numberWithInteger:0];
    
    [self.audioPlayer pause];
    [self.audioPlayer.currentItem cancelPendingSeeks];
    [self.audioPlayer.currentItem.asset cancelLoading];
    [self sendDataToJS:@{@"bufferProgress": @"0"}];
    [self sendDataToJS:@{@"loop": _isLoop}];
    [self unregisterAudioListeners];
    
    self.audioPlayer = nil;
    self.audioItem = nil;
    songIsStopped = true;
    
    center.nowPlayingInfo = nil;
}

- (void)sendRemoteControlEvent:(NSString*)event
{
    NSLog(@"Event, %@", event);
    // Send event in JS env
    if (songIsStopped == false) {
     [self sendDataToJS:@{@"event": event}];
    }
}

- (void)onPlay:(MPRemoteCommandHandlerStatus*)event { [self sendRemoteControlEvent:@"play"]; }
- (void)onPause:(MPRemoteCommandHandlerStatus*)event { [self sendRemoteControlEvent:@"pause"]; }
- (void)onNextTrack:(MPRemoteCommandHandlerStatus*)event { [self sendRemoteControlEvent:@"nextTrack"]; }
- (void)onPreviousTrack:(MPRemoteCommandHandlerStatus*)event { [self sendRemoteControlEvent:@"previousTrack"]; }

// TODO read something about it
- (MPRemoteCommandHandlerStatus)setCanBeControlledByScrubbing:(MPChangePlaybackPositionCommandEvent*)event {
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)onChangePlayback:(MPChangePlaybackPositionCommandEvent*)event {
    NSLog(@"changePlaybackPosition to %f", event.positionTime);
    AVURLAsset *currentSong = (AVURLAsset *)[self.audioPlayer.currentItem asset];
    
    // Songs are loading async, rewind will work only for current song
    if ((readyToPlay == true) && ([currentSong.URL isEqual: readyToPlayAsset.URL])) {
        CMTime seekTime = CMTimeMakeWithSeconds(event.positionTime, 100000);
        int audioCurrentTimeSeconds = CMTimeGetSeconds(seekTime);
        NSString *elapsed = [[NSNumber numberWithInteger:audioCurrentTimeSeconds] stringValue];
        
        // seek to in player
        [self setCurrentTime:audioCurrentTimeSeconds];
        
        // update playnow widget
        NSMutableDictionary *playInfo = [NSMutableDictionary dictionaryWithDictionary:[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo];
        [playInfo setObject:elapsed forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
        center.nowPlayingInfo = playInfo;
    }

    return MPRemoteCommandHandlerStatusSuccess;
}

- (void)updateMusicControls:(BOOL)isPause {
    if (songIsStopped == false) {
        CMTime audioDuration = self.audioPlayer.currentItem.asset.duration;
        CMTime audioCurrentTime = self.audioPlayer.currentTime;
        
        int audioDurationSeconds = CMTimeGetSeconds(audioDuration);
        int audioCurrentTimeSeconds = CMTimeGetSeconds(audioCurrentTime);
        
        NSString *duration = [[NSNumber numberWithInteger:audioDurationSeconds] stringValue];
        NSString *elapsed = [[NSNumber numberWithInteger:audioCurrentTimeSeconds] stringValue];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            UIImage *image = nil;
            // check whether cover path is present
            if (![_cover isEqual: @""]) {
                // cover is remote file
                if ([_cover hasPrefix: @"http://"] || [_cover hasPrefix: @"https://"]) {
                    NSURL *imageURL = [NSURL URLWithString:_cover];
                    NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
                    image = [UIImage imageWithData:imageData];
                }
                // cover is full path to local file
                else if ([_cover hasPrefix: @"file://"]) {
                    NSString *fullPath = [_cover stringByReplacingOccurrencesOfString:@"file://" withString:@""];
                    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:fullPath];
                    if (fileExists) {
                        image = [[UIImage alloc] initWithContentsOfFile:fullPath];
                    }
                }
                // cover is relative path to local file
                else {
                    NSString *basePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                    NSString *fullPath = [NSString stringWithFormat:@"%@%@", basePath, _cover];
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
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (NSClassFromString(@"MPNowPlayingInfoCenter")) {
                        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithImage: image];
                        center.nowPlayingInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                                 _artist, MPMediaItemPropertyArtist,
                                                 _title, MPMediaItemPropertyTitle,
                                                 _album, MPMediaItemPropertyAlbumTitle,
                                                 artwork, MPMediaItemPropertyArtwork,
                                                 duration, MPMediaItemPropertyPlaybackDuration,
                                                 elapsed, MPNowPlayingInfoPropertyElapsedPlaybackTime,
                                                 [NSNumber numberWithFloat:(isPause ? 0.0f : 1.0f)], MPNowPlayingInfoPropertyPlaybackRate, nil];
                    }
                });
            }
        });
    }
}

-(void)itemDidFinishPlaying:(NSNotification *) notification {
    NSLog(@"Song stopped, %@", _isLoop);
    // If need loop current song
    if ([_isLoop isEqualToNumber:[NSNumber numberWithInt:1]]) {
        [self setCurrentTime:0];
        [self play:nil];
    } else {
        [self sendDataToJS:@{@"currentTime": @"0"}];
        [self sendRemoteControlEvent:@"nextTrack"];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    // check status initializing of song
    if (object == self.audioItem && [keyPath isEqualToString:@"status"]) {
        if (self.audioItem.status == AVPlayerStatusReadyToPlay) {
            NSLog(@"Ready to play");
            
            if (readyToPlayFired == false) {
                readyToPlay = true;
                readyToPlayFired = true;
                readyToPlayAsset = (AVURLAsset *)[self.audioPlayer.currentItem asset];
                
                if (needPlaySong) {
                    [self play:nil];
                }
            }
            
            plresult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:nil];
            [self.commandDelegate sendPluginResult:plresult callbackId:initCallbackID];
        } else if (self.audioPlayer.status == AVPlayerStatusFailed) {
            NSLog(@"Not ready to play");
            plresult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:self.audioPlayer.currentItem.error.localizedDescription];
            [self.commandDelegate sendPluginResult:plresult callbackId:initCallbackID];
        }
    }

    // Progress of buffering audio
    if (songIsLoaded == false) {
        if(object == self.audioPlayer.currentItem && [keyPath isEqualToString:@"loadedTimeRanges"]) {
            NSArray *loadedTimeRanges = [[self.audioPlayer currentItem] loadedTimeRanges];
            CMTimeRange timeRange = [[loadedTimeRanges objectAtIndex:0] CMTimeRangeValue];
            Float64 startSeconds = CMTimeGetSeconds(timeRange.start);
            Float64 durationSeconds = CMTimeGetSeconds(timeRange.duration);
            
            float percent = (startSeconds + durationSeconds) / CMTimeGetSeconds(self.audioPlayer.currentItem.duration) * 100;

            NSString *percentString = [[NSNumber numberWithFloat:percent] stringValue];

            [self sendDataToJS:@{@"bufferProgress": percentString}];

            NSLog(@"Buffering %@", percentString);

            if (percent >= 100) {
                songIsLoaded = true;
            }
        }
    }
}

-(void)dealloc {
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"receivedEvent" object:nil];
    [self unregisterAudioListeners];
}

@end
