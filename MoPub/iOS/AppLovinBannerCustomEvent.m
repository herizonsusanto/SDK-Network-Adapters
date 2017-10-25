//
//  AppLovinBannerCustomEvent.m
//
//
//  Created by Thomas So on 7/6/17.
//
//


#import "AppLovinBannerCustomEvent.h"
#import "MPConstants.h"
#import "MPError.h"

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALAdView.h"
#endif

/**
 * The receiver object of the ALAdView's delegates. This is used to prevent a retain cycle between the ALAdView and AppLovinBannerCustomEvent.
 */
@interface AppLovinMoPubBannerDelegate : NSObject<ALAdLoadDelegate, ALAdDisplayDelegate>
@property (nonatomic, weak) AppLovinBannerCustomEvent *parentCustomEvent;
- (instancetype)initWithCustomEvent:(AppLovinBannerCustomEvent *)parentCustomEvent;
@end

@interface AppLovinBannerCustomEvent()
@property (nonatomic, strong) ALAdView *adView;
@end

@implementation AppLovinBannerCustomEvent

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALMoPubMediationErrorDomain = @"com.applovin.sdk.mediation.mopub.errorDomain";

#pragma mark - MPBannerCustomEvent Overridden Methods

- (void)requestAdWithSize:(CGSize)size customEventInfo:(NSDictionary *)info
{
    [self log: @"Requesting AppLovin banner of size %@ with info: %@", NSStringFromCGSize(size), info];
    
    // Convert requested size to AppLovin Ad Size
    ALAdSize *adSize = [self appLovinAdSizeFromRequestedSize: size];
    if ( adSize )
    {
        [[ALSdk shared] setPluginVersion: @"MoPub-2.2"];
        
        // Zones support is available on AppLovin SDK 4.5.0 and higher
        NSString *zoneIdentifier = info[@"zone_id"];
        if ( [ALSdk versionCode] >= 450 && zoneIdentifier.length > 0 )
        {
            self.adView = [self adViewWithAdSize: adSize zoneIdentifier: zoneIdentifier];
        }
        else
        {
            self.adView = [[ALAdView alloc] initWithFrame: CGRectMake(0.0f, 0.0f, size.width, size.height)
                                                     size: adSize
                                                      sdk: [ALSdk shared]];
        }
        
        AppLovinMoPubBannerDelegate *delegate = [[AppLovinMoPubBannerDelegate alloc] initWithCustomEvent: self];
        self.adView.adLoadDelegate = delegate;
        self.adView.adDisplayDelegate = delegate;
        
        [self.adView loadNextAd];
    }
    else
    {
        [self log: @"Failed to create an AppLovin banner with invalid size"];
        
        NSString *failureReason = [NSString stringWithFormat: @"Adaptor requested to display a banner with invalid size: %@.", NSStringFromCGSize(size)];
        NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                             code: kALErrorCodeUnableToRenderAd
                                         userInfo: @{NSLocalizedFailureReasonErrorKey : failureReason}];
        
        [self.delegate bannerCustomEvent: self didFailToLoadAdWithError: error];
    }
}

- (BOOL)enableAutomaticImpressionAndClickTracking
{
    return NO;
}

#pragma mark - Utility Methods

- (ALAdView *)adViewWithAdSize:(ALAdSize *)adSize zoneIdentifier:(NSString *)zoneIdentifier
{
    // Prematurely create instance of ALAdView to store initialized one in later
    ALAdView *adView = [ALAdView alloc];
    
    // We must use NSInvocation over performSelector: for initializers
    NSMethodSignature *methodSignature = [ALAdView instanceMethodSignatureForSelector: @selector(initWithSize:zoneIdentifier:)];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature: methodSignature];
    [inv setSelector: @selector(initWithSize:zoneIdentifier:)];
    [inv setArgument: &adSize atIndex: 2];
    [inv setArgument: &zoneIdentifier atIndex: 3];
    [inv setReturnValue: &adView];
    [inv invokeWithTarget: adView];
    
    return adView;
}

- (ALAdSize *)appLovinAdSizeFromRequestedSize:(CGSize)size
{
    if ( CGSizeEqualToSize(size, MOPUB_BANNER_SIZE) )
    {
        return [ALAdSize sizeBanner];
    }
    else if ( CGSizeEqualToSize(size, MOPUB_MEDIUM_RECT_SIZE) )
    {
        return [ALAdSize sizeMRec];
    }
    else if ( CGSizeEqualToSize(size, MOPUB_LEADERBOARD_SIZE) )
    {
        return [ALAdSize sizeLeader];
    }
    
    return nil;
}

- (void)log:(NSString *)format, ...
{
    if ( kALLoggingEnabled )
    {
        va_list valist;
        va_start(valist, format);
        NSString *message = [[NSString alloc] initWithFormat: format arguments: valist];
        va_end(valist);
        
        NSLog(@"AppLovinBannerCustomEvent: %@", message);
    }
}

- (MOPUBErrorCode)toMoPubErrorCode:(int)appLovinErrorCode
{
    if ( appLovinErrorCode == kALErrorCodeNoFill )
    {
        return MOPUBErrorAdapterHasNoInventory;
    }
    else if ( appLovinErrorCode == kALErrorCodeAdRequestNetworkTimeout )
    {
        return MOPUBErrorNetworkTimedOut;
    }
    else if ( appLovinErrorCode == kALErrorCodeInvalidResponse )
    {
        return MOPUBErrorServerError;
    }
    else
    {
        return MOPUBErrorUnknown;
    }
}

@end

@implementation AppLovinMoPubBannerDelegate

#pragma mark - Initialization

- (instancetype)initWithCustomEvent:(AppLovinBannerCustomEvent *)parentCustomEvent
{
    self = [super init];
    if ( self )
    {
        self.parentCustomEvent = parentCustomEvent;
    }
    return self;
}

#pragma mark - Ad Load Delegate

- (void)adService:(ALAdService *)adService didLoadAd:(ALAd *)ad
{
    [self.parentCustomEvent log: @"Banner did load ad: %@", ad.adIdNumber];
    [self.parentCustomEvent.delegate bannerCustomEvent: self.parentCustomEvent didLoadAd: self.parentCustomEvent.adView];
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    [self.parentCustomEvent log: @"Banner failed to load with error: %d", code];
    
    NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                         code: [self.parentCustomEvent toMoPubErrorCode: code]
                                     userInfo: nil];
    [self.parentCustomEvent.delegate bannerCustomEvent: self.parentCustomEvent didFailToLoadAdWithError: error];
}

#pragma mark - Ad Display Delegate

- (void)ad:(ALAd *)ad wasDisplayedIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner displayed"];
    
    // `didDisplayAd` of this class would not be called by MoPub on AppLovin banner refresh if enabled.
    // Only way to track impression of AppLovin refresh is via this callback.
    [self.parentCustomEvent.delegate trackImpression];
}

- (void)ad:(ALAd *)ad wasHiddenIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner dismissed"];
}

- (void)ad:(ALAd *)ad wasClickedIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner clicked"];
    
    [self.parentCustomEvent.delegate trackClick];
    [self.parentCustomEvent.delegate bannerCustomEventWillLeaveApplication: self.parentCustomEvent];
}

@end
