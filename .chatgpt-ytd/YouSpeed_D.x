#import "../YTVideoOverlay/Header.h"
#import "../YTVideoOverlay/Init.x"
#import <YouTubeHeader/MDCSlider.h>
#import <YouTubeHeader/MLAVPlayer.h>
#import <YouTubeHeader/MLHAMPlayerItemSegment.h>
#import <YouTubeHeader/MLHAMQueuePlayer.h>
#import <YouTubeHeader/QTMIcon.h>
#import <YouTubeHeader/UIView+YouTube.h>
#import <YouTubeHeader/YTActionSheetAction.h>
#import <YouTubeHeader/YTAlertView.h>
#import <YouTubeHeader/YTColor.h>
#import <YouTubeHeader/YTColorPalette.h>
#import <YouTubeHeader/YTCommonColorPalette.h>
#import <YouTubeHeader/YTCommonUtils.h>
#import <YouTubeHeader/YTLabel.h>
#import <YouTubeHeader/YTQTMButton.h>
#import <YouTubeHeader/YTIMenuItemSupportedRenderers.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import <YouTubeHeader/YTVarispeedSwitchController.h>
#import <YouTubeHeader/YTVarispeedSwitchControllerImpl.h>
#import <YouTubeHeader/YTVarispeedSwitchControllerOption.h>

#define TweakKey @"YouSpeed"
#define MoreSpeedKey @"YSMS"
#define FixNativeSpeedKey @"YSFNS"
#define SpeedSliderKey @"YSSS"
#define MIN_SPEED 0.25
#define MAX_SPEED 10.0

@interface YTMainAppControlsOverlayView (YouSpeed)
- (void)didPressYouSpeed:(id)arg;
- (void)updateYouSpeedButton:(id)arg;
@end

@interface YTMainAppVideoPlayerOverlayViewController (YouSpeed)
- (void)didChangePlaybackSpeed:(MDCSlider *)s;
@end

@interface YTInlinePlayerBarContainerView (YouSpeed)
- (void)didPressYouSpeed:(id)arg;
- (void)updateYouSpeedButton:(id)arg;
@end

NSString *YouSpeedUpdateNotification = @"YouSpeedUpdateNotification";
NSString *currentSpeedLabel = @"1x";
float currentPlaybackRate = 1.0;
static const void *YSFeedButtonKey = &YSFeedButtonKey;
static const void *YSFeedProxyKey = &YSFeedProxyKey;
static NSString *const YTSEExternalRateDidChangeNotification = @"YTSEExternalRateDidChange";
static NSString *const YTSEUnifiedSpeedDidChangeNotification = @"YTSEUnifiedSpeedDidChange";

static float YSSnapRate(float rate) {
    if (!isfinite(rate)) return 1.0;
    rate = roundf(rate * 4.0f) / 4.0f;
    return fmaxf(MIN_SPEED, fminf(MAX_SPEED, rate));
}

static NSBundle *YouSpeedBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"YouSpeed" ofType:@"bundle"];
        bundle = [NSBundle bundleWithPath:tweakBundlePath ?: PS_ROOT_PATH_NS(@"/Library/Application Support/YouSpeed.bundle")];
    });
    return bundle;
}

static BOOL MoreSpeed() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:MoreSpeedKey];
}

static BOOL FixNativeSpeed() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:FixNativeSpeedKey];
}

static BOOL SpeedSlider() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:SpeedSliderKey];
}

static NSString *speedLabel(float rate) {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 0;
    formatter.maximumFractionDigits = 2;
    NSString *rateString = [formatter stringFromNumber:[NSNumber numberWithFloat:rate]];
    return [NSString stringWithFormat:@"%@x", rateString];
}

static void didSelectRate(float rate) {
    if (!isfinite(rate) || rate < MIN_SPEED || rate > MAX_SPEED) return;
    currentPlaybackRate = rate;
    currentSpeedLabel = speedLabel(rate);
    [[NSNotificationCenter defaultCenter] postNotificationName:YouSpeedUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:YTSEUnifiedSpeedDidChangeNotification object:@(rate)];
}

static void YSDismissFromButton(UIView *button) {
    UIResponder *r = button;
    while (r) {
        if ([r respondsToSelector:@selector(dismiss)]) {
            ((void(*)(id,SEL))objc_msgSend)(r, @selector(dismiss));
            return;
        }
        r = r.nextResponder;
    }
}

@interface YSFeedSpeedDelegate : NSObject
@property (nonatomic, weak) YTPlayerViewController *player;
@end

@implementation YSFeedSpeedDelegate
- (void)didChangePlaybackSpeed:(MDCSlider *)s {
    float rate = YSSnapRate(s.value);
    s.value = rate;
    UILabel *label = [s.superview viewWithTag:'cvl0'];
    label.text = speedLabel(rate);
    if ([self.player respondsToSelector:@selector(varispeedSwitchController:didSelectRate:)]) {
        [self.player varispeedSwitchController:nil didSelectRate:rate];
    }
}
- (void)didPressMinusButton:(YTQTMButton *)button {
    MDCSlider *s = [button.superview viewWithTag:'slid'];
    s.value = YSSnapRate(s.value - 0.25f);
    [self didChangePlaybackSpeed:s];
}
- (void)didPressPlusButton:(YTQTMButton *)button {
    MDCSlider *s = [button.superview viewWithTag:'slid'];
    s.value = YSSnapRate(s.value + 0.25f);
    [self didChangePlaybackSpeed:s];
}
- (void)didPressSpeedPresetButton:(YTQTMButton *)button {
    MDCSlider *s = [button.superview viewWithTag:'slid'];
    float rate = YSSnapRate([[button titleForState:UIControlStateNormal] floatValue]);
    s.value = rate;
    [self didChangePlaybackSpeed:s];
    YSDismissFromButton(button);
}
@end

static BOOL YSIsFeedInlinePlayer(YTPlayerViewController *player) {
    if (![player isInlinePlaybackActive]) return NO;
    id overlay = [player activeVideoPlayerOverlay];
    NSString *name = overlay ? NSStringFromClass([overlay class]) : @"";
    return [name rangeOfString:@"InlineMutedPlayback" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static void YSStyleFeedButton(UIButton *button) {
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    button.layer.cornerRadius = 20.0;
    button.clipsToBounds = YES;
}

static void YSShowFeedSpeedUI(YTPlayerViewController *player, UIButton *sender) {
    if (SpeedSlider()) {
        Class alertClass = NSClassFromString(@"YouSpeedSliderAlertView");
        SEL infoSel = @selector(infoDialog);
        if (alertClass && [alertClass respondsToSelector:infoSel]) {
            id a = ((id(*)(id,SEL))objc_msgSend)(alertClass, infoSel);
            YSFeedSpeedDelegate *proxy = [YSFeedSpeedDelegate new];
            proxy.player = player;
            objc_setAssociatedObject(a, YSFeedProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSBundle *tweakBundle = YouSpeedBundle();
            NSString *label = LOC(@"PLAYBACK_SPEED");
            SEL setupSel = NSSelectorFromString(@"setupViews:sliderLabel:");
            if ([a respondsToSelector:setupSel])
                ((void(*)(id,SEL,id,id))objc_msgSend)(a, setupSel, proxy, label);
            @try { [a setValue:label forKey:@"title"]; } @catch (__unused NSException *e) {}
            SEL dismissSel = NSSelectorFromString(@"setShouldDismissOnBackgroundTap:");
            if ([a respondsToSelector:dismissSel])
                ((void(*)(id,SEL,BOOL))objc_msgSend)(a, dismissSel, YES);
            SEL showSel = @selector(show);
            if ([a respondsToSelector:showSel])
                ((void(*)(id,SEL))objc_msgSend)(a, showSel);
            return;
        }
    }

    id overlay = [player activeVideoPlayerOverlay];
    SEL varispeedSel = NSSelectorFromString(@"didPressVarispeed:");
    if (overlay && [overlay respondsToSelector:varispeedSel]) {
        ((void(*)(id,SEL,id))objc_msgSend)(overlay, varispeedSel, sender);
        return;
    }

    Class popupClass = NSClassFromString(@"YTPSpeedPopupController");
    SEL speedControllerSel = NSSelectorFromString(@"speedController");
    if (popupClass && [popupClass respondsToSelector:speedControllerSel]) {
        id popup = ((id(*)(id,SEL))objc_msgSend)(popupClass, speedControllerSel);
        SEL presentSel = NSSelectorFromString(@"presentFromViewController:");
        UIViewController *presenter = [player activeVideoPlayerOverlay] ?: player;
        if ([popup respondsToSelector:presentSel])
            ((void(*)(id,SEL,id))objc_msgSend)(popup, presentSel, presenter);
    }
}

%group Video

%hook YTPlayerViewController

- (void)setPlaybackRate:(float)rate {
    didSelectRate(rate);
    %orig;
    UIButton *feedButton = objc_getAssociatedObject(self, YSFeedButtonKey);
    if (feedButton) [feedButton setTitle:currentSpeedLabel forState:UIControlStateNormal];
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIButton *button = objc_getAssociatedObject(self, YSFeedButtonKey);
    if (!YSIsFeedInlinePlayer(self)) {
        button.hidden = YES;
        return;
    }

    UIView *playerView = self.playerView;
    if (!playerView) return;
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.accessibilityLabel = @"Feed playback speed";
        [button addTarget:self action:@selector(ysFeedSpeedTapped:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(self, YSFeedButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [playerView addSubview:button];
    } else if (button.superview != playerView) {
        [button removeFromSuperview];
        [playerView addSubview:button];
    }
    button.hidden = NO;
    [button setTitle:currentSpeedLabel forState:UIControlStateNormal];
    button.frame = CGRectMake(MAX(8.0, playerView.bounds.size.width - 58.0),
                              MAX(8.0, playerView.bounds.size.height - 108.0),
                              44.0, 40.0);
    YSStyleFeedButton(button);
    [playerView bringSubviewToFront:button];
}

%new(v@:@)
- (void)ysFeedSpeedTapped:(UIButton *)sender {
    YSShowFeedSpeedUI(self, sender);
}

%end

%end

%group Top

%hook YTMainAppControlsOverlayView

- (id)initWithDelegate:(id)delegate {
    self = %orig;
    [self updateYouSpeedButton:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateYouSpeedButton:) name:YouSpeedUpdateNotification object:nil];
    return self;
}

- (id)initWithDelegate:(id)delegate autoplaySwitchEnabled:(BOOL)autoplaySwitchEnabled {
    self = %orig;
    [self updateYouSpeedButton:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateYouSpeedButton:) name:YouSpeedUpdateNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:YouSpeedUpdateNotification object:nil];
    %orig;
}

%new(v@:@)
- (void)updateYouSpeedButton:(id)arg {
    [self.overlayButtons[TweakKey] setTitle:currentSpeedLabel forState:UIControlStateNormal];
}

%new(v@:@)
- (void)didPressYouSpeed:(id)arg {
    YTMainAppVideoPlayerOverlayViewController *c = [self valueForKey:@"_eventsDelegate"];
    [c didPressVarispeed:arg];
    [self updateYouSpeedButton:nil];
}

%end

%end

%group Bottom

%hook YTInlinePlayerBarContainerView

- (id)init {
    self = %orig;
    [self updateYouSpeedButton:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateYouSpeedButton:) name:YouSpeedUpdateNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:YouSpeedUpdateNotification object:nil];
    %orig;
}

%new(v@:@)
- (void)updateYouSpeedButton:(id)arg {
    [self.overlayButtons[TweakKey] setTitle:currentSpeedLabel forState:UIControlStateNormal];
}

%new(v@:@)
- (void)didPressYouSpeed:(id)arg {
    YTMainAppVideoPlayerOverlayViewController *c = [self.delegate valueForKey:@"_delegate"];
    [c didPressVarispeed:arg];
    [self updateYouSpeedButton:nil];
}

- (void)layoutSubviews {
    %orig;
    YTQTMButton *button = self.overlayButtons[TweakKey];
    if (!button) return;
    CGRect f = button.frame;
    CGPoint center = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
    f.size = CGSizeMake(44.0, 38.0);
    f.origin = CGPointMake(center.x - 22.0, center.y - 19.0);
    button.frame = f;
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    button.layer.cornerRadius = 19.0;
    button.clipsToBounds = YES;
}

%end

%end

%group OverrideNative

%hook YTMenuController

- (NSMutableArray <YTActionSheetAction *> *)actionsForRenderers:(NSMutableArray <YTIMenuItemSupportedRenderers *> *)renderers fromView:(UIView *)fromView entry:(id)entry shouldLogItems:(BOOL)shouldLogItems firstResponder:(id)firstResponder {
    NSUInteger index = [renderers indexOfObjectPassingTest:^BOOL(YTIMenuItemSupportedRenderers *renderer, NSUInteger idx, BOOL *stop) {
        YTIMenuItemSupportedRenderersElementRendererCompatibilityOptionsExtension *extension = (YTIMenuItemSupportedRenderersElementRendererCompatibilityOptionsExtension *)[renderer.elementRenderer.compatibilityOptions messageForFieldNumber:396644439];
        BOOL isVideoSpeed = [extension.menuItemIdentifier isEqualToString:@"menu_item_playback_speed"];
        if (isVideoSpeed) *stop = YES;
        return isVideoSpeed;
    }];
    NSMutableArray <YTActionSheetAction *> *actions = %orig;
    if (index != NSNotFound) {
        YTActionSheetAction *action = actions[index];
        action.handler = ^{
            [firstResponder didPressVarispeed:fromView];
        };
        UIView *elementView = [action.button valueForKey:@"_elementView"];
        elementView.userInteractionEnabled = NO;
    }
    return actions;
}

%end

%end

%group Speed

#define itemCount 17

%hook YTVarispeedSwitchController

- (id)init {
    self = %orig;
    float speeds[] = {MIN_SPEED, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 4.0, 5.0, 6.0, 7.5, MAX_SPEED};
    id options[itemCount];
    Class YTVarispeedSwitchControllerOptionClass = %c(YTVarispeedSwitchControllerOption);
    for (int i = 0; i < itemCount; ++i) {
        NSString *title = [NSString stringWithFormat:@"%.2fx", speeds[i]];
        options[i] = [[YTVarispeedSwitchControllerOptionClass alloc] initWithTitle:title rate:speeds[i]];
    }
    [self setValue:[NSArray arrayWithObjects:options count:itemCount] forKey:@"_options"];
    return self;
}

%end

%hook YTVarispeedSwitchControllerImpl

- (id)init {
    self = %orig;
    float speeds[] = {MIN_SPEED, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 4.0, 5.0, 6.0, 7.5, MAX_SPEED};
    id options[itemCount];
    Class YTVarispeedSwitchControllerOptionClass = %c(YTVarispeedSwitchControllerOption);
    for (int i = 0; i < itemCount; ++i) {
        NSString *title = [NSString stringWithFormat:@"%.2fx", speeds[i]];
        options[i] = [[YTVarispeedSwitchControllerOptionClass alloc] initWithTitle:title rate:speeds[i]];
    }
    [self setValue:[NSArray arrayWithObjects:options count:itemCount] forKey:@"_options"];
    return self;
}

%end

%hook MLHAMQueuePlayer

- (void)setRate:(float)newRate {
    float rate = [[self valueForKey:@"_rate"] floatValue];
    if (rate == newRate) return;
    MLHAMPlayerItem *playerItem = nil;
    if ([self respondsToSelector:@selector(currentPlayerItem)]) {
        playerItem = [self currentPlayerItem];
    } else {
        MLHAMPlayerItemSegment *segment = [self valueForKey:@"_currentSegment"];
        playerItem = [segment playerItem];
    }
    if (![playerItem.config varispeedAllowed]) return;
    [self setValue:@(newRate) forKey:@"_rate"];
    [self internalSetRate];
}

%end

%hook YTIPlayerHotConfig

%new(f@:)
- (float)maximumPlaybackRate {
    return MAX_SPEED;
}

%end

%hook YTIGranularVariableSpeedConfig

%new(d@:)
- (int)maximumPlaybackRate {
    return MAX_SPEED * 100;
}

%end

%end

%group AVPlayer

%hook MLAVPlayer

- (float)maximumSupportedPlaybackRate {
    return MAX_SPEED;
}

- (void)setRate:(float)newRate {
    MLInnerTubePlayerConfig *config = [self valueForKey:@"_config"];
    if (![config varispeedAllowed]) return;
    float rate = [[self valueForKey:@"_rate"] floatValue];
    if (rate == newRate) return;
    [self setValue:@(newRate) forKey:@"_rate"];
    self.assetPlayer.rate = newRate;
    MLPlayerStickySettings *stickySettings = [self valueForKey:@"_stickySettings"];
    stickySettings.rate = newRate;
    MLPlayerEventCenter *eventCenter = [self valueForKey:@"_playerEventCenter"];
    [eventCenter broadcastRateChange:newRate];
    if ([self.delegate respondsToSelector:@selector(player:rateDidChange:)])
        [self.delegate player:self rateDidChange:newRate];
    else
        [self.delegate playerRateDidChange:newRate];
}

%end

%end

%group Slider

@interface YouSpeedSliderAlertView : YTAlertView
- (void)setupViews:(YTMainAppVideoPlayerOverlayViewController *)delegate sliderLabel:(NSString *)sliderLabel;
@end

%subclass YouSpeedSliderAlertView : YTAlertView

%new(v@:@@)
- (void)setupViews:(YTMainAppVideoPlayerOverlayViewController *)delegate sliderLabel:(NSString *)sliderLabel {
    CGSize labelSize = CGSizeMake(50, 20);
    CGSize adjustButtonSize = CGSizeMake(30, 30);
    CGSize presetButtonSize = CGSizeMake(50, 30);

    MDCSlider *slider = [%c(MDCSlider) new];
    slider.statefulAPIEnabled = YES;
    slider.thumbHollowAtStart = NO;
    slider.minimumValue = MIN_SPEED;
    slider.maximumValue = MoreSpeed() ? MAX_SPEED : 2.0;
    slider.value = YSSnapRate(currentPlaybackRate);
    slider.continuous = NO;
    slider.accessibilityLabel = sliderLabel;
    slider.tag = 'slid';
    [slider setTrackBackgroundColor:[%c(YTColor) grey3Alpha70] forState:UIControlStateNormal];

    YTLabel *minLabel = [%c(YTLabel) new];
    minLabel.text = speedLabel(MIN_SPEED);
    minLabel.textAlignment = NSTextAlignmentLeft;
    minLabel.tag = 'minl';
    [minLabel yt_setSize:labelSize];
    [minLabel setTypeKind:22];

    YTLabel *maxLabel = [%c(YTLabel) new];
    maxLabel.text = speedLabel(MoreSpeed() ? MAX_SPEED : 2.0);
    maxLabel.textAlignment = NSTextAlignmentRight;
    maxLabel.tag = 'maxl';
    [maxLabel yt_setSize:labelSize];
    [maxLabel setTypeKind:22];

    YTLabel *currentValueLabel = [%c(YTLabel) new];
    currentValueLabel.text = currentSpeedLabel;
    currentValueLabel.textAlignment = NSTextAlignmentCenter;
    currentValueLabel.tag = 'cvl0';
    [currentValueLabel yt_setSize:labelSize];
    [currentValueLabel setTypeKind:22];

    UIImage *minusImage = [%c(QTMIcon) imageWithName:@"ic_remove" color:nil];
    UIImage *plusImage = [%c(QTMIcon) imageWithName:@"ic_add" color:nil];
    BOOL legacy = minusImage == nil;
    if (legacy) {
        minusImage = [%c(QTMIcon) imageWithName:@"ic_remove_circle" color:nil];
        plusImage = [[%c(QTMIcon) imageWithName:@"ic_add_circle" color:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    YTQTMButton *minusButton = [%c(YTQTMButton) buttonWithImage:minusImage accessibilityLabel:@"Decrease playback speed" accessibilityIdentifier:@"playback.speed.minus"];
    minusButton.flatButtonHasOpaqueBackground = !legacy;
    minusButton.sizeWithPaddingAndInsets = YES;
    minusButton.tag = 'mbtn';
    [minusButton yt_setSize:adjustButtonSize];
    [minusButton addTarget:delegate action:@selector(didPressMinusButton:) forControlEvents:UIControlEventTouchUpInside];

    YTQTMButton *plusButton = [%c(YTQTMButton) buttonWithImage:plusImage accessibilityLabel:@"Increase playback speed" accessibilityIdentifier:@"playback.speed.plus"];
    plusButton.flatButtonHasOpaqueBackground = !legacy;
    plusButton.sizeWithPaddingAndInsets = YES;
    plusButton.tag = 'pbtn';
    [plusButton yt_setSize:adjustButtonSize];
    [plusButton addTarget:delegate action:@selector(didPressPlusButton:) forControlEvents:UIControlEventTouchUpInside];

    struct {
        NSInteger tag;
        NSString *title;
    } presetSpeedConfigs[] = {
        {'s025', @"1x"},
        {'s050', @"2x"},
        {'s100', @"3x"},
        {'s150', @"5x"},
        {'s200', @"10x"},
    };
    NSUInteger presetCount = sizeof(presetSpeedConfigs) / sizeof(presetSpeedConfigs[0]);

    NSMutableArray *presetButtons = [NSMutableArray arrayWithCapacity:presetCount];
    for (NSUInteger i = 0; i < presetCount; i++) {
        YTQTMButton *button = [%c(YTQTMButton) textButton];
        button.flatButtonHasOpaqueBackground = YES;
        button.sizeWithPaddingAndInsets = NO;
#pragma clang diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        button.contentEdgeInsets = UIEdgeInsetsZero;
#pragma clang diagnostic pop
        button.tag = presetSpeedConfigs[i].tag;
        [button yt_setSize:presetButtonSize];
        [button setTitleTypeKind:21];
        [button setTitle:presetSpeedConfigs[i].title forState:UIControlStateNormal];
        [button addTarget:delegate action:@selector(didPressSpeedPresetButton:) forControlEvents:UIControlEventTouchUpInside];
        [presetButtons addObject:button];
    }

    CGFloat contentWidth = [%c(YTCommonUtils) isIPad] ? 350 : 250;
    UIView *contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, contentWidth, 120)];
    [contentView addSubview:slider];
    [contentView addSubview:minLabel];
    [contentView addSubview:maxLabel];
    [contentView addSubview:currentValueLabel];
    [contentView addSubview:minusButton];
    [contentView addSubview:plusButton];
    for (YTQTMButton *button in presetButtons) {
        [contentView addSubview:button];
    }

    CGFloat sliderWidth = contentWidth - 80;
    slider.frame = CGRectMake(0, 0, sliderWidth, adjustButtonSize.height);
    slider.delegate = (id <MDCSliderDelegate>)contentView;
    [slider addTarget:delegate action:@selector(didChangePlaybackSpeed:) forControlEvents:UIControlEventValueChanged];

    self.customContentView = contentView;
}

- (void)layoutSubviews {
    %orig;
    UIView *contentView = self.customContentView;
    YTLabel *minLabel = [contentView viewWithTag:'minl'];
    YTLabel *maxLabel = [contentView viewWithTag:'maxl'];
    YTLabel *currentValueLabel = [contentView viewWithTag:'cvl0'];
    YTQTMButton *minusButton = [contentView viewWithTag:'mbtn'];
    YTQTMButton *plusButton = [contentView viewWithTag:'pbtn'];
    MDCSlider *slider = [contentView viewWithTag:'slid'];
    
    NSMutableArray *presetButtons = [NSMutableArray array];
    NSInteger presetTags[] = {'s025', 's050', 's100', 's150', 's200'};
    for (int i = 0; i < 5; i++) {
        UIView *button = [contentView viewWithTag:presetTags[i]];
        if (button) [presetButtons addObject:button];
    }

    [slider alignCenterTopToCenterTopOfView:contentView paddingY:0];
    [minLabel alignTopLeadingToBottomLeadingOfView:slider paddingX:0 paddingY:10];
    [maxLabel alignTopTrailingToBottomTrailingOfView:slider paddingX:0 paddingY:10];
    [currentValueLabel alignCenterTopToCenterBottomOfView:slider paddingY:10];
    [minusButton alignCenterTrailingToCenterLeadingOfView:slider paddingX:10];
    [plusButton alignCenterLeadingToCenterTrailingOfView:slider paddingX:10];

    CGFloat padding = (contentView.frame.size.width - (50 * 5)) / 4;
    CGFloat buttonY = currentValueLabel.frame.origin.y + currentValueLabel.frame.size.height + 15;

    if ([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft)
        presetButtons = (NSMutableArray *)[[presetButtons reverseObjectEnumerator] allObjects];
    for (int i = 0; i < presetButtons.count; ++i) {
        YTQTMButton *button = presetButtons[i];
        [button yt_setOrigin:CGPointMake(i * (padding + 50), buttonY)];
    }
}

- (void)pageStyleDidChange:(NSInteger)pageStyle {
    %orig;
    YTCommonColorPalette *colorPalette;
    Class YTCommonColorPaletteClass = %c(YTCommonColorPalette);
    if (YTCommonColorPaletteClass)
        colorPalette = pageStyle == 1 ? [YTCommonColorPaletteClass darkPalette] : [YTCommonColorPaletteClass lightPalette];
    else
        colorPalette = [%c(YTColorPalette) colorPaletteForPageStyle:pageStyle];
    UIView *contentView = self.customContentView;
    MDCSlider *slider = [contentView viewWithTag:'slid'];
    YTLabel *minLabel = [contentView viewWithTag:'minl'];
    YTLabel *maxLabel = [contentView viewWithTag:'maxl'];
    YTLabel *currentValueLabel = [contentView viewWithTag:'cvl0'];
    YTQTMButton *minusButton = [contentView viewWithTag:'mbtn'];
    YTQTMButton *plusButton = [contentView viewWithTag:'pbtn'];

    NSMutableArray *presetButtons = [NSMutableArray array];
    NSInteger presetTags[] = {'s025', 's050', 's100', 's150', 's200'};
    for (int i = 0; i < 5; ++i) {
        YTQTMButton *button = (YTQTMButton *)[contentView viewWithTag:presetTags[i]];
        if (button) [presetButtons addObject:button];
    }

    UIColor *textColor = [colorPalette textPrimary];
    UIColor *adjustButtonBackgroundColor = [UIColor colorWithWhite:pageStyle alpha:0.2];
    minLabel.textColor = textColor;
    maxLabel.textColor = textColor;
    currentValueLabel.textColor = textColor;
    minusButton.tintColor = textColor;
    minusButton.enabledBackgroundColor = adjustButtonBackgroundColor;
    plusButton.tintColor = textColor;
    plusButton.enabledBackgroundColor = adjustButtonBackgroundColor;
    
    for (YTQTMButton *button in presetButtons) {
        button.customTitleColor = textColor;
        button.enabledBackgroundColor = adjustButtonBackgroundColor;
    }
    
    [slider setThumbColor:textColor forState:UIControlStateNormal];
    [slider setTrackFillColor:textColor forState:UIControlStateNormal];
}

%end

YouSpeedSliderAlertView *alert;

%hook YTMainAppVideoPlayerOverlayViewController

- (void)didPressVarispeed:(id)arg1 {
    NSBundle *tweakBundle = YouSpeedBundle();
    NSString *label = LOC(@"PLAYBACK_SPEED");
    NSString *chooseFromOriginalLabel = LOC(@"CHOOSE_FROM_ORIGINAL");
    alert = [%c(YouSpeedSliderAlertView) infoDialog];
    [alert setupViews:self sliderLabel:label];
    alert.title = label;
    alert.shouldDismissOnBackgroundTap = YES;
    alert.customContentViewInsets = UIEdgeInsetsMake(8, 0, 0, 0);
    [alert addTitle:chooseFromOriginalLabel withCancelAction:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            %orig;
        });
    }];
    [alert show];
}

%new(v@:@)
- (void)didChangePlaybackSpeed:(MDCSlider *)s {
    float rate = YSSnapRate(s.value);
    s.value = rate;
    UILabel *currentValueLabel = [s.superview viewWithTag:'cvl0'];
    [(id <YTVarispeedSwitchControllerDelegate>)self.delegate varispeedSwitchController:nil didSelectRate:rate];
    currentValueLabel.text = speedLabel(rate);
}

%new(v@:@)
- (void)didPressMinusButton:(YTQTMButton *)button {
    MDCSlider *slider = [button.superview viewWithTag:'slid'];
    float newValue = MAX(slider.minimumValue, YSSnapRate(slider.value - 0.25f));
    [slider setValue:newValue animated:YES];
    [self didChangePlaybackSpeed:slider];
}

%new(v@:@)
- (void)didPressPlusButton:(YTQTMButton *)button {
    MDCSlider *slider = [button.superview viewWithTag:'slid'];
    float newValue = MIN(slider.maximumValue, YSSnapRate(slider.value + 0.25f));
    [slider setValue:newValue animated:YES];
    [self didChangePlaybackSpeed:slider];
}

%new(v@:@)
- (void)didPressSpeedPresetButton:(YTQTMButton *)button {
    MDCSlider *slider = [button.superview viewWithTag:'slid'];
    float newValue = YSSnapRate([[button titleForState:UIControlStateNormal] floatValue]);
    slider.value = newValue;
    [self didChangePlaybackSpeed:slider];
    [alert dismiss];
    alert = nil;
}

%end

%end

%ctor {
    [[NSNotificationCenter defaultCenter] addObserverForName:YTSEExternalRateDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSNumber *n = note.object;
        if ([n respondsToSelector:@selector(floatValue)]) didSelectRate([n floatValue]);
    }];

    initYTVideoOverlay(TweakKey, @{
        AccessibilityLabelKey: @"Speed",
        SelectorKey: @"didPressYouSpeed:",
        AsTextKey: @YES,
        ExtraBooleanKeys: @[MoreSpeedKey, FixNativeSpeedKey, SpeedSliderKey],
    });
    %init(Video);
    %init(Top);
    %init(Bottom);
    if (MoreSpeed()) {
        %init(Speed);
        if (dlopen(PS_ROOT_PATH("/Library/MobileSubstrate/DynamicLibraries/UncappedAVPlayer.dylib"), RTLD_NOLOAD)) {
            %init(AVPlayer);
        }
    }
    if (FixNativeSpeed()) {
        %init(OverrideNative);
    }
    if (SpeedSlider()) {
        %init(Slider);
    }
}
