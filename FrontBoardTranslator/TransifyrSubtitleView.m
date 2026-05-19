#import "TransifyrSubtitleStore.h"
#import "TransifyrSubtitleView.h"

@interface TransifyrSubtitleView ()
@property(nonatomic, strong) UILabel *subtitleLabel;
@property(nonatomic, strong) TransifyrSubtitleStore *store;
@property(nonatomic, strong, nullable) NSTimer *timer;
@property(nonatomic, copy) NSString *lastTranslation;
@property(nonatomic, assign) BOOL subtitlesEnabled;
@end

@implementation TransifyrSubtitleView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _store = [TransifyrSubtitleStore new];
        _lastTranslation = @"";
        _subtitlesEnabled = YES;
        [self configureView];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)configureView {
    self.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.72];
    self.layer.cornerRadius = 16;
    self.layer.borderWidth = 1;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    self.clipsToBounds = YES;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(self.bounds, 18, 12)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.numberOfLines = 3;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.72;
    label.text = @"";
    self.subtitleLabel = label;
    [self addSubview:label];
}

- (void)start {
    [self stop];
    [self refreshSubtitle];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(refreshSubtitle) userInfo:nil repeats:YES];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)refreshSubtitle {
    BOOL activeAudio = [self.store hasActiveAudio];
    NSString *translation = [self.store currentTranslation];
    BOOL shouldShow = self.subtitlesEnabled && activeAudio && translation.length > 0;
    if ([translation isEqualToString:self.lastTranslation] && self.hidden == !shouldShow) {
        return;
    }

    self.lastTranslation = translation;
    self.subtitleLabel.text = translation;
    self.hidden = !shouldShow;
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
}

- (void)setSubtitlesEnabled:(BOOL)subtitlesEnabled {
    _subtitlesEnabled = subtitlesEnabled;
    if (!subtitlesEnabled) {
        self.hidden = YES;
    } else {
        [self refreshSubtitle];
    }
}

- (BOOL)hasActiveAudio {
    return [self.store hasActiveAudio];
}

@end
