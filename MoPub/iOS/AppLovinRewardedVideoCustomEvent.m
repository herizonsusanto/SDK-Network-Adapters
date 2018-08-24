//
//  AppLovinRewardedVideoCustomEvent.m
//
//
//  Created by Thomas So on 5/21/17.
//
//

#import "AppLovinRewardedVideoCustomEvent.h"
#import "MPRewardedVideoReward.h"
#import "MPError.h"
#import "MoPub.h"
#import "MPLogging.h"

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALIncentivizedInterstitialAd.h"
    #import "ALPrivacySettings.h"
#endif

#define DEFAULT_ZONE @""

/**
 * This class guarantees that the count for each MoPub ad request, we get that same count of ads loaded.
 * So if a publisher loads 2 ads for a particular zone - we will honor both of those ad requests.
 */
@interface AppLovinRewardedCustomEventAdStorage : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<ALAd *> *> *ads;
- (BOOL)hasAdForZoneIdentifier:(NSString *)zoneIdentifier;
- (void)enqueueAd:(ALAd *)ad forZoneIdentifier:(NSString *)zoneIdentifier;
- (ALAd *)dequeueAdForZoneIdentifier:(NSString *)zoneIdentifier;
@end

// This class implementation with the old classname is left here for backwards compatibility purposes.
@implementation AppLovinRewardedCustomEvent
@end

@interface AppLovinRewardedVideoCustomEvent() <ALAdLoadDelegate, ALAdDisplayDelegate, ALAdVideoPlaybackDelegate, ALAdRewardDelegate>

@property (nonatomic, strong) ALSdk *sdk;
@property (nonatomic, strong) ALIncentivizedInterstitialAd *incent;
@property (nonatomic,   copy) NSString *zoneIdentifier;

@property (nonatomic, assign) BOOL fullyWatched;
@property (nonatomic, strong) MPRewardedVideoReward *reward;

@end

@implementation AppLovinRewardedVideoCustomEvent

static NSString *const kALMoPubMediationErrorDomain = @"com.applovin.sdk.mediation.mopub.errorDomain";

static AppLovinRewardedCustomEventAdStorage *ALRewardedCustomEventAdStorage;
static NSObject *ALRewardedCustomEventAdStorageLock;

#pragma mark - Class Initialization

+ (void)initialize
{
    [super initialize];
    
    ALRewardedCustomEventAdStorage = [[AppLovinRewardedCustomEventAdStorage alloc] init];
    ALRewardedCustomEventAdStorageLock = [[NSObject alloc] init];
}

#pragma mark - MPRewardedVideoCustomEvent Overridden Methods

- (void)requestRewardedVideoWithCustomEventInfo:(NSDictionary *)info
{
    [self log: @"Requesting AppLovin rewarded video with info: %@", info];
    
    // Collect and pass the user's consent from MoPub into the AppLovin SDK
    if ( [[MoPub sharedInstance] isGDPRApplicable] == MPBoolYes )
    {
        BOOL canCollectPersonalInfo = [[MoPub sharedInstance] canCollectPersonalInfo];
        [ALPrivacySettings setHasUserConsent: canCollectPersonalInfo];
    }
    
    self.sdk = [self SDKFromCustomEventInfo: info];
    
    if ( info[@"zone_id"] )
    {
        self.zoneIdentifier = info[@"zone_id"];

        // If we have zone id - we can load it via zone API
        [self.sdk.adService loadNextAdForZoneIdentifier: self.zoneIdentifier andNotify: self];
    }
    else
    {
        self.zoneIdentifier = DEFAULT_ZONE;
        
        // Create NEW instance of incentivized ad to load non-zone ad
        ALIncentivizedInterstitialAd *incent = [[ALIncentivizedInterstitialAd alloc] initWithSdk: self.sdk];
        [incent preloadAndNotify: self];
    }
}

- (BOOL)hasAdAvailable
{
    @synchronized ( ALRewardedCustomEventAdStorageLock )
    {
        return [ALRewardedCustomEventAdStorage hasAdForZoneIdentifier: self.zoneIdentifier];
    }
}

- (void)presentRewardedVideoFromViewController:(UIViewController *)viewController
{
    ALAd *ad;
    
    @synchronized ( ALRewardedCustomEventAdStorageLock )
    {
        // Retrieve ad
        ad = [ALRewardedCustomEventAdStorage dequeueAdForZoneIdentifier: self.zoneIdentifier];
    }
    
    if ( ad )
    {
        // Clear states
        self.reward = nil;
        self.fullyWatched = NO;
        
        // Hold reference to the displaying incent ad so it does not dealloc
        self.incent = [[ALIncentivizedInterstitialAd alloc] initWithSdk: self.sdk];
        self.incent.adVideoPlaybackDelegate = self;
        self.incent.adDisplayDelegate = self;
        [self.incent showOver: [UIApplication sharedApplication].keyWindow renderAd: ad andNotify: self];
    }
    else
    {
        [self log: @"Failed to show an AppLovin rewarded video before one was loaded"];
        
        NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                             code: kALErrorCodeUnableToRenderAd
                                         userInfo: @{NSLocalizedFailureReasonErrorKey : @"Adapter requested to display a rewarded video before one was loaded"}];
        
        [self.delegate rewardedVideoDidFailToPlayForCustomEvent: self error: error];
    }
}

- (void)handleCustomEventInvalidated { }
- (void)handleAdPlayedForCustomEventNetwork { }

#pragma mark - Ad Load Delegate

- (void)adService:(ALAdService *)adService didLoadAd:(ALAd *)ad
{
    [self log: @"Rewarded video did load ad: %@", ad.adIdNumber];
    
    @synchronized ( ALRewardedCustomEventAdStorageLock )
    {
        [ALRewardedCustomEventAdStorage enqueueAd: ad forZoneIdentifier: self.zoneIdentifier];
    }
            
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate rewardedVideoDidLoadAdForCustomEvent: self];
    });
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    [self log: @"Rewarded video failed to load with error: %d", code];
    
    NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                         code: [self toMoPubErrorCode: code]
                                     userInfo: nil];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate rewardedVideoDidFailToLoadAdForCustomEvent: self error: error];
    });
}

#pragma mark - Ad Display Delegate

- (void)ad:(ALAd *)ad wasDisplayedIn:(UIView *)view
{
    [self log: @"Rewarded video displayed"];
    
    [self.delegate rewardedVideoWillAppearForCustomEvent: self];
    [self.delegate rewardedVideoDidAppearForCustomEvent: self];
}

- (void)ad:(ALAd *)ad wasHiddenIn:(UIView *)view
{
    [self log: @"Rewarded video dismissed"];
    
    if ( self.fullyWatched && self.reward )
    {
        [self.delegate rewardedVideoShouldRewardUserForCustomEvent: self reward: self.reward];
    }
    
    [self.delegate rewardedVideoWillDisappearForCustomEvent: self];
    [self.delegate rewardedVideoDidDisappearForCustomEvent: self];
    
    self.incent = nil;
}

- (void)ad:(ALAd *)ad wasClickedIn:(UIView *)view
{
    [self log: @"Rewarded video clicked"];
    
    [self.delegate rewardedVideoDidReceiveTapEventForCustomEvent: self];
    [self.delegate rewardedVideoWillLeaveApplicationForCustomEvent: self];
}

#pragma mark - Video Playback Delegate

- (void)videoPlaybackBeganInAd:(ALAd *)ad
{
    [self log: @"Rewarded video video playback began"];
}

- (void)videoPlaybackEndedInAd:(ALAd *)ad atPlaybackPercent:(NSNumber *)percentPlayed fullyWatched:(BOOL)wasFullyWatched
{
    [self log: @"Rewarded video video playback ended at playback percent: %lu", percentPlayed.unsignedIntegerValue];
    
    self.fullyWatched = wasFullyWatched;
}

#pragma mark - Reward Delegate

- (void)rewardValidationRequestForAd:(ALAd *)ad didExceedQuotaWithResponse:(NSDictionary *)response
{
    [self log: @"Rewarded video validation request for ad did exceed quota with response: %@", response];
}

- (void)rewardValidationRequestForAd:(ALAd *)ad didFailWithError:(NSInteger)responseCode
{
    [self log: @"Rewarded video validation request for ad failed with error code: %ld", responseCode];
}

- (void)rewardValidationRequestForAd:(ALAd *)ad wasRejectedWithResponse:(NSDictionary *)response
{
    [self log: @"Rewarded video validation request was rejected with response: %@", response];
}

- (void)userDeclinedToViewAd:(ALAd *)ad
{
    [self log: @"User declined to view rewarded video"];
    
    [self.delegate rewardedVideoWillDisappearForCustomEvent: self];
    [self.delegate rewardedVideoDidDisappearForCustomEvent: self];
}

- (void)rewardValidationRequestForAd:(ALAd *)ad didSucceedWithResponse:(NSDictionary *)response
{
    NSNumber *amount = response[@"amount"];
    NSString *currency = response[@"currency"];
    
    [self log: @"Rewarded %@ %@", amount, currency];
    
    self.reward = [[MPRewardedVideoReward alloc] initWithCurrencyType: currency amount: amount];
}

#pragma mark - Utility Methods

- (void)log:(NSString *)format, ...
{
    va_list valist;
    va_start(valist, format);
    NSString *message = [[NSString alloc] initWithFormat: format arguments: valist];
    va_end(valist);
    
    MPLogDebug(@"AppLovinRewardedVideoCustomEvent: %@", message);
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

- (ALSdk *)SDKFromCustomEventInfo:(NSDictionary *)info
{
    NSString *SDKKey = info[@"sdk_key"];
    ALSdk *sdk = ( SDKKey.length > 0 ) ? [ALSdk sharedWithKey: SDKKey] : [ALSdk shared];
    
    [sdk setPluginVersion: @"MoPub-3.0.0"];
    [sdk setMediationProvider: ALMediationProviderMoPub];
    
    return sdk;
}

@end

@implementation AppLovinRewardedCustomEventAdStorage

- (instancetype)init
{
    self = [super init];
    if ( self )
    {
        self.ads = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)hasAdForZoneIdentifier:(NSString *)zoneIdentifier
{
    return [self adQueueForZoneIdentifier: zoneIdentifier].count > 0;
}

- (void)enqueueAd:(ALAd *)ad forZoneIdentifier:(NSString *)zoneIdentifier
{
    [[self adQueueForZoneIdentifier: zoneIdentifier] addObject: ad];
}

- (ALAd *)dequeueAdForZoneIdentifier:(NSString *)zoneIdentifier
{
    NSMutableArray<ALAd *> *adQueue = [self adQueueForZoneIdentifier: zoneIdentifier];
    ALAd *dequeuedAd = [adQueue firstObject];
    if ( dequeuedAd )
    {
        [adQueue removeObjectAtIndex: 0];
    }
    
    return dequeuedAd;
}

- (NSMutableArray<ALAd *> *)adQueueForZoneIdentifier:(NSString *)zoneIdentifier
{
    if ( self.ads[zoneIdentifier] )
    {
        return self.ads[zoneIdentifier];
    }
    else
    {
        NSMutableArray<ALAd *> *adQueue = [NSMutableArray array];
        self.ads[zoneIdentifier] = adQueue;
        
        return adQueue;
    }
}

@end
