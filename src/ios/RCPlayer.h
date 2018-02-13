#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MediaPlayer/MPNowPlayingInfoCenter.h>
#import <MediaPlayer/MPMediaItem.h>
#import "AVQueuePlayerPrevious.h"
#import "RCPlayerSong.h"

@interface RCPlayer : CDVPlugin {
//    NSString *initCallbackID;
    NSString *subscribeCallbackID;
    MPNowPlayingInfoCenter *center;
    AVAudioSession *audioSession;
    AVQueuePlayerPrevious *player;
    NSMutableArray<AVPlayerItem *> *playerItems;
    NSMutableArray<RCPlayerSong *> *queue;
    NSMutableArray<RCPlayerSong *> *needAddToQueueWhenItWillBeInited;
    NSMutableArray<RCPlayerSong *> *needRemoveFromQueueWhenItWillBeInited;
    AVPlayer *currentTimeObserver;
    NSNumber *needLoopSong;
    NSString *shouldPlayWhenPlayerWillBeReady;
    bool queueWasInited;
    bool playerShouldPlayWhenItWillBeReady;
    bool playerIsPlaying;
    int queuePointer;
}

// NEW INTERFACE

- (void) initQueue:(CDVInvokedUrlCommand*)command; // DONE
- (void) add:(CDVInvokedUrlCommand*)command; // DONE insertBeforeId (optional)
- (void) remove:(CDVInvokedUrlCommand*)command; // from trackId to 1, set song (optional)
- (void) playTrack:(CDVInvokedUrlCommand*)command; // DONE
- (void) pauseTrack:(CDVInvokedUrlCommand*)command; // DONE
- (void) reset:(CDVInvokedUrlCommand*)command; // DONE
- (void) setLoopJS:(CDVInvokedUrlCommand*)command; // DONE
- (void) setCurrentTimeJS:(CDVInvokedUrlCommand*)command; // DONE

@end
