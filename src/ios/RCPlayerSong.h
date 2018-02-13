#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MediaPlayer/MPNowPlayingInfoCenter.h>
#import <MediaPlayer/MPMediaItem.h>
#import "AVQueuePlayerPrevious.h"

@interface RCPlayerSong : NSObject {}

//- (void) setInformation:(NSDictionary*)data;
//- (void) setDuration:(NSString*)duration;

@property (strong, nonatomic) NSString *code;
@property (strong, nonatomic) NSString *artist;
@property (strong, nonatomic) NSString *title;
@property (strong, nonatomic) NSString *album;
@property (strong, nonatomic) NSString *cover;
@property (strong, nonatomic) NSString *url;

@end
