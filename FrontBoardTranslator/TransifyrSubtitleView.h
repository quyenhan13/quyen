#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TransifyrSubtitleView : UIView

- (void)start;
- (void)stop;
- (void)setSubtitlesEnabled:(BOOL)subtitlesEnabled;
- (BOOL)hasActiveAudio;

@end

NS_ASSUME_NONNULL_END
