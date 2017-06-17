#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MediaPlayer/MPNowPlayingInfoCenter.h>
#import <MediaPlayer/MPMediaItem.h>

@interface HWPHello : CDVPlugin {
    NSString *callbackID;
    CDVPluginResult *plresult;
    NSMutableDictionary *songInfo;
    MPNowPlayingInfoCenter *center;
}

- (void) initSong:(CDVInvokedUrlCommand*)command;
- (void) play:(CDVInvokedUrlCommand*)command;
- (void) pause:(CDVInvokedUrlCommand*)command;

@property (strong, nonatomic) AVPlayerItem *audioItem;
@property (strong, nonatomic) AVPlayer *audioPlayer;

@end
