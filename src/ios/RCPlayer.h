#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MediaPlayer/MPNowPlayingInfoCenter.h>
#import <MediaPlayer/MPMediaItem.h>

@interface RCPlayer : CDVPlugin {
    NSString *initCallbackID;
    NSString *subscribeCallbackID;
    CDVPluginResult *plresult;
    MPNowPlayingInfoCenter *center;
    AVAudioSession *audioSession;
}

- (void) initSong:(CDVInvokedUrlCommand*)command;
- (void) setLoopFromJS:(CDVInvokedUrlCommand*)command;
- (void) setCurrentTimeFromJS:(CDVInvokedUrlCommand*)command;
- (void) play:(CDVInvokedUrlCommand*)command;
- (void) pause:(CDVInvokedUrlCommand*)command;
- (void) stop:(CDVInvokedUrlCommand*)command;

@property (strong, nonatomic) AVPlayerItem *audioItem;
@property (strong, nonatomic) AVPlayer *audioPlayer;
@property (strong, nonatomic) AVPlayer *timeObserver;

@end
