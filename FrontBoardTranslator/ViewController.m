#import "DecoratedAppSceneView.h"
#import "TransifyrSubtitleView.h"
#import "ViewController.h"

@interface ViewController ()
@property(nonatomic) FBApplicationProcessLaunchTransaction *transaction;
@property(nonatomic) UIScenePresentationManager *presentationManager;
@property(nonatomic, strong) TransifyrSubtitleView *subtitleView;
@property(nonatomic, strong) UIView *controlPanel;
@property(nonatomic, strong) UIButton *toggleButton;
@property(nonatomic, strong) UIButton *rotateButton;
@property(nonatomic, strong) NSTimer *controlTimer;
@property(nonatomic, assign) BOOL subtitlesEnabled;
@property(nonatomic, assign) NSInteger forcedOrientationMode;
@property(nonatomic, assign) NSTimeInterval controlsVisibleUntil;
@end

@implementation ViewController

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (self.forcedOrientationMode == 1) {
        return UIInterfaceOrientationMaskLandscape;
    }
    if (self.forcedOrientationMode == 2) {
        return UIInterfaceOrientationMaskPortrait;
    }
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
    self.title = nil;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutSubtitleView];
}

- (void)loadView {
    [super loadView];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.opaque = NO;
    self.title = nil;
    self.subtitlesEnabled = YES;
    self.forcedOrientationMode = 0;

    TransifyrSubtitleView *subtitleView = [[TransifyrSubtitleView alloc] initWithFrame:CGRectZero];
    subtitleView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleWidth;
    self.subtitleView = subtitleView;
    [self.view addSubview:self.subtitleView];
    [self.subtitleView start];
    [self configureControlPanel];
    [self startControlTimer];
    [self layoutSubtitleView];

    // Keep the shell visually transparent; the old drag/title handle created a dark band over SpringBoard.
}

- (void)dealloc {
    [self.controlTimer invalidate];
}

- (void)configureControlPanel {
    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.34];
    panel.opaque = NO;
    panel.layer.cornerRadius = 18;
    panel.layer.masksToBounds = YES;
    panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.controlPanel = panel;
    [self.view addSubview:panel];

    UIButton *toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    toggleButton.tintColor = UIColor.whiteColor;
    toggleButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [toggleButton setTitle:@"CC On" forState:UIControlStateNormal];
    [toggleButton addTarget:self action:@selector(toggleSubtitles) forControlEvents:UIControlEventTouchUpInside];
    self.toggleButton = toggleButton;
    [panel addSubview:toggleButton];

    UIButton *rotateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    rotateButton.tintColor = UIColor.whiteColor;
    rotateButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [rotateButton setTitle:@"Auto" forState:UIControlStateNormal];
    [rotateButton addTarget:self action:@selector(cycleOrientationMode) forControlEvents:UIControlEventTouchUpInside];
    self.rotateButton = rotateButton;
    [panel addSubview:rotateButton];
}

- (void)layoutSubtitleView {
    if (!self.subtitleView) {
        return;
    }

    CGRect bounds = self.view.bounds;
    if (CGRectIsEmpty(bounds)) {
        bounds = UIScreen.mainScreen.bounds;
    }

    BOOL landscape = bounds.size.width > bounds.size.height;
    CGFloat horizontalInset = landscape ? 80 : 16;
    CGFloat width = MIN(bounds.size.width - horizontalInset * 2, landscape ? 720 : 520);
    CGFloat height = landscape ? 78 : 92;
    CGFloat bottomInset = self.view.safeAreaInsets.bottom + (landscape ? 34 : 120);
    CGFloat x = (bounds.size.width - width) / 2;
    CGFloat y = MAX(self.view.safeAreaInsets.top + 12, bounds.size.height - bottomInset - height);

    self.subtitleView.frame = CGRectMake(x, y, width, height);
    [self.subtitleView setSubtitlesEnabled:self.subtitlesEnabled];

    CGFloat panelWidth = 128;
    CGFloat panelHeight = 36;
    CGFloat panelX = bounds.size.width - panelWidth - 12;
    CGFloat panelY = self.view.safeAreaInsets.top + 12;
    self.controlPanel.frame = CGRectMake(panelX, panelY, panelWidth, panelHeight);
    self.toggleButton.frame = CGRectMake(0, 0, panelWidth / 2, panelHeight);
    self.rotateButton.frame = CGRectMake(panelWidth / 2, 0, panelWidth / 2, panelHeight);
    [self refreshControlVisibility];
}

- (void)toggleSubtitles {
    self.subtitlesEnabled = !self.subtitlesEnabled;
    self.controlsVisibleUntil = NSDate.date.timeIntervalSince1970 + 4;
    [self.subtitleView setSubtitlesEnabled:self.subtitlesEnabled];
    [self.toggleButton setTitle:self.subtitlesEnabled ? @"CC On" : @"CC Off" forState:UIControlStateNormal];
    [self refreshControlVisibility];
}

- (void)cycleOrientationMode {
    self.forcedOrientationMode = (self.forcedOrientationMode + 1) % 3;
    self.controlsVisibleUntil = NSDate.date.timeIntervalSince1970 + 4;
    if (self.forcedOrientationMode == 0) {
        [self.rotateButton setTitle:@"Auto" forState:UIControlStateNormal];
        [UIViewController attemptRotationToDeviceOrientation];
        [self.view setNeedsLayout];
    } else if (self.forcedOrientationMode == 1) {
        [self.rotateButton setTitle:@"Ngang" forState:UIControlStateNormal];
        [self forceOrientation:UIInterfaceOrientationLandscapeRight];
    } else {
        [self.rotateButton setTitle:@"Doc" forState:UIControlStateNormal];
        [self forceOrientation:UIInterfaceOrientationPortrait];
    }
}

- (void)forceOrientation:(UIInterfaceOrientation)orientation {
    NSNumber *value = @(orientation);
    [[UIDevice currentDevice] setValue:value forKey:@"orientation"];
    [UIViewController attemptRotationToDeviceOrientation];
    [self.view setNeedsLayout];
}

- (void)startControlTimer {
    [self.controlTimer invalidate];
    self.controlTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refreshControlVisibility) userInfo:nil repeats:YES];
}

- (void)refreshControlVisibility {
    BOOL activeAudio = [self.subtitleView hasActiveAudio];
    BOOL recentlyTouched = NSDate.date.timeIntervalSince1970 < self.controlsVisibleUntil;
    BOOL visible = activeAudio || recentlyTouched || !self.subtitlesEnabled || self.forcedOrientationMode != 0;
    self.controlPanel.alpha = visible ? 1.0 : 0.18;
}

@end
