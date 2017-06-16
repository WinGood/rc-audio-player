#import "HWPHello.h"

@implementation HWPHello

static NSString *_artist;
static NSString *_title;
static NSString *_album;
static NSString *_cover;
static bool isPlaying = false;

- (void)pluginInitialize
{
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
    [commandCenter.changePlaybackPositionCommand addTarget:self action:@selector(onChangePlayback:)];
    [commandCenter.playCommand addTarget:self action:@selector(onPlay:)];
    [commandCenter.pauseCommand addTarget:self action:@selector(onPause:)];
    [commandCenter.nextTrackCommand addTarget:self action:@selector(onNextTrack:)];
    [commandCenter.previousTrackCommand addTarget:self action:@selector(onPreviousTrack:)];
    [commandCenter.seekBackwardCommand addTarget:self action:@selector(onSeekBackwardTrack:)];
    [commandCenter.seekForwardCommand addTarget:self action:@selector(onSeekForwardTrack:)];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.audioItem];
}

- (void)initSong:(CDVInvokedUrlCommand*)command
{
    callbackID = command.callbackId;
    center = [MPNowPlayingInfoCenter defaultCenter];
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

    NSString *url = [command.arguments objectAtIndex:0];
    NSString *artist = [command.arguments objectAtIndex:1];
    NSString *title = [command.arguments objectAtIndex:2];
    NSString *album = [command.arguments objectAtIndex:3];
    NSString *cover = [command.arguments objectAtIndex:4];
//    NSNumber *duration = [command.arguments objectAtIndex:5];
//    NSNumber *elapsed = [command.arguments objectAtIndex:6];

    NSURL *soundUrl = [[NSURL alloc] initWithString:url];
    AVURLAsset* audioAsset = [AVURLAsset URLAssetWithURL:soundUrl options:nil];
    NSLog(@"initSong, %@", soundUrl);
    NSLog(@"Song title %@", title);
    

    _artist = artist;
    _title = title;
    _album = album;
    _cover = cover;
//
//    [songInfo setObject:soundUrl forKey:@"url"];
//    [songInfo setObject:artist forKey:@"artist"];
//    [songInfo setObject:title forKey:@"title"];
//    [songInfo setObject:album forKey:@"album"];
//    [songInfo setObject:cover forKey:@"cover"];

    self.audioItem = [AVPlayerItem playerItemWithAsset:audioAsset];
//    self.audioPlayer = [AVPlayer playerWithPlayerItem:self.audioItem];
    self.audioPlayer = [[AVPlayer alloc] initWithPlayerItem:self.audioItem];
    self.audioPlayer.automaticallyWaitsToMinimizeStalling = false;
    self.audioPlayer.allowsExternalPlayback = false;

    [[NSNotificationCenter defaultCenter]
    addObserver:self selector:@selector(playerItemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.audioItem];

    [[NSNotificationCenter defaultCenter]
    addObserver:self selector:@selector(playerItemStalled:) name:AVPlayerItemPlaybackStalledNotification object:self.audioItem];
}

- (void)playerItemDidReachEnd:(NSNotification *)notification{
    [self.audioItem seekToTime:kCMTimeZero];
    NSLog(@"AudioEnded");
//    [self sendEventWithName:@"AudioEnded" body:@{@"event": @"finished"}];
}
- (void)playerItemStalled:(NSNotification *)notification{
    [self.audioPlayer play];
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

- (void)onSeekBackwardTrack:(MPRemoteCommandHandlerStatus*)event {
    [self sendEvent:@"seekBackwardTrack"];
}

- (void)onSeekForwardTrack:(MPRemoteCommandHandlerStatus*)event {
    [self sendEvent:@"seekForwardTrack"];
}

- (MPRemoteCommandHandlerStatus)setCanBeControlledByScrubbing:(MPChangePlaybackPositionCommandEvent*)event {
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)onChangePlayback:(MPChangePlaybackPositionCommandEvent*)event {
    NSLog(@"changePlaybackPosition to %f", event.positionTime);
    CMTime seekTime = CMTimeMakeWithSeconds(event.positionTime, 100000);
    float audioCurrentTimeSeconds = CMTimeGetSeconds(seekTime);
    NSString *elapsed = [[NSNumber numberWithFloat:audioCurrentTimeSeconds] stringValue];
    
    [self.audioPlayer seekToTime:seekTime];
    
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
    
//    NSLog(@"duration, %@, %@", duration, elapsed);
    
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
    NSLog(@"Song stopped");
    [self sendEvent:@"nextTrack"];
}

-(void)dealloc {
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"receivedEvent" object:nil];
}

@end
