#import "TransifyrSubtitleStore.h"
#import "TransifyrSubtitleView.h"

@interface TransifyrSubtitleView ()
@property(nonatomic, strong) UILabel *subtitleLabel;
@property(nonatomic, strong) TransifyrSubtitleStore *store;
@property(nonatomic, strong, nullable) NSTimer *timer;
@property(nonatomic, copy) NSString *lastTranslation;
@property(nonatomic, strong, nullable) NSTimer *hideTimer;
@end

@implementation TransifyrSubtitleView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _store = [TransifyrSubtitleStore new];
        _lastTranslation = @"";
        [self configureView];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)configureView {
    self.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.64];
    self.layer.cornerRadius = 14;
    self.layer.borderWidth = 1;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    self.clipsToBounds = YES;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(self.bounds, 16, 9)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.numberOfLines = 2;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.68;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.text = @"";
    self.subtitleLabel = label;
    [self addSubview:label];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat minSide = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat maxSide = MAX(self.bounds.size.width, self.bounds.size.height);
    BOOL compactHeight = self.bounds.size.height < 68;

    CGFloat horizontalInset = compactHeight ? 14 : 16;
    CGFloat verticalInset = compactHeight ? 7 : 9;
    self.subtitleLabel.frame = CGRectInset(self.bounds, horizontalInset, verticalInset);

    CGFloat fontSize = maxSide / 34.0;
    fontSize = MAX(compactHeight ? 15.0 : 16.0, MIN(fontSize, compactHeight ? 18.0 : 20.0));
    if (minSide < 62) {
        fontSize = MIN(fontSize, 16.5);
    }

    self.subtitleLabel.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold];
    self.subtitleLabel.numberOfLines = compactHeight ? 2 : 3;
    self.layer.cornerRadius = compactHeight ? 12 : 14;
}

- (void)start {
    [self stop];
    [self refreshSubtitle];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(refreshSubtitle) userInfo:nil repeats:YES];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
    [self.hideTimer invalidate];
    self.hideTimer = nil;
}

- (void)refreshSubtitle {
    NSString *translation = [self.store consumeNewTranslation];
    if (translation.length == 0 || [translation isEqualToString:self.lastTranslation]) {
        return;
    }

    self.lastTranslation = translation;
    self.subtitleLabel.text = translation;
    self.hidden = NO;

    [self.hideTimer invalidate];
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:4.0 target:self selector:@selector(hideSubtitle) userInfo:nil repeats:NO];
}

- (void)hideSubtitle {
    self.subtitleLabel.text = @"";
    self.lastTranslation = @"";
    self.hidden = YES;
}

@end
