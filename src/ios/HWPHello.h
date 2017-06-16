#import <Cordova/CDV.h>
@import AVFoundation;

@interface HWPHello : CDVPlugin

- (void) initSong:(CDVInvokedUrlCommand*)command;
- (void) play:(CDVInvokedUrlCommand*)command;
- (void) pause:(CDVInvokedUrlCommand*)command;

@property (strong, nonatomic) AVPlayerItem *audioItem;
@property (strong, nonatomic) AVPlayer *audioPlayer;

@end
