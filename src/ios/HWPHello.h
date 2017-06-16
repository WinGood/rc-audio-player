#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MediaPlayer/MPNowPlayingInfoCenter.h>
#import <MediaPlayer/MPMediaItem.h>

@interface HWPHello : CDVPlugin {
    NSString *callbackId;
}

- (void) initSong:(CDVInvokedUrlCommand*)command;
- (void) play:(CDVInvokedUrlCommand*)command;
- (void) pause:(CDVInvokedUrlCommand*)command;

@property (nonatomic, copy) NSString *callbackId;
@property (strong, nonatomic) AVPlayerItem *audioItem;
@property (strong, nonatomic) AVPlayer *audioPlayer;

@end
