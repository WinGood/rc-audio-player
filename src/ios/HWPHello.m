#import "HWPHello.h"

@implementation HWPHello

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
    [commandCenter.playCommand addTarget:self action:@selector(onPlay:)];
    [commandCenter.pauseCommand addTarget:self action:@selector(onPause:)];
    [commandCenter.nextTrackCommand addTarget:self action:@selector(onNextTrack:)];
    [commandCenter.previousTrackCommand addTarget:self action:@selector(onPreviousTrack:)];

    
//    [commandCenter.pauseCommand addTarget:self action:@selector(onPause:)];
//    [commandCenter.nextTrackCommand addTarget:self action:@selector(onNextTrack:)];
//    [commandCenter.previousTrackCommand addTarget:self action:@selector(onPreviousTrack:)];

}

- (void)initSong:(CDVInvokedUrlCommand*)command
{

//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    NSString* url = [[command arguments] objectAtIndex:0];
    NSURL *soundUrl = [[NSURL alloc] initWithString:url];
    NSLog(@"initSong, %@", soundUrl);
        
    self.audioItem = [AVPlayerItem playerItemWithURL:soundUrl];
    self.audioPlayer = [AVPlayer playerWithPlayerItem:self.audioItem];
    self.audioPlayer.automaticallyWaitsToMinimizeStalling = false;
        
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
    NSLog(@"play");
    [self.audioPlayer play];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (NSClassFromString(@"MPNowPlayingInfoCenter")) {
            MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
            center.nowPlayingInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                     @"test", MPMediaItemPropertyArtist,
                                     @"test", MPMediaItemPropertyTitle,
                                     @"test", MPMediaItemPropertyAlbumTitle,
//                                     self.audioItem.duration, MPMediaItemPropertyPlaybackDuration,
                                     [NSNumber numberWithFloat:1.0f],MPNowPlayingInfoPropertyPlaybackRate, nil];
        }
    });
}

- (void)pause:(CDVInvokedUrlCommand*)command
{
    NSLog(@"pause");
    [self.audioPlayer pause];
}

- (void)sendEvent:(NSString*)event
{
    NSLog(@"Event, %@", event);
    
//    if (self.callbackId != nil) {
//        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:event];
//        [pluginResult setKeepCallback:[NSNumber numberWithBool:YES]];
//        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
//    }
    
    if ([event isEqual: @"pause"]) {
        [self pause:nil];
    }
    
    if ([event isEqual: @"play"]) {
        [self play:nil];
    }
    
    if ([event isEqual:@"previousTrack"]) {
        
    }
    
    if ([event isEqual:@"nextTrack"]) {
        
    }
    
    NSDictionary *dict = @{@"subtype": event};
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options: 0 error: nil];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *jsStatement = [NSString stringWithFormat:@"if(window.hello)hello.receiveRemoteEvent(%@);", jsonString];
    
#ifdef __CORDOVA_4_0_0
    [self.webViewEngine evaluateJavaScript:jsStatement completionHandler:nil];
#else
    [self.webView stringByEvaluatingJavaScriptFromString:jsStatement];
#endif
}

- (void)onPlay:(MPRemoteCommandHandlerStatus*)event { [self sendEvent:@"play"]; }
- (void)onPause:(MPRemoteCommandHandlerStatus*)event { [self sendEvent:@"pause"]; }
- (void)onNextTrack:(MPRemoteCommandHandlerStatus*)event { [self sendEvent:@"nextTrack"]; }
- (void)onPreviousTrack:(MPRemoteCommandHandlerStatus*)event { [self sendEvent:@"previousTrack"]; }

-(void)dealloc {
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"receivedEvent" object:nil];
}

@end
