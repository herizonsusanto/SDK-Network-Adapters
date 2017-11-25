//
//  AppLovinCustomEventBanner.m
//
//
//  Created by Thomas So on 4/12/17.
//
//

#import "AppLovinCustomEventBanner.h"

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALAdView.h"
#endif

// Convenience macro for checking if AppLovin SDK has support for zones
#define HAS_ZONES_SUPPORT [[ALSdk shared].adService respondsToSelector: @selector(loadNextAdForZoneIdentifier:andNotify:)]
#define DEFAULT_ZONE @""

@interface ALAdMobAdView : ALAdView @end

/**
 * The receiver object of the ALAdView's and ALAdService's delegates. This is used to prevent a retain cycle between the ALAdView and AppLovinBannerCustomEvent.
 */
@interface AppLovinAdMobBannerDelegate : NSObject<ALAdDisplayDelegate>
@property (nonatomic, weak) AppLovinCustomEventBanner *parentCustomEvent;
- (instancetype)initWithCustomEvent:(AppLovinCustomEventBanner *)parentCustomEvent;
@end

@interface AppLovinCustomEventBanner()<ALAdLoadDelegate>
@property (nonatomic, strong) ALAdView *adView;
@property (nonatomic,   copy) NSString *zoneIdentifier; // The zone identifier this instance of the custom event is loading for
@end

@implementation AppLovinCustomEventBanner
@synthesize delegate;

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALAdMobMediationErrorDomain = @"com.applovin.sdk.mediation.admob.errorDomain";

static const CGFloat kALBannerHeightOffsetTolerance = 10.0f;
static const CGFloat kALBannerStandardHeight = 50.0f;

// A dictionary of Zone -> AdView to be shared by instances of the custom event to prevent redundant recreation of our `ALAdView`s.
static NSMutableDictionary<NSString *, ALAdView *> *ALGlobalAdViews;

// A dictionary of Zone -> Queue of `ALAd`s to be shared by instances of the custom event.
// This prevents skipping of ads as this adapter will be re-created and preloaded
// on every ad load regardless if ad was actually displayed or not.
static NSMutableDictionary<NSString *, NSMutableArray<ALAd *> *> *ALGlobalAdViewAds;
static NSObject *ALGlobalAdViewAdsLock;

#pragma mark - Class Initialization

+ (void)initialize
{
    [super initialize];
    
    ALGlobalAdViews = [NSMutableDictionary dictionary];
    
    ALGlobalAdViewAds = [NSMutableDictionary dictionary];
    ALGlobalAdViewAdsLock = [[NSObject alloc] init];
}

#pragma mark - GADCustomEventBanner Protocol

- (void)requestBannerAd:(GADAdSize)adSize parameter:(NSString *)serverParameter label:(NSString *)serverLabel request:(GADCustomEventRequest *)request
{
    [self log: @"Requesting AppLovin banner of size %@", NSStringFromGADAdSize(adSize)];
    
    // Convert requested size to AppLovin Ad Size
    ALAdSize *appLovinAdSize = [self appLovinAdSizeFromRequestedSize: adSize];
    if ( appLovinAdSize )
    {
        [[ALSdk shared] setPluginVersion: @"AdMob-2.3"];
        
        CGSize size = CGSizeFromGADAdSize(adSize);
        
        // Zones support is available on AppLovin SDK 4.5.0 and higher
        if ( HAS_ZONES_SUPPORT && request.additionalParameters[@"zone_id"] )
        {
            self.zoneIdentifier = request.additionalParameters[@"zone_id"];
        }
        else
        {
            self.zoneIdentifier = DEFAULT_ZONE;
        }
        
        
        self.adView = ALGlobalAdViews[self.zoneIdentifier];
        
        // Check if we already have an ALAdView for the given zone
        if ( !self.adView )
        {
            // If this is a default Zone, create the incentivized ad normally
            if ( [DEFAULT_ZONE isEqualToString: self.zoneIdentifier] )
            {
                self.adView = [[ALAdMobAdView alloc] initWithFrame: CGRectMake(0.0f, 0.0f, size.width, size.height)
                                                              size: appLovinAdSize
                                                               sdk: [ALSdk shared]];
            }
            // Otherwise, use the Zones API
            else
            {
                self.adView = [self adViewWithAdSize: appLovinAdSize zoneIdentifier: self.zoneIdentifier];
            }
            
            ALGlobalAdViews[self.zoneIdentifier] = self.adView;
        }
        
        
        AppLovinAdMobBannerDelegate *delegate = [[AppLovinAdMobBannerDelegate alloc] initWithCustomEvent: self];
        self.adView.adDisplayDelegate = delegate;
        
        // Already have a preloaded ad
        if ( [[self class] hasEnqueuedAdForZoneIdentifier: self.zoneIdentifier] )
        {
            [self.delegate customEventBanner: self didReceiveAd: self.adView];
        }
        else
        {
            // If this is a default Zone, create the incentivized ad normally
            if ( [DEFAULT_ZONE isEqualToString: self.zoneIdentifier] )
            {
                [[ALSdk shared].adService loadNextAd: appLovinAdSize andNotify: self];
            }
            // Otherwise, use the Zones API
            else
            {
                // Dynamically load an ad for a given zone without breaking backwards compatibility for publishers on older SDKs
                [[ALSdk shared].adService performSelector: @selector(loadNextAdForZoneIdentifier:andNotify:)
                                               withObject: self.zoneIdentifier
                                               withObject: self];
            }
        }
    }
    else
    {
        [self log: @"Failed to create an AppLovin Banner with invalid size"];
        
        NSError *error = [NSError errorWithDomain: kALAdMobMediationErrorDomain
                                             code: kGADErrorMediationInvalidAdSize
                                         userInfo: nil];
        [self.delegate customEventBanner: self didFailAd: error];
    }
}


#pragma mark - AppLovin Ad Load Delegate

- (void)adService:(ALAdService *)adService didLoadAd:(ALAd *)ad
{
    [self log: @"Banner did load ad: %@", ad.adIdNumber];
    
    if ( !self.adView.window )
    {
        [AppLovinCustomEventBanner enqueueAd: ad forZoneIdentifier: self.zoneIdentifier];
    }
    else
    {
        // Check if we have enqueued ad already
        ALAd *enqueuedAd = [AppLovinCustomEventBanner dequeueAdForZoneIdentifier: self.zoneIdentifier];
        if ( enqueuedAd )
        {
            [self.adView render: enqueuedAd];
            [AppLovinCustomEventBanner enqueueAd: ad forZoneIdentifier: self.zoneIdentifier];
        }
        // No enqueued ad, render newly loaded ad
        else
        {
            [self.adView render: ad];
        }
    }
    
    [self.delegate customEventBanner: self didReceiveAd: self.adView];
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    [self log: @"Banner failed to load with error: %d", code];
    
    NSError *error = [NSError errorWithDomain: kALAdMobMediationErrorDomain
                                         code: [self toAdMobErrorCode: code]
                                     userInfo: nil];
    
    // If CURRENT ad request was a no fill, check against enqueued ads
    if ( code == kALErrorCodeNoFill )
    {
        ALAd *preloadedAd = [AppLovinCustomEventBanner dequeueAdForZoneIdentifier: self.zoneIdentifier];
        
        // There is an enqueued ad, use that
        if ( preloadedAd )
        {
            [self log: @"Using enqueued ad instead..."];
            [self adService: adService didLoadAd: preloadedAd];
        }
        else
        {
            [self.delegate customEventBanner: self didFailAd: error];
        }
    }
    else
    {
        [self.delegate customEventBanner: self didFailAd: error];
    }
}

#pragma mark - Utility Methods

+ (BOOL)hasEnqueuedAdForZoneIdentifier:(NSString *)zoneIdentifier
{
    @synchronized ( ALGlobalAdViewAdsLock )
    {
        return ALGlobalAdViewAds[zoneIdentifier].count > 0;
    }
}

+ (alnullable ALAd *)dequeueAdForZoneIdentifier:(NSString *)zoneIdentifier
{
    @synchronized ( ALGlobalAdViewAdsLock )
    {
        ALAd *preloadedAd;
        
        NSMutableArray<ALAd *> *preloadedAds = ALGlobalAdViewAds[zoneIdentifier];
        if ( preloadedAds.count > 0 )
        {
            preloadedAd = preloadedAds[0];
            [preloadedAds removeObjectAtIndex: 0];
        }
        
        return preloadedAd;
    }
}

+ (void)enqueueAd:(ALAd *)ad forZoneIdentifier:(NSString *)zoneIdentifier
{
    @synchronized ( ALGlobalAdViewAdsLock )
    {
        NSMutableArray<ALAd *> *preloadedAds = ALGlobalAdViewAds[zoneIdentifier];
        if ( !preloadedAds )
        {
            preloadedAds = [NSMutableArray array];
            ALGlobalAdViewAds[zoneIdentifier] = preloadedAds;
        }
        
        [preloadedAds addObject: ad];
    }
}

/**
 * Dynamically create an instance of ALAdView with a given zone without breaking backwards compatibility for publishers on older SDKs.
 */
- (ALAdView *)adViewWithAdSize:(ALAdSize *)adSize zoneIdentifier:(NSString *)zoneIdentifier
{
    // Prematurely create instance of ALAdView to store initialized one in later
    ALAdView *adView = [ALAdMobAdView alloc];
    
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

- (ALAdSize *)appLovinAdSizeFromRequestedSize:(GADAdSize)size
{
    if ( GADAdSizeEqualToSize(kGADAdSizeBanner, size ) || GADAdSizeEqualToSize(kGADAdSizeLargeBanner, size ) )
    {
        return [ALAdSize sizeBanner];
    }
    else if ( GADAdSizeEqualToSize(kGADAdSizeMediumRectangle, size) )
    {
        return [ALAdSize sizeMRec];
    }
    else if ( GADAdSizeEqualToSize(kGADAdSizeLeaderboard, size) )
    {
        return [ALAdSize sizeLeader];
    }
    // This is not a one of AdMob's predefined size
    else
    {
        CGSize frameSize = size.size;
        
        // Attempt to check for fluid size
        if ( CGRectGetWidth([UIScreen mainScreen].bounds) == frameSize.width )
        {
            CGFloat frameHeight = frameSize.height;
            if ( frameHeight == CGSizeFromGADAdSize(kGADAdSizeBanner).height || frameHeight == CGSizeFromGADAdSize(kGADAdSizeLargeBanner).height )
            {
                return [ALAdSize sizeBanner];
            }
            else if ( frameHeight == CGSizeFromGADAdSize(kGADAdSizeMediumRectangle).height )
            {
                return [ALAdSize sizeMRec];
            }
            else if ( frameHeight == CGSizeFromGADAdSize(kGADAdSizeLeaderboard).height )
            {
                return [ALAdSize sizeLeader];
            }
        }
        
        // Assume fluid width, and check for height with offset tolerance
        CGFloat offset = ABS(kALBannerStandardHeight - frameSize.height);
        if ( offset <= kALBannerHeightOffsetTolerance )
        {
            return [ALAdSize sizeBanner];
        }
    }
    
    [self log: @"Unable to retrieve AppLovin size from GADAdSize: %@", NSStringFromGADAdSize(size)];
    
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
        
        NSLog(@"AppLovinCustomEventBanner: %@", message);
    }
}

- (GADErrorCode)toAdMobErrorCode:(int)appLovinErrorCode
{
    if ( appLovinErrorCode == kALErrorCodeNoFill )
    {
        return kGADErrorMediationNoFill;
    }
    else if ( appLovinErrorCode == kALErrorCodeAdRequestNetworkTimeout )
    {
        return kGADErrorTimeout;
    }
    else if ( appLovinErrorCode == kALErrorCodeInvalidResponse )
    {
        return kGADErrorReceivedInvalidResponse;
    }
    else if ( appLovinErrorCode == kALErrorCodeUnableToRenderAd )
    {
        return kGADErrorServerError;
    }
    else
    {
        return kGADErrorInternalError;
    }
}

@end

@implementation AppLovinAdMobBannerDelegate

#pragma mark - Initialization

- (instancetype)initWithCustomEvent:(AppLovinCustomEventBanner *)parentCustomEvent
{
    self = [super init];
    if ( self )
    {
        self.parentCustomEvent = parentCustomEvent;
    }
    return self;
}

#pragma mark - Ad Display Delegate

- (void)ad:(ALAd *)ad wasDisplayedIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner displayed"];
}

- (void)ad:(ALAd *)ad wasHiddenIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner dismissed"];
}

- (void)ad:(ALAd *)ad wasClickedIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner clicked"];
    
    [self.parentCustomEvent.delegate customEventBannerWasClicked: self.parentCustomEvent];
    [self.parentCustomEvent.delegate customEventBannerWillLeaveApplication: self.parentCustomEvent];
}

@end

@implementation ALAdMobAdView @end

/**
 * This category provides a way to have an `ALAdView` to dynamically render an enqueued ad WHEN needed.
 */
@interface ALAdMobAdView (AdMob)
@property (nonatomic, copy, readonly) NSString *zoneIdentifier;
@end

@implementation ALAdMobAdView (AdMob)
@dynamic zoneIdentifier;

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    
    if ( self.window )
    {
        NSString *zoneIdentifier = ( HAS_ZONES_SUPPORT && self.zoneIdentifier ) ? self.zoneIdentifier : DEFAULT_ZONE;
        
        ALAd *preloadedAd = [AppLovinCustomEventBanner dequeueAdForZoneIdentifier: zoneIdentifier];
        if ( preloadedAd )
        {
            [self render: preloadedAd];
        }
        // Something is wrong... no preloaded ad provided... manually load an ad if none provided
        else
        {
            [self loadNextAd];
        }
    }
}

@end
