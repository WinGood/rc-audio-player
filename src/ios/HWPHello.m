#import "HWPHello.h"

@implementation HWPHello

- (void)initSong:(CDVInvokedUrlCommand*)command
{

    NSString* url = [[command arguments] objectAtIndex:0];
    NSLog(@"initSong, %@", url);
    
    NSURL *soundUrl = [[NSURL alloc] initWithString:url];
    self.audioItem = [AVPlayerItem playerItemWithURL:soundUrl];
    self.audioPlayer = [AVPlayer playerWithPlayerItem:self.audioItem];
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(playerItemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.audioItem];
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(playerItemStalled:) name:AVPlayerItemPlaybackStalledNotification object:self.audioItem];

//    CDVPluginResult* result = [CDVPluginResult
//                               resultWithStatus:CDVCommandStatus_OK
//                               messageAsString:msg];
//
//    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
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
}

- (void)pause:(CDVInvokedUrlCommand*)command
{
    NSLog(@"pause");
    [self.audioPlayer pause];
}

@end
