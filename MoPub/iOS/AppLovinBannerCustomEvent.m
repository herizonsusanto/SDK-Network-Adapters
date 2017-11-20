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

// Convenience macro for checking if AppLovin SDK has support for zones
#define HAS_ZONES_SUPPORT [[ALSdk shared].adService respondsToSelector: @selector(loadNextAdForZoneIdentifier:andNotify:)]
#define DEFAULT_ZONE @""

/**
 * The receiver object of the ALAdView's and ALAdService's delegates. This is used to prevent a retain cycle between the ALAdView and AppLovinBannerCustomEvent.
 */
@interface AppLovinMoPubBannerDelegate : NSObject<ALAdLoadDelegate, ALAdDisplayDelegate>
@property (nonatomic, weak) AppLovinBannerCustomEvent *parentCustomEvent;
- (instancetype)initWithCustomEvent:(AppLovinBannerCustomEvent *)parentCustomEvent;
@end

@interface AppLovinBannerCustomEvent()
@property (nonatomic, strong) ALAdView *adView;
@property (nonatomic,   copy) NSString *zoneIdentifier; // The zone identifier this instance of the custom event is loading for
@end

@implementation AppLovinBannerCustomEvent

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALMoPubMediationErrorDomain = @"com.applovin.sdk.mediation.mopub.errorDomain";

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

#pragma mark - MPBannerCustomEvent Overridden Methods

- (void)requestAdWithSize:(CGSize)size customEventInfo:(NSDictionary *)info
{
    [self log: @"Requesting AppLovin banner of size %@ with info: %@", NSStringFromCGSize(size), info];
    
    // Convert requested size to AppLovin Ad Size
    ALAdSize *appLovinAdSize = [self appLovinAdSizeFromRequestedSize: size];
    if ( appLovinAdSize )
    {
        [[ALSdk shared] setPluginVersion: @"MoPub-2.2"];
        
        // Zones support is available on AppLovin SDK 4.5.0 and higher
        if ( HAS_ZONES_SUPPORT && info[@"zone_id"] )
        {
            self.zoneIdentifier = info[@"zone_id"];
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
                self.adView = [[ALAdView alloc] initWithFrame: CGRectMake(0.0f, 0.0f, size.width, size.height)
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
        
        AppLovinMoPubBannerDelegate *delegate = [[AppLovinMoPubBannerDelegate alloc] initWithCustomEvent: self];
        self.adView.adDisplayDelegate = delegate;
        
        // If this is a default Zone, create the incentivized ad normally
        if ( [DEFAULT_ZONE isEqualToString: self.zoneIdentifier] )
        {
            [[ALSdk shared].adService loadNextAd: appLovinAdSize andNotify: delegate];
        }
        // Otherwise, use the Zones API
        else
        {
            // Dynamically load an ad for a given zone without breaking backwards compatibility for publishers on older SDKs
            [[ALSdk shared].adService performSelector: @selector(loadNextAdForZoneIdentifier:andNotify:)
                                           withObject: self.zoneIdentifier
                                           withObject: delegate];
        }
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
    // This is not a one of MoPub's predefined size
    else
    {
        // Assume fluid width, and check for height with offset tolerance
        CGFloat offset = ABS(kALBannerStandardHeight - size.height);
        if ( offset <= kALBannerHeightOffsetTolerance )
        {
            return [ALAdSize sizeBanner];
        }
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
    
    ALAdView *adView = self.parentCustomEvent.adView;
    
    if ( !adView.window )
    {
        [AppLovinBannerCustomEvent enqueueAd: ad forZoneIdentifier: self.parentCustomEvent.zoneIdentifier];
    }
    else
    {
        [adView render: ad];
    }
    
    [self.parentCustomEvent.delegate bannerCustomEvent: self.parentCustomEvent didLoadAd: self.parentCustomEvent.adView];
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    [self.parentCustomEvent log: @"Banner failed to load with error: %d", code];
    
    NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                         code: [self.parentCustomEvent toMoPubErrorCode: code]
                                     userInfo: nil];
    [self.parentCustomEvent.delegate bannerCustomEvent: self.parentCustomEvent didFailToLoadAdWithError: error];
    
    // TODO: Add support for backfilling on regular ad request if invalid zone entered
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

/**
 * This category provides a way to have an `ALAdView` to dynamically render an enqueued ad WHEN needed.
 */
@interface ALAdView (MoPub)
@property (nonatomic, copy, readonly) NSString *zoneIdentifier;
@end

@implementation ALAdView (MoPub)
@dynamic zoneIdentifier;

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    
    if ( self.window )
    {
        ALAd *preloadedAd = [AppLovinBannerCustomEvent dequeueAdForZoneIdentifier: self.zoneIdentifier];
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
