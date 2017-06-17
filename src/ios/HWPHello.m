#import "HWPHello.h"

@implementation HWPHello

static NSString *_artist;
static NSString *_title;
static NSString *_album;
static NSString *_cover;
static NSNumber *_isLoop;
static bool isPlaying = false;
static bool audioListenersApplied = false;
static bool songIsLoaded = false;

- (void)pluginInitialize
{
    // Playback audio in background mode
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
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

    self.audioPlayer = [[AVPlayer alloc] init];

    // Listener for event that fired when song has stopped playing
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.audioItem];
}

- (void)initSong:(CDVInvokedUrlCommand*)command
{
    callbackID = command.callbackId;
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
    NSString *url = initSongDict[@"url"];
    NSString *artist = initSongDict[@"artist"];
    NSString *title = initSongDict[@"title"];
    NSString *album = initSongDict[@"album"];
    NSString *cover = initSongDict[@"cover"];
    NSString *isLoop = initSongDict[@"loop"];

    NSURL *soundUrl = [[NSURL alloc] initWithString:url];
    AVURLAsset* audioAsset = [AVURLAsset URLAssetWithURL:soundUrl options:nil];
    NSLog(@"Song title %@", title);


    _artist = artist;
    _title = title;
    _album = album;
    _cover = cover;
    _isLoop = [NSNumber numberWithBool:isLoop];

    songIsLoaded = false;

//    [songInfo setObject:soundUrl forKey:@"url"];
//    [songInfo setObject:artist forKey:@"artist"];
//    [songInfo setObject:title forKey:@"title"];
//    [songInfo setObject:album forKey:@"album"];
//    [songInfo setObject:cover forKey:@"cover"];

    [self unregisterAudioListeners];

    self.audioItem = [AVPlayerItem playerItemWithAsset:audioAsset];
    self.audioPlayer = [[AVPlayer alloc] initWithPlayerItem:self.audioItem];
    self.audioPlayer.automaticallyWaitsToMinimizeStalling = false;
    self.audioPlayer.allowsExternalPlayback = false;
    [self sendDuration];


    [self registerAudioListeners];
}

- (void) setCurrentTimeFromJS: (CDVInvokedUrlCommand*) command {
    NSNumber *value = [command.arguments objectAtIndex:0];
    NSLog(@"setCurrentTimeFromJS, %@", value);
    [self setCurrentTime:[value floatValue]];
}

- (void) setCurrentTime: (float) seconds {
    // seek time in player
    CMTime seekTime = CMTimeMakeWithSeconds(seconds, 100000);
    [self.audioPlayer seekToTime:seekTime];
}

// Get id for JS callback
- (void) watch: (CDVInvokedUrlCommand*) command {
    watchCallbackID = command.callbackId;
}

// Send any data back to JS env
- (void) sendDataToJS: (NSDictionary*) dict {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options: 0 error: nil];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    plresult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonString];
    [plresult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:plresult callbackId:watchCallbackID];
}

- (void)sendDuration
{
    CMTime audioDuration = self.audioPlayer.currentItem.asset.duration;
    float audioDurationSeconds = CMTimeGetSeconds(audioDuration);
    NSString *duration = [[NSNumber numberWithFloat:audioDurationSeconds] stringValue];
//
//    NSMutableDictionary *data = [NSMutableDictionary dictionary];
//    [data setObject:[NSMutableDictionary dictionaryWithDictionary:@{@"duration" : duration}]
//             forKey:@"data"];

    [self sendDataToJS:@{@"duration": duration}];

    NSLog(@"duration, %@", duration);
}

- (void)unregisterAudioListeners
{
    if (audioListenersApplied == true) {
        [self.audioItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
        [self.audioPlayer removeTimeObserver:self.timeObserver];
        audioListenersApplied = false;
    }
}

- (void)registerAudioListeners
{
    if (audioListenersApplied == false) {
        // Listener for updating current time in JS env
        __block HWPHello *that = self;
        CMTime interval = CMTimeMakeWithSeconds(1.0, NSEC_PER_SEC);

        self.timeObserver = [self.audioPlayer addPeriodicTimeObserverForInterval:interval queue:NULL usingBlock:^(CMTime time) {
            CMTime audioCurrentTime = that.audioPlayer.currentTime;
            float audioCurrentTimeSeconds = CMTimeGetSeconds(audioCurrentTime);
            NSString *elapsed = [[NSNumber numberWithFloat:audioCurrentTimeSeconds] stringValue];

            [that sendDataToJS:@{@"elapsed": elapsed}];
            NSLog(@"update time - %@", elapsed);
        }];

        // Listener for buffering progress
        [self.audioItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];

        audioListenersApplied = true;
    }
}

- (void)play:(CDVInvokedUrlCommand*)command
{
    NSLog(@"play, %@", _title);
    [self.audioPlayer play];
    [self updateMusicControls:false];
}

- (void)pause:(CDVInvokedUrlCommand*)command
{
    NSLog(@"pause");
    isPlaying = false;
    [self.audioPlayer pause];
    [self updateMusicControls:true];
}

- (void)sendEvent:(NSString*)event
{
    NSLog(@"Event, %@", event);

    // Send data back in JS env
    NSDictionary *dict = @{@"type": event};
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options: 0 error: nil];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    plresult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonString];
    [plresult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:plresult callbackId:callbackID];
}

- (void)onPlay:(MPRemoteCommandHandlerStatus*)event { [self sendEvent:@"play"]; }
- (void)onPause:(MPRemoteCommandHandlerStatus*)event { [self sendEvent:@"pause"]; }
- (void)onNextTrack:(MPRemoteCommandHandlerStatus*)event { [self sendEvent:@"nextTrack"]; }
- (void)onPreviousTrack:(MPRemoteCommandHandlerStatus*)event { [self sendEvent:@"previousTrack"]; }

- (MPRemoteCommandHandlerStatus)setCanBeControlledByScrubbing:(MPChangePlaybackPositionCommandEvent*)event {
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)onChangePlayback:(MPChangePlaybackPositionCommandEvent*)event {
    NSLog(@"changePlaybackPosition to %f", event.positionTime);
    CMTime seekTime = CMTimeMakeWithSeconds(event.positionTime, 100000);
    float audioCurrentTimeSeconds = CMTimeGetSeconds(seekTime);
    NSString *elapsed = [[NSNumber numberWithFloat:audioCurrentTimeSeconds] stringValue];

    // seek to in player
    [self setCurrentTime:audioCurrentTimeSeconds];

    // update playnow widget
    NSMutableDictionary *playInfo = [NSMutableDictionary dictionaryWithDictionary:[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo];
    [playInfo setObject:elapsed forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    center.nowPlayingInfo = playInfo;

    return MPRemoteCommandHandlerStatusSuccess;
}

- (void)updateMusicControls:(BOOL)isPause {
    CMTime audioDuration = self.audioPlayer.currentItem.asset.duration;
    CMTime audioCurrentTime = self.audioPlayer.currentTime;

    float audioDurationSeconds = CMTimeGetSeconds(audioDuration);
    float audioCurrentTimeSeconds = CMTimeGetSeconds(audioCurrentTime);

    NSString *duration = [[NSNumber numberWithFloat:audioDurationSeconds] stringValue];
    NSString *elapsed = [[NSNumber numberWithFloat:audioCurrentTimeSeconds] stringValue];

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

-(void)itemDidFinishPlaying:(NSNotification *) notification {
    NSLog(@"Song stopped, %@", _isLoop);
    if ([_isLoop isEqualToNumber:[NSNumber numberWithInt:1]]) {
        // Loop for current audio
        [self setCurrentTime:0.0];
        [self play:nil];
    } else {
        [self sendEvent:@"nextTrack"];
    }
}

-(void)itemDidFinishPlaying1:(NSNotification *) notification {
    NSLog(@"Song jumped %@", notification);
//    [self sendEvent:@"nextTrack"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if (songIsLoaded == false) {
        if(object == self.audioPlayer.currentItem && [keyPath isEqualToString:@"loadedTimeRanges"]) {
            NSArray *timeRanges = (NSArray*)[change objectForKey:NSKeyValueChangeNewKey];
            if (timeRanges && [timeRanges count]) {
                CMTimeRange timeRange = [[timeRanges objectAtIndex:0] CMTimeRangeValue];

                float percent = (CMTimeGetSeconds(timeRange.duration) / CMTimeGetSeconds(self.audioPlayer.currentItem.duration)) * 100;

                NSString *percentString = [[NSNumber numberWithFloat:percent] stringValue];

                NSLog(@"Buffering %@", percentString);

                [self sendDataToJS:@{@"bufferProgress": percentString}];

                if (percent >= 100) {
                    songIsLoaded = true;
                }
            }
        }
    }
}

-(void)dealloc {
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"receivedEvent" object:nil];
}

@end
