#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MediaPlayer/MPNowPlayingInfoCenter.h>
#import <MediaPlayer/MPMediaItem.h>
#import "AVQueuePlayerPrevious.h"
#import "RCPlayerSong.h"

@interface RCPlayer : CDVPlugin {
    NSString *subscribeCallbackID;
    MPNowPlayingInfoCenter *center;
    AVAudioSession *audioSession;
    AVQueuePlayerPrevious *player;
    NSMutableArray<RCPlayerSong *> *queue;
    NSMutableArray<RCPlayerSong *> *needAddToQueueWhenItWillBeInited;
    AVPlayer *currentTimeObserver;
    NSString *shouldPlayWhenPlayerWillBeReady;
    int shuffling;
    bool queueWasInited;
    bool playerShouldPlayWhenItWillBeReady;
    bool playerIsPlaying;
    int queuePointer;
}

// NEW INTERFACE

- (void) initQueue:(CDVInvokedUrlCommand*)command; // DONE
- (void) add:(CDVInvokedUrlCommand*)command; // DONE
- (void) replaceTrack:(CDVInvokedUrlCommand*)command; // DONE
- (void) removeTrack:(CDVInvokedUrlCommand*)command; //
- (void) playTrack:(CDVInvokedUrlCommand*)command; // DONE
- (void) setShuffling:(CDVInvokedUrlCommand*)command; // DONE
- (void) pauseTrack:(CDVInvokedUrlCommand*)command; // DONE
- (void) reset:(CDVInvokedUrlCommand*)command; // DONE
- (void) setCurrentTimeJS:(CDVInvokedUrlCommand*)command; // DONE

@end


