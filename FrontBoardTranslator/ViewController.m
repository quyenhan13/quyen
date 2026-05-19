#import "DecoratedAppSceneView.h"
#import "TransifyrSubtitleView.h"
#import "ViewController.h"
#import "UIKitPrivate.h"
#include <math.h>

@interface ViewController ()
@property(nonatomic) FBApplicationProcessLaunchTransaction *transaction;
@property(nonatomic) UIScenePresentationManager *presentationManager;
@property(nonatomic, strong) UIView *overlayContainer;
@property(nonatomic, strong) UIButton *rotateButton;
@property(nonatomic, strong) TransifyrSubtitleView *subtitleView;
@property(nonatomic, assign) BOOL forceLandscape;
@property(nonatomic, assign) NSInteger orientationMode;
@property(nonatomic, assign) BOOL manualLandscapeFallback;
@property(nonatomic, assign) CGSize lastLayoutSize;
@property(nonatomic, assign) CGPoint panStartCenter;
@property(nonatomic, assign) CGFloat lastSubtitleDefaultCenterX;
@property(nonatomic, assign) CGFloat lastSubtitleTopCenterY;
@property(nonatomic, assign) CGFloat lastSubtitleBottomCenterY;
@property(nonatomic, assign) BOOL draggingSubtitle;
@end

@implementation ViewController

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    switch (self.orientationMode) {
        case 1:
            return UIInterfaceOrientationMaskLandscapeRight;
        case 2:
            return UIInterfaceOrientationMaskLandscapeLeft;
        default:
            return UIInterfaceOrientationMaskPortrait;
    }
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    switch (self.orientationMode) {
        case 1:
            return UIInterfaceOrientationLandscapeRight;
        case 2:
            return UIInterfaceOrientationLandscapeLeft;
        default:
            return UIInterfaceOrientationPortrait;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
    self.title = nil;
}

- (void)loadView {
    [super loadView];
    self.view.backgroundColor = UIColor.clearColor;
    self.view.opaque = NO;
    self.title = nil;
    self.forceLandscape = NO;
    self.orientationMode = 0;
    self.manualLandscapeFallback = NO;
    self.lastLayoutSize = CGSizeZero;
    self.panStartCenter = CGPointZero;
    self.lastSubtitleDefaultCenterX = 0;
    self.lastSubtitleTopCenterY = 0;
    self.lastSubtitleBottomCenterY = 0;
    self.draggingSubtitle = NO;

    CGFloat width = MIN(UIScreen.mainScreen.bounds.size.width - 32, 520);
    CGFloat height = 92;
    UIView *container = [[UIView alloc] initWithFrame:self.view.bounds];
    container.backgroundColor = UIColor.clearColor;
    container.opaque = NO;
    container.autoresizingMask = UIViewAutoresizingNone;
    self.overlayContainer = container;
    [self.view addSubview:container];

    CGRect frame = CGRectMake(0, 0, width, height);
    TransifyrSubtitleView *subtitleView = [[TransifyrSubtitleView alloc] initWithFrame:frame];
    subtitleView.autoresizingMask = UIViewAutoresizingNone;
    self.subtitleView = subtitleView;
    [self.overlayContainer addSubview:subtitleView];
    [subtitleView start];
    [self addSubtitlePanGesture];
    [self addRotateButton];
    [self layoutOverlayControlsAnimated:NO];
    [self startFollowingSceneLayout];

    // Keep the shell visually transparent; the old drag/title handle created a dark band over SpringBoard.
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutOverlayControlsAnimated:NO];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self layoutOverlayControlsAnimated:YES];
}

- (void)addRotateButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = UIColor.whiteColor;
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.34];
    button.layer.cornerRadius = 18;
    button.layer.masksToBounds = YES;
    [button setTitle:@"Ngang" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(toggleOrientation) forControlEvents:UIControlEventTouchUpInside];
    self.rotateButton = button;
    [self.overlayContainer addSubview:button];
}

- (void)addSubtitlePanGesture {
    self.subtitleView.userInteractionEnabled = YES;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleSubtitlePan:)];
    [self.subtitleView addGestureRecognizer:pan];
}

- (NSString *)subtitleAnchorDefaultsKey {
    CGSize size = self.overlayContainer.bounds.size;
    BOOL wideLayout = self.manualLandscapeFallback || size.width > size.height || UIInterfaceOrientationIsLandscape(self.view.window.windowScene.interfaceOrientation);
    return wideLayout ? @"TransifyrSubtitleAnchorLandscape" : @"TransifyrSubtitleAnchorPortrait";
}

- (BOOL)subtitleShouldAnchorTop {
    NSString *anchor = [NSUserDefaults.standardUserDefaults stringForKey:[self subtitleAnchorDefaultsKey]];
    return [anchor isEqualToString:@"top"];
}

- (void)saveSubtitleAnchorTop:(BOOL)anchorTop {
    [NSUserDefaults.standardUserDefaults setObject:(anchorTop ? @"top" : @"bottom") forKey:[self subtitleAnchorDefaultsKey]];
}

- (void)clampSubtitleToVisibleAreaAnimated:(BOOL)animated {
    UIEdgeInsets safeArea = self.view.safeAreaInsets;
    CGRect visibleBounds = UIEdgeInsetsInsetRect(self.overlayContainer.bounds, UIEdgeInsetsMake(
        safeArea.top + 8,
        safeArea.left + 8,
        safeArea.bottom + 8,
        safeArea.right + 8
    ));
    if (CGRectGetWidth(visibleBounds) <= 1 || CGRectGetHeight(visibleBounds) <= 1) {
        visibleBounds = CGRectInset(self.overlayContainer.bounds, 8, 8);
    }

    CGRect frame = self.subtitleView.frame;
    if (CGRectGetWidth(visibleBounds) <= frame.size.width) {
        frame.origin.x = CGRectGetMidX(visibleBounds) - frame.size.width / 2.0;
    } else {
        frame.origin.x = MIN(MAX(frame.origin.x, CGRectGetMinX(visibleBounds)), CGRectGetMaxX(visibleBounds) - frame.size.width);
    }

    if (CGRectGetHeight(visibleBounds) <= frame.size.height) {
        frame.origin.y = CGRectGetMidY(visibleBounds) - frame.size.height / 2.0;
    } else {
        frame.origin.y = MIN(MAX(frame.origin.y, CGRectGetMinY(visibleBounds)), CGRectGetMaxY(visibleBounds) - frame.size.height);
    }

    void (^changes)(void) = ^{
        self.subtitleView.frame = frame;
    };

    if (animated) {
        [UIView animateWithDuration:0.2 animations:changes];
    } else {
        changes();
    }
}

- (void)handleSubtitlePan:(UIPanGestureRecognizer *)recognizer {
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            self.draggingSubtitle = YES;
            self.panStartCenter = self.subtitleView.center;
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint translation = [recognizer translationInView:self.overlayContainer];
            self.subtitleView.center = CGPointMake(self.lastSubtitleDefaultCenterX, self.panStartCenter.y + translation.y);
            [self clampSubtitleToVisibleAreaAnimated:NO];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            CGFloat midpoint = (self.lastSubtitleTopCenterY + self.lastSubtitleBottomCenterY) / 2.0;
            BOOL anchorTop = self.subtitleView.center.y < midpoint;
            self.draggingSubtitle = NO;
            [self saveSubtitleAnchorTop:anchorTop];
            [self layoutOverlayControlsAnimated:YES];
            break;
        }
        default:
            break;
    }
}

- (void)startFollowingSceneLayout {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sceneLayoutDidChange:) name:UIDeviceOrientationDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sceneLayoutDidChange:) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
}

- (void)sceneLayoutDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.draggingSubtitle) {
            return;
        }
        [self layoutOverlayControlsAnimated:YES];
    });
}

- (void)layoutOverlayControlsAnimated:(BOOL)animated {
    if (!self.overlayContainer || !self.subtitleView || !self.rotateButton) {
        return;
    }
    if (self.draggingSubtitle) {
        return;
    }

    void (^changes)(void) = ^{
        [self updateOverlayContainerGeometry];

        CGSize size = self.overlayContainer.bounds.size;
        if (size.width <= 1 || size.height <= 1) {
            return;
        }
        UIEdgeInsets safeArea = self.view.safeAreaInsets;
        BOOL wideLayout = self.manualLandscapeFallback || size.width > size.height || UIInterfaceOrientationIsLandscape(self.view.window.windowScene.interfaceOrientation);

        CGFloat horizontalSafeWidth = size.width - safeArea.left - safeArea.right;
        if (horizontalSafeWidth <= 1) {
            horizontalSafeWidth = size.width;
        }
        CGFloat homeIndicatorInset = wideLayout ? MAX(safeArea.bottom, MAX(safeArea.left, safeArea.right)) : safeArea.bottom;
        CGFloat maxSubtitleWidth = wideLayout ? MIN(size.width * 0.72, 700) : MIN(size.width * 0.86, 540);
        CGFloat minSubtitleWidth = MIN(horizontalSafeWidth - 24, wideLayout ? 300 : 260);
        minSubtitleWidth = MAX(minSubtitleWidth, 220);
        CGFloat subtitleWidth = MIN(MAX(horizontalSafeWidth - 48, minSubtitleWidth), maxSubtitleWidth);
        CGFloat subtitleHeight = wideLayout
            ? MIN(MAX(size.height * 0.105, 52), 66)
            : MIN(MAX(size.height * 0.085, 64), 86);
        CGFloat bottomInset = MAX(homeIndicatorInset, 12);
        CGFloat centerX = safeArea.left + horizontalSafeWidth / 2.0;
        CGFloat topInset = MAX(safeArea.top, 12);
        CGFloat topCenterY = topInset + subtitleHeight / 2.0 + 18;
        CGFloat bottomCenterY = size.height - bottomInset - subtitleHeight / 2.0 - 18;

        self.subtitleView.transform = CGAffineTransformIdentity;
        self.subtitleView.bounds = CGRectMake(0, 0, subtitleWidth, subtitleHeight);
        self.lastSubtitleDefaultCenterX = centerX;
        self.lastSubtitleTopCenterY = topCenterY;
        self.lastSubtitleBottomCenterY = bottomCenterY;
        BOOL anchorTop = [self subtitleShouldAnchorTop];
        self.subtitleView.center = CGPointMake(centerX, anchorTop ? topCenterY : bottomCenterY);
        [self clampSubtitleToVisibleAreaAnimated:NO];

        CGFloat buttonWidth = 64;
        CGFloat buttonHeight = 34;
        CGFloat buttonY = anchorTop
            ? CGRectGetMaxY(self.subtitleView.frame) + 8
            : safeArea.top + 12;
        CGFloat maxButtonY = size.height - safeArea.bottom - buttonHeight - 12;
        CGFloat minButtonY = safeArea.top + 12;
        if (maxButtonY < minButtonY) {
            buttonY = minButtonY;
        } else {
            buttonY = MIN(MAX(buttonY, minButtonY), maxButtonY);
        }
        self.rotateButton.transform = CGAffineTransformIdentity;
        self.rotateButton.frame = CGRectMake(
            size.width - safeArea.right - buttonWidth - 12,
            buttonY,
            buttonWidth,
            buttonHeight
        );
    };

    BOOL sizeChanged = !CGSizeEqualToSize(self.lastLayoutSize, self.overlayContainer.bounds.size);
    self.lastLayoutSize = self.overlayContainer.bounds.size;

    if (animated) {
        [UIView animateWithDuration:sizeChanged ? 0.25 : 0.16 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:changes completion:nil];
    } else {
        changes();
    }
}

- (void)updateOverlayContainerGeometry {
    CGSize size = self.view.bounds.size;
    if (size.width <= 1 || size.height <= 1) {
        return;
    }

    if (self.manualLandscapeFallback && size.height > size.width) {
        CGFloat landscapeWidth = size.height;
        CGFloat landscapeHeight = size.width;
        self.overlayContainer.bounds = CGRectMake(0, 0, landscapeWidth, landscapeHeight);
        self.overlayContainer.center = CGPointMake(size.width / 2.0, size.height / 2.0);
        CGFloat angle = self.orientationMode == 2 ? (CGFloat)-M_PI_2 : (CGFloat)M_PI_2;
        self.overlayContainer.transform = CGAffineTransformMakeRotation(angle);
    } else {
        self.overlayContainer.transform = CGAffineTransformIdentity;
        self.overlayContainer.frame = self.view.bounds;
    }
}

- (void)toggleOrientation {
    self.orientationMode = (self.orientationMode + 1) % 3;
    self.forceLandscape = self.orientationMode != 0;
    self.manualLandscapeFallback = NO;
    [self updateRotateButtonTitle];
    [self setNeedsUpdateOfSupportedInterfaceOrientations];
    [self layoutOverlayControlsAnimated:YES];

    UIInterfaceOrientationMask mask = UIInterfaceOrientationMaskPortrait;
    UIDeviceOrientation deviceOrientation = UIDeviceOrientationPortrait;
    if (self.orientationMode == 1) {
        mask = UIInterfaceOrientationMaskLandscapeRight;
        deviceOrientation = UIDeviceOrientationLandscapeLeft;
    } else if (self.orientationMode == 2) {
        mask = UIInterfaceOrientationMaskLandscapeLeft;
        deviceOrientation = UIDeviceOrientationLandscapeRight;
    }

    if (@available(iOS 16.0, *)) {
        UIWindowScene *windowScene = self.view.window.windowScene;
        if (!windowScene) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:UIWindowScene.class]) {
                    windowScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
        UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
        [windowScene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
            [[UIDevice currentDevice] setValue:@(deviceOrientation) forKey:@"orientation"];
            [UIViewController attemptRotationToDeviceOrientation];
        }];
        [self.view.window setAutorotates:YES forceUpdateInterfaceOrientation:YES];
        [[UIDevice currentDevice] setValue:@(deviceOrientation) forKey:@"orientation"];
        [UIViewController attemptRotationToDeviceOrientation];
    } else {
        [self.view.window setAutorotates:YES forceUpdateInterfaceOrientation:YES];
        [[UIDevice currentDevice] setValue:@(deviceOrientation) forKey:@"orientation"];
        [UIViewController attemptRotationToDeviceOrientation];
    }

    [self.view setNeedsLayout];
    [self verifyLandscapeFallbackAfterRotationRequest];
}

- (void)verifyLandscapeFallbackAfterRotationRequest {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.forceLandscape) {
            self.manualLandscapeFallback = NO;
            [self layoutOverlayControlsAnimated:YES];
            return;
        }

        CGSize size = self.view.bounds.size;
        BOOL sceneIsLandscape = size.width > size.height || UIInterfaceOrientationIsLandscape(self.view.window.windowScene.interfaceOrientation);
        self.manualLandscapeFallback = !sceneIsLandscape;
        [self layoutOverlayControlsAnimated:YES];
    });
}

- (void)updateRotateButtonTitle {
    NSString *title = @"Ngang";
    if (self.orientationMode == 1) {
        title = @"Trai";
    } else if (self.orientationMode == 2) {
        title = @"Doc";
    }
    [self.rotateButton setTitle:title forState:UIControlStateNormal];
}

@end
