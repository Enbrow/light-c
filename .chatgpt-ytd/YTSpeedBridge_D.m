#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

static NSString *const YTSEExternalRateDidChangeNotification = @"YTSEExternalRateDidChange";
static NSString *const YTSEUnifiedSpeedDidChangeNotification = @"YTSEUnifiedSpeedDidChange";

static IMP oMasterSetRate = NULL;
static IMP oMasterManage = NULL;
static IMP oSpeedViewInit = NULL;
static IMP oSpeedSliderChanged = NULL;
static IMP oSpeedSliderTapped = NULL;
static IMP oControlsLayout = NULL;
static IMP oOverlayLayout = NULL;

static float gLastRate = 1.0f;
static CFAbsoluteTime gGestureStartedAt = 0;
static NSUInteger gGestureGeneration = 0;

static float SnapRate(float rate) {
    if (!isfinite(rate)) return 1.0f;
    rate = roundf(rate * 4.0f) / 4.0f;
    return fmaxf(0.25f, fminf(10.0f, rate));
}

static NSString *RateText(float rate) {
    if (fabsf(rate - roundf(rate)) < 0.001f)
        return [NSString stringWithFormat:@"%.0fx", rate];
    if (fabsf(rate * 10.0f - roundf(rate * 10.0f)) < 0.001f)
        return [NSString stringWithFormat:@"%.1fx", rate];
    return [NSString stringWithFormat:@"%.2fx", rate];
}

static void Swizzle(Class cls, SEL sel, IMP replacement, IMP *original) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    if (original) *original = method_getImplementation(m);
    method_setImplementation(m, replacement);
}

static CGRect WindowRect(UIView *v) {
    if (!v.window) return CGRectZero;
    return [v convertRect:v.bounds toView:v.window];
}

static BOOL LooksLikeSpeedText(NSString *text) {
    if (!text.length || text.length > 8) return NO;
    NSString *lower = text.lowercaseString;
    if (![lower hasSuffix:@"x"] && ![lower hasSuffix:@"×"]) return NO;
    NSString *num = [text substringToIndex:text.length - 1];
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet];
    return [num rangeOfCharacterFromSet:bad].location == NSNotFound && num.length > 0;
}

static void SyncSpeedLabelsInView(UIView *view, float rate) {
    if (!view) return;
    NSString *text = RateText(rate);

    SEL speedValueSel = NSSelectorFromString(@"speedValue");
    if ([view respondsToSelector:speedValueSel]) {
        id obj = ((id(*)(id,SEL))objc_msgSend)(view, speedValueSel);
        if ([obj isKindOfClass:UIButton.class]) {
            [(UIButton *)obj setTitle:text forState:UIControlStateNormal];
        } else if ([obj isKindOfClass:UILabel.class]) {
            [(UILabel *)obj setText:text];
        }
    }

    if ([view isKindOfClass:UIButton.class]) {
        UIButton *b = (UIButton *)view;
        NSString *t = [b titleForState:UIControlStateNormal];
        if (LooksLikeSpeedText(t)) {
            CGRect r = WindowRect(b);
            if (!CGRectIsEmpty(r) && CGRectGetMidX(r) < 140.0 && CGRectGetMinY(r) < 500.0)
                [b setTitle:text forState:UIControlStateNormal];
        }
    } else if ([view isKindOfClass:UILabel.class]) {
        UILabel *l = (UILabel *)view;
        if (LooksLikeSpeedText(l.text)) {
            CGRect r = WindowRect(l);
            if (!CGRectIsEmpty(r) && CGRectGetMidX(r) < 140.0 && CGRectGetMinY(r) < 500.0)
                l.text = text;
        }
    }

    for (UIView *sub in view.subviews)
        SyncSpeedLabelsInView(sub, rate);
}

static void SyncAllLeftSpeedLabels(float rate) {
    gLastRate = rate;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows)
            SyncSpeedLabelsInView(window, rate);
    });
}

static void PostRateToYouSpeed(float rate) {
    if (!isfinite(rate) || rate < 0.25f || rate > 10.0f) return;
    gLastRate = rate;
    [[NSNotificationCenter defaultCenter] postNotificationName:YTSEExternalRateDidChangeNotification object:@(rate)];
    SyncAllLeftSpeedLabels(rate);
}

static void MasterSetRate(id self, SEL _cmd, double rate) {
    ((void(*)(id,SEL,double))oMasterSetRate)(self, _cmd, rate);
    if (isfinite(rate) && rate >= 0.25 && rate <= 10.0)
        PostRateToYouSpeed((float)rate);
}

static UIView *EducationViewForOverlay(id overlayVC) {
    id overlay = nil;
    id edu = nil;
    @try { overlay = [overlayVC valueForKey:@"videoPlayerOverlayView"]; } @catch (__unused NSException *e) {}
    @try { edu = [overlay valueForKey:@"scrubUserEducationView"]; } @catch (__unused NSException *e) {}
    return [edu isKindOfClass:UIView.class] ? edu : nil;
}

static void HideEducationView(UIView *edu) {
    SEL setVisible = NSSelectorFromString(@"setVisible:");
    if (edu && [edu respondsToSelector:setVisible])
        ((void(*)(id,SEL,BOOL))objc_msgSend)(edu, setVisible, NO);
}

static void MasterManage(id self, SEL _cmd, id gesture, id overlayVC) {
    ((void(*)(id,SEL,id,id))oMasterManage)(self, _cmd, gesture, overlayVC);

    UIGestureRecognizerState state = [gesture respondsToSelector:@selector(state)] ? [gesture state] : UIGestureRecognizerStatePossible;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    UIView *edu = EducationViewForOverlay(overlayVC);

    if (state == UIGestureRecognizerStateBegan) {
        gGestureStartedAt = now;
        NSUInteger generation = ++gGestureGeneration;
        __weak UIView *weakEdu = edu;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation == gGestureGeneration)
                HideEducationView(weakEdu);
        });
    } else if (gGestureStartedAt > 0 && now - gGestureStartedAt >= 3.0) {
        HideEducationView(edu);
    }

    if (state == UIGestureRecognizerStateEnded ||
        state == UIGestureRecognizerStateCancelled ||
        state == UIGestureRecognizerStateFailed) {
        gGestureStartedAt = 0;
        ++gGestureGeneration;
    }
}

static UISlider *SpeedViewSlider(id speedView) {
    id slider = nil;
    @try { slider = [speedView valueForKey:@"_slider"]; } @catch (__unused NSException *e) {}
    return [slider isKindOfClass:UISlider.class] ? slider : nil;
}

static void SetSpeedViewStep(id speedView, float step) {
    Ivar iv = class_getInstanceVariable(object_getClass(speedView) ? [speedView class] : Nil, "_step");
    if (!iv) iv = class_getInstanceVariable([speedView class], "_step");
    if (!iv) return;
    ptrdiff_t offset = ivar_getOffset(iv);
    uint8_t *base = (__bridge void *)speedView;
    *((float *)(base + offset)) = step;
}

static id SpeedViewInit(id self, SEL _cmd, CGRect frame) {
    id obj = ((id(*)(id,SEL,CGRect))oSpeedViewInit)(self, _cmd, frame);
    if (obj) {
        SetSpeedViewStep(obj, 0.25f);
        UISlider *slider = SpeedViewSlider(obj);
        if (slider) {
            slider.minimumValue = 0.25f;
            slider.maximumValue = 10.0f;
            slider.value = SnapRate(slider.value);
        }
    }
    return obj;
}

static void SpeedSliderChanged(id self, SEL _cmd, UISlider *slider) {
    if ([slider isKindOfClass:UISlider.class])
        slider.value = SnapRate(slider.value);
    ((void(*)(id,SEL,id))oSpeedSliderChanged)(self, _cmd, slider);
}

static void SpeedSliderTapped(id self, SEL _cmd, id sender) {
    ((void(*)(id,SEL,id))oSpeedSliderTapped)(self, _cmd, sender);
    UISlider *slider = SpeedViewSlider(self);
    if (slider) {
        float snapped = SnapRate(slider.value);
        if (fabsf(snapped - slider.value) > 0.001f) {
            slider.value = snapped;
            SEL changed = NSSelectorFromString(@"sliderChanged:");
            if ([self respondsToSelector:changed])
                ((void(*)(id,SEL,id))objc_msgSend)(self, changed, slider);
        }
    }
}

static void ControlsLayout(id self, SEL _cmd) {
    ((void(*)(id,SEL))oControlsLayout)(self, _cmd);
    SyncSpeedLabelsInView((UIView *)self, gLastRate);
}

static void OverlayLayout(id self, SEL _cmd) {
    ((void(*)(id,SEL))oOverlayLayout)(self, _cmd);
    SyncSpeedLabelsInView((UIView *)self, gLastRate);
}

__attribute__((constructor)) static void InitYTSEBridge(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:YTSEUnifiedSpeedDidChangeNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification *note) {
            NSNumber *n = note.object;
            if ([n respondsToSelector:@selector(floatValue)]) {
                float rate = [n floatValue];
                if (isfinite(rate) && rate >= 0.25f && rate <= 10.0f)
                    SyncAllLeftSpeedLabels(rate);
            }
        }];

        Class master = NSClassFromString(@"YTPSpeedMaster");
        Swizzle(master, NSSelectorFromString(@"setPlaybackRate:"), (IMP)MasterSetRate, &oMasterSetRate);
        Swizzle(master, NSSelectorFromString(@"manageSpeedMaster:playerOverlayVC:"), (IMP)MasterManage, &oMasterManage);

        Class speedView = NSClassFromString(@"YTPSpeedControlView");
        Swizzle(speedView, NSSelectorFromString(@"initWithFrame:"), (IMP)SpeedViewInit, &oSpeedViewInit);
        Swizzle(speedView, NSSelectorFromString(@"sliderChanged:"), (IMP)SpeedSliderChanged, &oSpeedSliderChanged);
        Swizzle(speedView, NSSelectorFromString(@"sliderTapped:"), (IMP)SpeedSliderTapped, &oSpeedSliderTapped);

        Class controls = NSClassFromString(@"YTMainAppControlsOverlayView");
        Swizzle(controls, @selector(layoutSubviews), (IMP)ControlsLayout, &oControlsLayout);

        Class overlay = NSClassFromString(@"YTMainAppVideoPlayerOverlayView");
        Swizzle(overlay, @selector(layoutSubviews), (IMP)OverlayLayout, &oOverlayLayout);
    }
}
